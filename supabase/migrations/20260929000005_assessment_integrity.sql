-- =====================================================================
-- RM Onboarding Academy — Assessment integrity
-- Goal: the score must measure what the trainee knows, not what an AI
-- tool (or a colleague) knows. No single control stops a determined
-- cheat, so this layers: design → delivery → detection → human verification.
--
--  1. Delivery: one question at a time, served and timed by the SERVER,
--     options shuffled per trainee, no going back, answer key never sent.
--  2. Personalised questions: calculation "families" with different numbers
--     per attempt (answers cannot be shared or pre-computed).
--  3. Signals: tab/focus loss, paste, fullscreen exit, IP change, answers
--     too fast to be real, identical wrong-answer patterns between trainees.
--  4. Humans decide: a high integrity score never auto-fails anyone. It
--     holds the result and asks the mentor for a 20-minute verification
--     viva. Confirmed → result stands. Voided → supervised re-sit + HR
--     conduct review (the voided attempt does not use up an attempt).
--  5. The Academy chatbot refuses to answer while the trainee has a test open.
-- =====================================================================

alter table assessments
  add column secure_delivery            boolean  not null default true,
  add column seconds_per_question       smallint not null default 90,
  add column integrity_review_threshold smallint not null default 40;

alter table questions
  add column family  text,                    -- variants of one question; one per attempt
  add column is_calc boolean not null default false;

alter table attempts
  add column session_token   uuid,
  add column declaration_at  timestamptz,
  add column client_ip       text,
  add column user_agent      text,
  add column integrity_score numeric(5,2),
  add column integrity_flags jsonb not null default '{}',
  add column review_state    text not null default 'clear'
    check (review_state in ('clear','review','verified','voided'));

alter table journeys add column supervised_only boolean not null default false;

-- Scheduled sitting windows (a proctored branch/test-centre slot or remote-proctored slot)
create table assessment_windows (
  id            uuid primary key default gen_random_uuid(),
  cohort_id     uuid not null references cohorts(id) on delete cascade,
  assessment_id int  not null references assessments(id),
  opens_at      timestamptz not null,
  closes_at     timestamptz not null,
  mode          text not null check (mode in ('proctored_centre','remote_proctored')),
  venue         text,
  proctor_id    uuid references profiles(id)
);

-- Every question served, with the server's clock (the client's clock is never trusted)
create table attempt_answers (
  attempt_id    uuid not null references attempts(id) on delete cascade,
  seq           smallint not null,
  question_id   int not null references questions(id),
  option_order  smallint[] not null,   -- display position → original option index
  served_at     timestamptz not null default now(),
  answered_at   timestamptz,
  chosen_idx    smallint,              -- ORIGINAL option index
  within_time   boolean,
  primary key (attempt_id, seq)
);

-- Browser behaviour during the test
create table attempt_events (
  id          bigserial primary key,
  attempt_id  uuid not null references attempts(id) on delete cascade,
  trainee_id  uuid not null references profiles(id) on delete cascade,
  kind        text not null check (kind in ('focus_lost','fullscreen_exit','paste','copy',
                'context_menu','devtools','offline','ip_changed','resumed','second_session',
                'assistant_during_test')),
  seq         smallint,
  detail      jsonb not null default '{}',
  at          timestamptz not null default now()
);
create index on attempt_events(attempt_id);

create table integrity_reviews (
  id           uuid primary key default gen_random_uuid(),
  attempt_id   uuid unique not null references attempts(id) on delete cascade,
  reviewer_id  uuid references profiles(id),
  outcome      text check (outcome in ('confirmed','voided')),
  notes        text,
  sla_due      timestamptz not null,
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz
);

-- Oral checks: verification vivas and the Day-30 certification viva
create table vivas (
  id          uuid primary key default gen_random_uuid(),
  trainee_id  uuid not null references profiles(id) on delete cascade,
  assessor_id uuid not null references profiles(id),
  stage       text not null check (stage in ('GATE_1','GATE_2','FINAL','INTEGRITY')),
  score       smallint not null check (score between 1 and 5),
  notes       text not null,
  at          timestamptz not null default now()
);

alter table assessment_windows enable row level security;
alter table attempt_answers    enable row level security;
alter table attempt_events     enable row level security;
alter table integrity_reviews  enable row level security;
alter table vivas              enable row level security;
create policy windows_read on assessment_windows for select to authenticated using (true);
-- trainees never read attempt_answers directly (it holds option maps); coaches/HR may
create policy answers_read on attempt_answers for select to authenticated
  using (my_role() in ('mentor','reporting_manager','hr','admin')
         and exists (select 1 from attempts a where a.id = attempt_id and can_see_trainee(a.trainee_id)));
create policy events_read on attempt_events for select to authenticated
  using (my_role() in ('mentor','reporting_manager','hr','admin') and can_see_trainee(trainee_id));
create policy reviews_read on integrity_reviews for select to authenticated
  using (exists (select 1 from attempts a where a.id = attempt_id
                 and can_see_trainee(a.trainee_id) and my_role() <> 'trainee'));
create policy vivas_read on vivas for select to authenticated using (can_see_trainee(trainee_id));

-- ---------- helpers ----------------------------------------------------
create or replace function client_ip() returns text language plpgsql stable as $$
begin
  return split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for',''), ',', 1);
exception when others then return null;
end $$;

create or replace function has_open_attempt(p_trainee uuid default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from attempts
                 where trainee_id = coalesce(p_trainee, me())
                   and submitted_at is null and started_at > now() - interval '3 hours')
$$;

create or replace function valid_attempts(p_trainee uuid, p_assessment int) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from attempts
  where trainee_id = p_trainee and assessment_id = p_assessment
    and submitted_at is not null and review_state <> 'voided'
$$;

-- ---------- start_attempt (replaces the Day-1 version) ------------------
create or replace function start_attempt(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := me();
  a assessments; j journeys; t profiles;
  v_no int; v_qids int[]; v_id uuid; v_open int; v_token uuid := gen_random_uuid();
  v_has_windows boolean; v_mode text;
begin
  select * into a from assessments where code = p_code;
  if a.id is null then raise exception 'Unknown assessment %', p_code; end if;
  select * into j from journeys where trainee_id = v_me;
  select * into t from profiles where id = v_me;
  if j.trainee_id is null then raise exception 'No journey for caller'; end if;

  if (p_code = 'GATE_1' and j.current_phase <> 1) or (p_code = 'GATE_2' and j.current_phase <> 2)
     or (p_code = 'FINAL' and j.current_phase <> 3) then
    raise exception 'Assessment % is not open for your current phase', p_code;
  end if;
  if j.status in ('coaching','remediation','hr_review','certified','exited') then
    raise exception 'Assessment locked while status is %', j.status;
  end if;
  if exists (select 1 from attempts at join integrity_reviews r on r.attempt_id = at.id
             where at.trainee_id = v_me and r.outcome is null) then
    raise exception 'A previous attempt is awaiting verification by your mentor';
  end if;
  if has_open_attempt(v_me) then
    raise exception 'You already have an assessment in progress on another tab or device';
  end if;

  -- sitting window (if the cohort has windows for this assessment)
  select exists(select 1 from assessment_windows where cohort_id = t.cohort_id and assessment_id = a.id)
    into v_has_windows;
  if v_has_windows or j.supervised_only then
    select mode into v_mode from assessment_windows
    where cohort_id = t.cohort_id and assessment_id = a.id and now() between opens_at and closes_at
      and (not j.supervised_only or mode = 'proctored_centre')
    limit 1;
    if v_mode is null then
      raise exception 'No open % sitting window for you right now', case when j.supervised_only then 'supervised' else '' end;
    end if;
  end if;

  select count(*) into v_open
  from learning_items li join modules m on m.id = li.module_id
  left join progress pr on pr.item_id = li.id and pr.trainee_id = v_me
  where m.phase_id = j.current_phase and li.mandatory and li.kind <> 'shadow_task'
    and coalesce(pr.status,'not_started') <> 'completed';
  if v_open > 0 then raise exception '% mandatory learning items still open', v_open; end if;

  if valid_attempts(v_me, a.id) >= a.max_attempts then raise exception 'Maximum attempts reached'; end if;
  select coalesce(max(attempt_no),0) + 1 into v_no from attempts where trainee_id = v_me and assessment_id = a.id;

  -- one random variant per family, then a random subset in random order
  select array_agg(id) into v_qids from (
    select id from (
      select distinct on (coalesce(family, 'q' || id)) id
      from questions where assessment_id = a.id and is_active
      order by coalesce(family, 'q' || id), random()) f
    order by random() limit a.question_count) q;

  insert into attempts(trainee_id, assessment_id, attempt_no, question_ids, session_token, client_ip)
  values (v_me, a.id, v_no, v_qids, v_token, client_ip()) returning id into v_id;

  if a.secure_delivery then
    return jsonb_build_object('attempt_id', v_id, 'attempt_no', v_no, 'session_token', v_token,
      'total', array_length(v_qids,1), 'seconds_per_question', a.seconds_per_question,
      'secure', true, 'declaration_required', true);
  end if;
  -- practice / legacy mode: whole paper at once (no answer key)
  return jsonb_build_object('attempt_id', v_id, 'attempt_no', v_no, 'duration_min', a.duration_min, 'secure', false,
    'questions', (select jsonb_agg(jsonb_build_object('id', q.id, 'stem', q.stem, 'options', q.options))
                  from questions q where q.id = any(v_qids)));
end $$;

-- ---------- honour code ------------------------------------------------
create or replace function accept_declaration(p_attempt uuid, p_token uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update attempts set declaration_at = now(), user_agent = left(coalesce(
      current_setting('request.headers', true)::json ->> 'user-agent',''), 300)
  where id = p_attempt and trainee_id = me() and session_token = p_token and submitted_at is null;
  if not found then raise exception 'Attempt not found'; end if;
  perform log_audit('declaration_accepted','attempt',p_attempt::text,'{}');
end $$;

-- ---------- one question at a time ------------------------------------
create or replace function serve_question(p_attempt uuid, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  at attempts; a assessments; last attempt_answers; q questions;
  v_seq int; v_order smallint[]; v_left numeric; v_ip text := client_ip();
begin
  select * into at from attempts where id = p_attempt and trainee_id = me() for update;
  if at.id is null or at.submitted_at is not null then raise exception 'Attempt not open'; end if;
  if at.session_token is distinct from p_token then
    insert into attempt_events(attempt_id, trainee_id, kind) values (at.id, at.trainee_id, 'second_session');
    raise exception 'This test is open in another session';
  end if;
  if at.declaration_at is null then raise exception 'Accept the honour declaration first'; end if;
  select * into a from assessments where id = at.assessment_id;
  if v_ip is not null and v_ip <> '' and at.client_ip is not null and v_ip <> at.client_ip then
    insert into attempt_events(attempt_id, trainee_id, kind, detail)
    values (at.id, at.trainee_id, 'ip_changed', jsonb_build_object('from', at.client_ip, 'to', v_ip));
    update attempts set client_ip = v_ip where id = at.id;
  end if;

  select * into last from attempt_answers where attempt_id = at.id order by seq desc limit 1;
  if last.attempt_id is not null and last.answered_at is null then
    v_left := extract(epoch from (last.served_at + make_interval(secs => a.seconds_per_question) - now()));
    if v_left > 0 then     -- page refresh: same question, same clock (no extra time)
      insert into attempt_events(attempt_id, trainee_id, kind, seq) values (at.id, at.trainee_id, 'resumed', last.seq);
      select * into q from questions where id = last.question_id;
      return jsonb_build_object('seq', last.seq, 'total', array_length(at.question_ids,1),
        'stem', q.stem, 'options', (select jsonb_agg(q.options -> o order by ord)
                                     from unnest(last.option_order) with ordinality u(o, ord)),
        'seconds_left', floor(v_left));
    end if;
    update attempt_answers set within_time = false where attempt_id = at.id and seq = last.seq; -- timed out
  end if;

  v_seq := coalesce(last.seq, 0) + 1;
  if v_seq > array_length(at.question_ids,1) then return jsonb_build_object('done', true); end if;

  select * into q from questions where id = at.question_ids[v_seq];
  select array_agg(i::smallint order by random()) into v_order
  from generate_series(0, jsonb_array_length(q.options) - 1) i;
  insert into attempt_answers(attempt_id, seq, question_id, option_order)
  values (at.id, v_seq, q.id, v_order);

  return jsonb_build_object('seq', v_seq, 'total', array_length(at.question_ids,1), 'stem', q.stem,
    'options', (select jsonb_agg(q.options -> o order by ord) from unnest(v_order) with ordinality u(o, ord)),
    'seconds_left', a.seconds_per_question);
end $$;

create or replace function answer_question(p_attempt uuid, p_token uuid, p_seq int, p_display_idx int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare at attempts; a assessments; aa attempt_answers; v_ok boolean;
begin
  select * into at from attempts where id = p_attempt and trainee_id = me();
  if at.id is null or at.submitted_at is not null then raise exception 'Attempt not open'; end if;
  if at.session_token is distinct from p_token then raise exception 'This test is open in another session'; end if;
  select * into a from assessments where id = at.assessment_id;
  select * into aa from attempt_answers where attempt_id = p_attempt and seq = p_seq for update;
  if aa.attempt_id is null then raise exception 'Question not served'; end if;
  if aa.answered_at is not null or aa.within_time = false then raise exception 'Question already closed'; end if;
  if p_seq <> (select max(seq) from attempt_answers where attempt_id = p_attempt) then
    raise exception 'You cannot go back to an earlier question';
  end if;
  v_ok := now() <= aa.served_at + make_interval(secs => a.seconds_per_question + 5);  -- 5 s network grace
  update attempt_answers
     set answered_at = now(), within_time = v_ok,
         chosen_idx = case when v_ok and p_display_idx between 0 and array_length(option_order,1)-1
                           then option_order[p_display_idx + 1] end
   where attempt_id = p_attempt and seq = p_seq;
  return jsonb_build_object('recorded', v_ok);
end $$;

create or replace function log_attempt_event(p_attempt uuid, p_kind text, p_seq int default null, p_detail jsonb default '{}')
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into attempt_events(attempt_id, trainee_id, kind, seq, detail)
  select id, trainee_id, p_kind, p_seq, coalesce(p_detail,'{}')
  from attempts where id = p_attempt and trainee_id = me() and submitted_at is null;
end $$;

-- ---------- integrity score (0-100) — evidence for a human, never a verdict --
create or replace function compute_integrity(p_attempt uuid)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  at attempts; t profiles; v_flags jsonb := '{}'; v_score numeric := 0; n int;
begin
  select * into at from attempts where id = p_attempt;
  select * into t from profiles where id = at.trainee_id;

  select count(*) into n from attempt_events where attempt_id = p_attempt and kind = 'focus_lost';
  if n > 0 then v_flags := v_flags || jsonb_build_object('focus_lost', n);
                v_score := v_score + least(45, greatest(0, n - 1) * 15); end if;  -- first one forgiven
  select count(*) into n from attempt_events where attempt_id = p_attempt and kind in ('paste','copy');
  if n > 0 then v_flags := v_flags || jsonb_build_object('copy_paste', n); v_score := v_score + 30; end if;
  select count(*) into n from attempt_events where attempt_id = p_attempt and kind = 'fullscreen_exit';
  if n > 0 then v_flags := v_flags || jsonb_build_object('fullscreen_exit', n); v_score := v_score + least(30, n * 15); end if;
  select count(*) into n from attempt_events where attempt_id = p_attempt and kind in ('ip_changed','second_session','devtools');
  if n > 0 then v_flags := v_flags || jsonb_build_object('session_anomaly', n); v_score := v_score + 25; end if;

  select count(*) into n from attempt_events where attempt_id = p_attempt and kind = 'assistant_during_test';
  if n > 0 then v_flags := v_flags || jsonb_build_object('assistant_during_test', n); v_score := v_score + 20; end if;

  -- correct answers on calculation / hard questions faster than a person can read and compute
  select count(*) into n
  from attempt_answers aa join questions q on q.id = aa.question_id
  where aa.attempt_id = p_attempt and aa.chosen_idx = q.answer_idx
    and (q.is_calc or q.difficulty = 3)
    and aa.answered_at - aa.served_at < interval '8 seconds';
  if n >= 2 then v_flags := v_flags || jsonb_build_object('implausibly_fast_correct', n); v_score := v_score + least(30, n * 10); end if;

  -- long silent pauses followed by a correct answer on most questions (look-up pattern)
  select count(*) into n
  from attempt_answers aa join questions q on q.id = aa.question_id
  where aa.attempt_id = p_attempt and aa.chosen_idx = q.answer_idx
    and aa.answered_at - aa.served_at > interval '75 seconds' and not q.is_calc;
  if n >= 4 then v_flags := v_flags || jsonb_build_object('slow_correct_pattern', n); v_score := v_score + 15; end if;

  -- same WRONG choices as another trainee in the cohort (answer sharing)
  select coalesce(max(shared),0) into n from (
    select o.id, count(*) shared
    from attempt_answers mine
    join questions q on q.id = mine.question_id and mine.chosen_idx <> q.answer_idx
    join attempts o on o.assessment_id = at.assessment_id and o.id <> at.id and o.submitted_at is not null
    join profiles op on op.id = o.trainee_id and op.cohort_id = t.cohort_id
    join attempt_answers theirs on theirs.attempt_id = o.id and theirs.question_id = mine.question_id
                               and theirs.chosen_idx = mine.chosen_idx
    where mine.attempt_id = at.id group by o.id) s;
  if n >= 3 then v_flags := v_flags || jsonb_build_object('shared_wrong_answers', n); v_score := v_score + 25; end if;

  v_score := least(100, v_score);
  update attempts set integrity_score = v_score, integrity_flags = v_flags where id = p_attempt;
  return v_score;
end $$;

-- ---------- submit (replaces the Day-1 version) --------------------------
create or replace function submit_attempt(p_attempt uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := me(); at attempts; a assessments; t profiles;
  v_total int; v_correct int; v_pct numeric; v_mod jsonb; v_ans jsonb; v_int numeric;
begin
  select * into at from attempts where id = p_attempt and trainee_id = v_me for update;
  if at.id is null then raise exception 'Attempt not found'; end if;
  if at.submitted_at is not null then raise exception 'Attempt already submitted'; end if;
  select * into a from assessments where id = at.assessment_id;
  select * into t from profiles where id = v_me;

  if a.secure_delivery then
    if p_answers is not null then raise exception 'Answers are recorded question by question for this assessment'; end if;
    update attempt_answers set within_time = false where attempt_id = p_attempt and answered_at is null;
    select coalesce(jsonb_object_agg(question_id::text, chosen_idx), '{}') into v_ans
    from attempt_answers where attempt_id = p_attempt and within_time and chosen_idx is not null;
  else
    v_ans := coalesce(p_answers, '{}');
  end if;

  v_total := array_length(at.question_ids, 1);   -- unanswered or late = wrong
  select count(*) filter (where (v_ans ->> q.id::text)::int = q.answer_idx) into v_correct
  from questions q where q.id = any(at.question_ids);
  v_pct := round(100.0 * v_correct / greatest(v_total,1), 2);

  select jsonb_object_agg(code, pct) into v_mod from (
    select m.code, round(100.0 * count(*) filter (where (v_ans ->> q.id::text)::int = q.answer_idx) / count(*), 0) pct
    from questions q join modules m on m.id = q.module_id
    where q.id = any(at.question_ids) group by m.code) s;

  update attempts set answers = v_ans, submitted_at = now(), score_pct = v_pct,
         passed = (v_pct >= a.pass_pct), module_scores = coalesce(v_mod,'{}')
  where id = p_attempt;

  v_int := compute_integrity(p_attempt);

  -- A PASS with a high integrity score is held for a human check; a FAIL goes to coaching as usual
  if v_pct >= a.pass_pct and v_int >= a.integrity_review_threshold then
    update attempts set review_state = 'review' where id = p_attempt;
    insert into integrity_reviews(attempt_id, sla_due) values (p_attempt, add_working_days(now(), 2));
    perform log_audit('integrity_hold','attempt',p_attempt::text,
                      jsonb_build_object('score',v_pct,'integrity',v_int));
    perform enqueue_email(array(select email from profiles where id in (t.mentor_id)),
      'integrity_review_required',
      jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code, 'assessment', a.title,
                         'flags', (select integrity_flags from attempts where id = p_attempt),
                         'attempt_id', p_attempt),
      array(select email from profiles where id = t.hr_id));
    perform enqueue_email(array[t.email], 'result_under_review',
      jsonb_build_object('trainee', t.full_name, 'assessment', a.title));
    return jsonb_build_object('score_pct', v_pct, 'pass_pct', a.pass_pct, 'passed', true,
                              'status', 'under_review', 'module_scores', v_mod);
  end if;

  perform handle_gate_outcome(p_attempt);
  return jsonb_build_object('score_pct', v_pct, 'pass_pct', a.pass_pct,
                            'passed', v_pct >= a.pass_pct, 'module_scores', v_mod);
end $$;

-- ---------- mentor/HR verifies a held result through a short viva ---------
create or replace function verify_attempt(p_attempt uuid, p_outcome text, p_viva_score int, p_notes text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare at attempts; t profiles; a assessments;
begin
  select * into at from attempts where id = p_attempt for update;
  select * into t from profiles where id = at.trainee_id;
  select * into a from assessments where id = at.assessment_id;
  if me() not in (t.mentor_id, t.hr_id) then raise exception 'Only the mentor or HR partner can verify'; end if;
  if at.review_state <> 'review' then raise exception 'Attempt is not awaiting verification'; end if;
  if p_outcome not in ('confirmed','voided') then raise exception 'Outcome must be confirmed or voided'; end if;
  if coalesce(length(trim(p_notes)),0) < 30 then raise exception 'Notes must be at least 30 characters'; end if;

  insert into vivas(trainee_id, assessor_id, stage, score, notes) values (t.id, me(), 'INTEGRITY', p_viva_score, p_notes);
  update integrity_reviews set outcome = p_outcome, reviewer_id = me(), notes = p_notes, reviewed_at = now()
  where attempt_id = p_attempt;
  perform log_audit('integrity_'||p_outcome,'attempt',p_attempt::text,jsonb_build_object('viva',p_viva_score));

  if p_outcome = 'confirmed' then
    update attempts set review_state = 'verified' where id = p_attempt;
    perform handle_gate_outcome(p_attempt);           -- normal unlock
    return jsonb_build_object('status','confirmed');
  end if;

  -- voided: result removed, re-sit only in a supervised centre, conduct review by HR
  update attempts set review_state = 'voided', passed = false where id = p_attempt;
  update journeys set supervised_only = true, updated_at = now() where trainee_id = t.id;
  perform enqueue_email(array(select email from profiles where id in (t.hr_id, t.manager_id)),
    'attempt_voided', jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code,
                                         'assessment', a.title, 'notes', p_notes));
  perform enqueue_email(array[t.email], 'resit_supervised', jsonb_build_object('trainee', t.full_name, 'assessment', a.title));
  return jsonb_build_object('status','voided');
end $$;

-- ---------- gate outcome: attempt limit now ignores voided attempts ----------
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
    jsonb_build_object('code',a.code,'score',at.score_pct,'passed',at.passed,'attempt_no',at.attempt_no,
                       'integrity',at.integrity_score));
  if at.passed then perform unlock_next_phase(t.id, a.id, 'score'); return; end if;

  if valid_attempts(t.id, a.id) >= a.max_attempts then
    update journeys set status = 'hr_review', updated_at = now() where trainee_id = t.id;
    perform enqueue_email(array(select email from profiles where id in (t.hr_id, t.manager_id)),
      'hr_review_required', jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code,
        'assessment', a.title, 'score', at.score_pct, 'attempts', valid_attempts(t.id, a.id)));
    return;
  end if;

  insert into escalations(trainee_id, attempt_id, assessment_id, sla_due)
  values (t.id, at.id, a.id, add_working_days(now(), array_length(a.coach_roles,1) + 2))
  returning id into v_esc;
  foreach r in array a.coach_roles loop
    v_coach := case r when 'mentor' then t.mentor_id when 'reporting_manager' then t.manager_id
                      when 'hr' then t.hr_id end;
    if v_coach is not null then
      insert into coaching_sessions(escalation_id, coach_id, coach_role, scheduled_on)
      values (v_esc, v_coach, r, (add_working_days(now(), array_position(a.coach_roles, r)))::date);
    end if;
  end loop;
  update journeys set status = 'coaching', updated_at = now() where trainee_id = t.id;
  update escalations set state = 'coaching' where id = v_esc;
  select array_agg(p.email) into v_emails from coaching_sessions cs join profiles p on p.id = cs.coach_id
  where cs.escalation_id = v_esc;
  perform enqueue_email(v_emails, 'gate_failed_coaching_required',
    jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code, 'branch', t.branch,
                       'assessment', a.title, 'score', at.score_pct, 'pass_pct', a.pass_pct,
                       'module_scores', at.module_scores, 'escalation_id', v_esc,
                       'integrity_flags', at.integrity_flags,
                       'sla_due', (select sla_due from escalations where id = v_esc)));
  perform enqueue_email(array[t.email], 'trainee_coaching_scheduled',
    jsonb_build_object('trainee', t.full_name, 'assessment', a.title));
end $$;

-- ---------- vivas + Day-30 sign-off needs the mentor's certification viva ----
create or replace function record_viva(p_trainee uuid, p_stage text, p_score int, p_notes text)
returns void language plpgsql security definer set search_path = public as $$
declare t profiles;
begin
  select * into t from profiles where id = p_trainee;
  if me() not in (t.mentor_id, t.manager_id, t.hr_id) then raise exception 'Not an assessor for this trainee'; end if;
  if coalesce(length(trim(p_notes)),0) < 30 then raise exception 'Notes must be at least 30 characters'; end if;
  insert into vivas(trainee_id, assessor_id, stage, score, notes) values (p_trainee, me(), p_stage, p_score, p_notes);
end $$;

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
                where at.trainee_id = p_trainee and a.code = 'FINAL' and at.passed
                  and at.review_state in ('clear','verified'))
    into v_final_passed;
  if not v_final_passed then raise exception 'Final assessment not yet passed (or awaiting verification)'; end if;
  if p_approved and v_role = 'mentor' and not exists (
       select 1 from vivas where trainee_id = p_trainee and stage = 'FINAL' and score >= 3) then
    raise exception 'Record the Day-30 certification viva (score 3 or more) before approving';
  end if;

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
    update journeys set status = 'certified', certified_at = now(), updated_at = now() where trainee_id = p_trainee;
    perform enqueue_email(array(select email from profiles where id in (t.id, t.mentor_id, t.manager_id, t.hr_id)),
      'certified', jsonb_build_object('trainee', t.full_name, 'employee_code', t.employee_code));
    perform log_audit('certified','journey',p_trainee::text,'{}');
    return jsonb_build_object('status','certified');
  end if;
  return jsonb_build_object('status','awaiting_other_signatories','approved',v_done);
end $$;

-- Coaches' queue of held results
create or replace view v_my_integrity_reviews with (security_invoker = on) as
select r.id as review_id, at.id as attempt_id, a.code as gate, at.score_pct, at.integrity_score,
       at.integrity_flags, r.sla_due, p.full_name as trainee, p.employee_code
from integrity_reviews r
join attempts at on at.id = r.attempt_id
join assessments a on a.id = at.assessment_id
join profiles p on p.id = at.trainee_id
where r.outcome is null and me() in (p.mentor_id, p.hr_id);
