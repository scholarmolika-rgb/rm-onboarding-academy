-- =====================================================================
-- RM Onboarding Academy — gating engine, escalations, sign-off
-- All business rules live in the database so no client can bypass them.
-- =====================================================================

-- ---------- Identity helpers ------------------------------------------
create or replace function me() returns uuid
language sql stable security definer set search_path = public as $$
  select id from profiles where user_id = auth.uid()
$$;

create or replace function my_role() returns app_role
language sql stable security definer set search_path = public as $$
  select role from profiles where user_id = auth.uid()
$$;

-- Is the caller allowed to see this trainee? (self, own mentor/manager/hr, leadership, admin)
create or replace function can_see_trainee(p_trainee uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles t, profiles c
    where t.id = p_trainee and c.user_id = auth.uid()
      and ( c.id = t.id
         or c.id in (t.mentor_id, t.manager_id, t.hr_id)
         or c.role in ('hr','leadership','admin') )
  )
$$;

create or replace function log_audit(p_action text, p_entity text, p_entity_id text, p_detail jsonb)
returns void language sql security definer set search_path = public as $$
  insert into audit_log(actor_id, action, entity, entity_id, detail)
  values (me(), p_action, p_entity, p_entity_id, p_detail)
$$;

-- ---------- Calendar: training day N skips weekends + cohort holidays ---
create or replace function training_day(p_trainee uuid, p_on date default current_date)
returns int language sql stable set search_path = public as $$
  select count(*)::int
  from profiles p
  join cohorts c on c.id = p.cohort_id
  cross join lateral generate_series(c.start_date, p_on, interval '1 day') d
  where p.id = p_trainee
    and extract(isodow from d) < 6
    and not (d::date = any(c.holidays))
$$;

-- add N working days (used for coaching SLAs)
create or replace function add_working_days(p_from timestamptz, p_days int)
returns timestamptz language plpgsql immutable as $$
declare d timestamptz := p_from; n int := 0;
begin
  while n < p_days loop
    d := d + interval '1 day';
    if extract(isodow from d) < 6 then n := n + 1; end if;
  end loop;
  return d;
end $$;

-- ---------- Outbox helper ---------------------------------------------
create or replace function enqueue_email(p_to text[], p_template text, p_payload jsonb, p_cc text[] default '{}')
returns void language sql security definer set search_path = public as $$
  insert into notification_outbox(to_emails, cc_emails, template, payload)
  values (p_to, p_cc, p_template, p_payload)
$$;

-- ---------- Phase unlock ----------------------------------------------
create or replace function unlock_next_phase(p_trainee uuid, p_assessment int, p_via text)
returns void language plpgsql security definer set search_path = public as $$
declare a assessments; t profiles;
begin
  select * into a from assessments where id = p_assessment;
  select * into t from profiles where id = p_trainee;

  if a.code = 'GATE_1' then
    update journeys set current_phase = 2, status = 'active',
           phase2_unlocked_at = now(), updated_at = now() where trainee_id = p_trainee;
  elsif a.code = 'GATE_2' then
    update journeys set current_phase = 3, status = 'active',
           phase3_unlocked_at = now(), updated_at = now() where trainee_id = p_trainee;
  elsif a.code = 'FINAL' then
    -- final passed: request tri-party sign-off
    update journeys set status = 'awaiting_assessment', updated_at = now() where trainee_id = p_trainee;
    perform enqueue_email(
      array(select email from profiles where id in (t.mentor_id, t.manager_id, t.hr_id)),
      'final_signoff_request',
      jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code));
    return;
  end if;

  perform enqueue_email(array[t.email], 'phase_unlocked',
    jsonb_build_object('trainee', t.full_name, 'assessment', a.title, 'via', p_via));
  perform log_audit('phase_unlocked', 'journey', p_trainee::text,
                    jsonb_build_object('assessment', a.code, 'via', p_via));
end $$;

-- ---------- Start an attempt (server picks randomised questions) --------
create or replace function start_attempt(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := me();
  a assessments; j journeys;
  v_no int; v_qids int[]; v_id uuid; v_open int;
begin
  select * into a from assessments where code = p_code;
  if a.id is null then raise exception 'Unknown assessment %', p_code; end if;
  select * into j from journeys where trainee_id = v_me;
  if j.trainee_id is null then raise exception 'No journey for caller'; end if;

  -- eligibility: right phase, not blocked
  if (p_code = 'GATE_1' and j.current_phase <> 1)
     or (p_code = 'GATE_2' and j.current_phase <> 2)
     or (p_code = 'FINAL'  and j.current_phase <> 3) then
    raise exception 'Assessment % is not open for your current phase', p_code;
  end if;
  if j.status in ('coaching','remediation','hr_review','certified','exited') then
    raise exception 'Assessment locked while status is %', j.status;
  end if;

  -- all mandatory learning for the phase must be complete
  select count(*) into v_open
  from learning_items li join modules m on m.id = li.module_id
  left join progress pr on pr.item_id = li.id and pr.trainee_id = v_me
  where m.phase_id = j.current_phase and li.mandatory
    and li.kind <> 'shadow_task'
    and coalesce(pr.status,'not_started') <> 'completed';
  if v_open > 0 then
    raise exception '% mandatory learning items still open', v_open;
  end if;

  select coalesce(max(attempt_no),0) + 1 into v_no
  from attempts where trainee_id = v_me and assessment_id = a.id;
  if v_no > a.max_attempts then raise exception 'Maximum attempts reached'; end if;

  select array_agg(id) into v_qids from (
    select id from questions where assessment_id = a.id and is_active
    order by random() limit a.question_count) q;

  insert into attempts(trainee_id, assessment_id, attempt_no, question_ids)
  values (v_me, a.id, v_no, v_qids) returning id into v_id;

  return jsonb_build_object(
    'attempt_id', v_id, 'attempt_no', v_no, 'duration_min', a.duration_min,
    'questions', (select jsonb_agg(jsonb_build_object('id', q.id, 'stem', q.stem, 'options', q.options))
                  from questions q where q.id = any(v_qids)));
end $$;

-- ---------- Submit & grade (answers never trusted from client) ----------
create or replace function submit_attempt(p_attempt uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := me();
  at attempts; a assessments;
  v_total int; v_correct int; v_pct numeric; v_mod jsonb;
begin
  select * into at from attempts where id = p_attempt and trainee_id = v_me for update;
  if at.id is null then raise exception 'Attempt not found'; end if;
  if at.submitted_at is not null then raise exception 'Attempt already submitted'; end if;
  select * into a from assessments where id = at.assessment_id;

  if now() > at.started_at + make_interval(mins => a.duration_min + 2) then
    -- late submissions are still graded but flagged in audit
    perform log_audit('late_submission','attempt',p_attempt::text,'{}');
  end if;

  select count(*), count(*) filter (where (p_answers ->> q.id::text)::int = q.answer_idx)
    into v_total, v_correct
  from questions q where q.id = any(at.question_ids);

  v_pct := round(100.0 * v_correct / greatest(v_total,1), 2);

  select jsonb_object_agg(code, pct) into v_mod from (
    select m.code, round(100.0 * count(*) filter (where (p_answers ->> q.id::text)::int = q.answer_idx)
                         / count(*), 0) pct
    from questions q join modules m on m.id = q.module_id
    where q.id = any(at.question_ids) group by m.code) s;

  update attempts set answers = p_answers, submitted_at = now(), score_pct = v_pct,
         passed = (v_pct >= a.pass_pct), module_scores = coalesce(v_mod,'{}')
  where id = p_attempt;

  perform handle_gate_outcome(p_attempt);

  return jsonb_build_object('score_pct', v_pct, 'pass_pct', a.pass_pct,
                            'passed', v_pct >= a.pass_pct, 'module_scores', v_mod);
end $$;

-- ---------- The gate: pass → unlock ; fail → escalate & coach ----------
create or replace function handle_gate_outcome(p_attempt uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  at attempts; a assessments; t profiles;
  v_esc uuid; r app_role; v_coach uuid; v_emails text[];
begin
  select * into at from attempts where id = p_attempt;
  select * into a  from assessments where id = at.assessment_id;
  select * into t  from profiles where id = at.trainee_id;

  perform log_audit('attempt_graded','attempt',p_attempt::text,
    jsonb_build_object('code',a.code,'score',at.score_pct,'passed',at.passed,'attempt_no',at.attempt_no));

  if at.passed then
    perform unlock_next_phase(t.id, a.id, 'score');
    return;
  end if;

  -- Final attempt exhausted → HR performance review (real-world guardrail)
  if at.attempt_no >= a.max_attempts then
    update journeys set status = 'hr_review', updated_at = now() where trainee_id = t.id;
    perform enqueue_email(
      array(select email from profiles where id in (t.hr_id, t.manager_id)),
      'hr_review_required',
      jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code,
                         'assessment', a.title, 'score', at.score_pct, 'attempts', at.attempt_no));
    return;
  end if;

  -- Open escalation: one 1-day coaching session per required role
  insert into escalations(trainee_id, attempt_id, assessment_id, sla_due)
  values (t.id, at.id, a.id, add_working_days(now(), array_length(a.coach_roles,1) + 2))
  returning id into v_esc;

  foreach r in array a.coach_roles loop
    v_coach := case r when 'mentor' then t.mentor_id
                      when 'reporting_manager' then t.manager_id
                      when 'hr' then t.hr_id end;
    if v_coach is not null then
      insert into coaching_sessions(escalation_id, coach_id, coach_role, scheduled_on)
      values (v_esc, v_coach, r,
              (add_working_days(now(), 1 + array_position(a.coach_roles, r) - 1))::date);
    end if;
  end loop;

  update journeys set status = 'coaching', updated_at = now() where trainee_id = t.id;
  update escalations set state = 'coaching' where id = v_esc;

  select array_agg(p.email) into v_emails
  from coaching_sessions cs join profiles p on p.id = cs.coach_id
  where cs.escalation_id = v_esc;

  -- one email to all coaches (Mentor, Reporting Manager, HR as configured)
  perform enqueue_email(v_emails, 'gate_failed_coaching_required',
    jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code, 'branch', t.branch,
                       'assessment', a.title, 'score', at.score_pct, 'pass_pct', a.pass_pct,
                       'module_scores', at.module_scores, 'escalation_id', v_esc,
                       'sla_due', (select sla_due from escalations where id = v_esc)));
  -- supportive note to the trainee (no score shaming)
  perform enqueue_email(array[t.email], 'trainee_coaching_scheduled',
    jsonb_build_object('trainee', t.full_name, 'assessment', a.title));
end $$;

-- ---------- Coach records outcome of their 1-day session ---------------
create or replace function record_coaching(p_session uuid, p_decision coach_decision,
                                           p_notes text, p_repeat_modules int[] default '{}')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  cs coaching_sessions; e escalations; at attempts; t profiles;
  v_pending int; v_repeat int; v_mods int[];
begin
  select * into cs from coaching_sessions where id = p_session for update;
  if cs.id is null or cs.coach_id <> me() then raise exception 'Not your coaching session'; end if;
  if cs.decision is not null then raise exception 'Decision already recorded'; end if;
  if coalesce(length(trim(p_notes)),0) < 30 then
    raise exception 'Coaching notes must be at least 30 characters (audit requirement)';
  end if;

  update coaching_sessions set decision = p_decision, notes = p_notes,
         repeat_modules = coalesce(p_repeat_modules,'{}'), completed_at = now()
  where id = p_session;
  perform log_audit('coaching_recorded','coaching_session',p_session::text,
                    jsonb_build_object('decision',p_decision,'modules',p_repeat_modules));

  select * into e from escalations where id = cs.escalation_id for update;
  select count(*) filter (where decision is null),
         count(*) filter (where decision = 'repeat')
    into v_pending, v_repeat
  from coaching_sessions where escalation_id = e.id;

  if v_pending > 0 then
    return jsonb_build_object('status','waiting_for_other_coaches','pending',v_pending);
  end if;

  select * into t from profiles where id = e.trainee_id;

  -- Policy: any coach asking for repeat → repeat (conservative, bank-grade)
  if v_repeat > 0 then
    select array_agg(distinct m) into v_mods
    from coaching_sessions, unnest(repeat_modules) m where escalation_id = e.id;

    if v_mods is null then   -- coaches said repeat but named nothing → weakest modules (<70%)
      select * into at from attempts where id = e.attempt_id;
      select array_agg(m.id) into v_mods
      from jsonb_each_text(at.module_scores) s join modules m on m.code = s.key
      where s.value::numeric < 70;
    end if;

    insert into remediation_assignments(trainee_id, escalation_id, module_id, due_on)
    select e.trainee_id, e.id, m, (add_working_days(now(), 3))::date
    from unnest(coalesce(v_mods,'{}')) m on conflict do nothing;

    update escalations set state = 'decided', outcome = 'repeat', closed_at = now() where id = e.id;
    update journeys set status = 'remediation', updated_at = now() where trainee_id = e.trainee_id;
    perform enqueue_email(array[t.email], 'remediation_assigned',
      jsonb_build_object('trainee', t.full_name, 'modules',
        (select jsonb_agg(title) from modules where id = any(coalesce(v_mods,'{}')))));
    return jsonb_build_object('status','remediation','modules',v_mods);
  else
    update escalations set state = 'decided', outcome = 'pass', closed_at = now() where id = e.id;
    perform unlock_next_phase(e.trainee_id, e.assessment_id, 'coach_pass');
    return jsonb_build_object('status','passed_by_coaches');
  end if;
end $$;

-- ---------- Remediation complete → re-test opens -----------------------
create or replace function complete_remediation(p_assignment uuid)
returns void language plpgsql security definer set search_path = public as $$
declare ra remediation_assignments; v_open int;
begin
  select * into ra from remediation_assignments where id = p_assignment;
  if ra.trainee_id <> me() and my_role() not in ('mentor','hr','admin') then
    raise exception 'Not allowed';
  end if;
  update remediation_assignments set completed_at = now() where id = p_assignment;
  select count(*) into v_open from remediation_assignments
  where escalation_id = ra.escalation_id and completed_at is null;
  if v_open = 0 then
    update journeys set status = 'active', updated_at = now() where trainee_id = ra.trainee_id;
    update escalations set state = 'closed' where id = ra.escalation_id;
  end if;
end $$;

-- ---------- Day-30 tri-party sign-off → certification -------------------
create or replace function sign_off(p_trainee uuid, p_approved boolean, p_comments text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t profiles; v_role app_role; v_final_passed boolean; v_done int; v_rejected int;
begin
  select * into t from profiles where id = p_trainee;
  v_role := case me() when t.mentor_id then 'mentor'::app_role
                      when t.manager_id then 'reporting_manager'::app_role
                      when t.hr_id then 'hr'::app_role end;
  if v_role is null then raise exception 'You are not a signatory for this trainee'; end if;

  select exists(select 1 from attempts at join assessments a on a.id = at.assessment_id
                where at.trainee_id = p_trainee and a.code = 'FINAL' and at.passed)
    into v_final_passed;
  if not v_final_passed then raise exception 'Final assessment not yet passed'; end if;

  insert into signoffs(trainee_id, role, signer_id, approved, comments)
  values (p_trainee, v_role, me(), p_approved, p_comments)
  on conflict (trainee_id, role) do update
    set approved = excluded.approved, comments = excluded.comments, signed_at = now();

  select count(*) filter (where approved), count(*) filter (where not approved)
    into v_done, v_rejected from signoffs where trainee_id = p_trainee;

  if v_rejected > 0 then
    update journeys set status = 'hr_review', updated_at = now() where trainee_id = p_trainee;
    return jsonb_build_object('status','hr_review');
  elsif v_done = 3 then
    update journeys set status = 'certified', certified_at = now(), updated_at = now()
    where trainee_id = p_trainee;
    perform enqueue_email(
      array(select email from profiles where id in (t.id, t.mentor_id, t.manager_id, t.hr_id)),
      'certified', jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code));
    perform log_audit('certified','journey',p_trainee::text,'{}');
    return jsonb_build_object('status','certified');
  end if;
  return jsonb_build_object('status','awaiting_other_signatories','approved',v_done);
end $$;

-- ---------- Attrition early-warning score (recomputed nightly) ----------
-- Blends assessment gaps, coaching events, inactivity and pulse-survey signals.
create or replace function refresh_risk_scores() returns void
language sql security definer set search_path = public as $$
  update journeys j set risk_score = least(100, greatest(0,
      coalesce((select 40 - avg(score_pct)/2.5 from attempts where trainee_id = j.trainee_id and submitted_at is not null),0)
    + 15 * (select count(*) from escalations where trainee_id = j.trainee_id)
    + coalesce((select 10 * (5 - avg((confidence + belonging)/2.0)) from pulse_surveys
                where trainee_id = j.trainee_id and created_at > now() - interval '10 days'),0)
    + case when (select max(completed_at) from progress where trainee_id = j.trainee_id)
                < now() - interval '3 days' then 15 else 0 end
  )), updated_at = now()
  where j.status not in ('certified','exited')
$$;

-- ---------- Create journey automatically for every trainee --------------
create or replace function trg_profile_journey() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'trainee' then
    insert into journeys(trainee_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;
create trigger profile_journey after insert on profiles
for each row execute function trg_profile_journey();

-- ---------- Link Supabase auth user → pre-provisioned profile by email --
create or replace function trg_link_auth_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update profiles set user_id = new.id where lower(email) = lower(new.email) and user_id is null;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function trg_link_auth_user();
