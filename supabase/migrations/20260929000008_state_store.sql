-- =====================================================================
-- RM Onboarding Academy — state store
-- Every change made in the UI is saved in Supabase:
--  * Business data (joinees, logins, progress, attempts, coaching, shadow logs,
--    sign-offs) goes to its own table through the functions in migrations 002–007.
--  * Screen state (last page, open training day, filters, unsent form drafts)
--    goes to ui_state: one private JSON document per person per key.
-- This migration adds ui_state and the three UI actions that had no function yet.
-- =====================================================================

create table ui_state (
  profile_id  uuid not null references profiles(id) on delete cascade,
  key         text not null check (key ~ '^[a-z0-9_.:-]{1,64}$'),
  value       jsonb not null default '{}',
  updated_at  timestamptz not null default now(),
  primary key (profile_id, key)
);
alter table ui_state enable row level security;
create policy ui_state_own on ui_state for all to authenticated
  using (profile_id = me()) with check (profile_id = me());

-- upsert one key for the signed-in person (keeps values small: 16 KB cap)
create or replace function save_ui_state(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if me() is null then raise exception 'Sign in first'; end if;
  if pg_column_size(p_value) > 16384 then raise exception 'UI state for % is too large', p_key; end if;
  insert into ui_state(profile_id, key, value) values (me(), p_key, p_value)
  on conflict (profile_id, key) do update set value = excluded.value, updated_at = now();
end $$;

-- ---------- HR: withdraw a joinee before Day 1 (offer declined) -----------
create or replace function hr_withdraw_joinee(p_trainee uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare t profiles;
begin
  if my_role() not in ('hr','admin') then raise exception 'Only HR can withdraw joinees'; end if;
  select * into t from profiles where id = p_trainee and role = 'trainee';
  if t.id is null then raise exception 'Joinee not found'; end if;
  if exists (select 1 from progress where trainee_id = p_trainee)
     or exists (select 1 from attempts where trainee_id = p_trainee) then
    raise exception '% has already started the programme; use HR review instead', t.full_name;
  end if;
  if coalesce(length(trim(p_reason)),0) < 5 then raise exception 'Give a short reason'; end if;
  -- keep an audit record, free the seat, disable any login
  perform log_audit('joinee_withdrawn','profile',p_trainee::text,
    jsonb_build_object('employee_code', t.employee_code, 'reason', p_reason));
  update profiles set is_active = false, cohort_id = null, account_status =
         case when account_status = 'none' then 'none' else 'disabled' end
  where id = p_trainee;
  update journeys set status = 'exited', exit_reason = 'Withdrawn before Day 1: ' || p_reason, updated_at = now()
  where trainee_id = p_trainee;
end $$;

-- ---------- HR: decision after two failed attempts -------------------------
create or replace function hr_decide_review(p_trainee uuid, p_decision text, p_notes text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j journeys; t profiles; a assessments;
begin
  select * into t from profiles where id = p_trainee;
  if me() is distinct from t.hr_id and my_role() <> 'admin' then
    raise exception 'Only this joinee''s HR partner can decide';
  end if;
  select * into j from journeys where trainee_id = p_trainee for update;
  if j.status <> 'hr_review' then raise exception 'This joinee is not in HR review'; end if;
  if coalesce(length(trim(p_notes)),0) < 30 then raise exception 'Decision notes must be at least 30 characters'; end if;
  select * into a from assessments
  where code = case j.current_phase when 1 then 'GATE_1' when 2 then 'GATE_2' else 'FINAL' end;

  if p_decision = 'extend' then
    -- one more attempt: the extension is recorded and counted by valid_attempts()
    update journeys set status = 'active', updated_at = now() where trainee_id = p_trainee;
    insert into audit_log(actor_id, action, entity, entity_id, detail)
    values (me(), 'hr_extension', 'journey', p_trainee::text,
            jsonb_build_object('assessment', a.code, 'extra_attempts', 1, 'notes', p_notes));
    perform enqueue_email(array[t.email], 'phase_unlocked',
      jsonb_build_object('trainee', t.full_name, 'assessment', a.title, 'via', 'hr_extension'));
  elsif p_decision = 'exit' then
    update journeys set status = 'exited', exit_reason = p_notes, updated_at = now() where trainee_id = p_trainee;
    update profiles set account_status = case when account_status = 'none' then 'none' else 'disabled' end
    where id = p_trainee;
    perform log_audit('hr_exit','journey',p_trainee::text, jsonb_build_object('notes', p_notes));
  else
    raise exception 'Decision must be extend or exit';
  end if;
  return jsonb_build_object('status', p_decision);
end $$;

-- extensions granted by HR count as extra attempts
create or replace function valid_attempts(p_trainee uuid, p_assessment int) returns int
language sql stable security definer set search_path = public as $$
  select greatest(0,
    (select count(*)::int from attempts
     where trainee_id = p_trainee and assessment_id = p_assessment
       and submitted_at is not null and review_state <> 'voided')
  - (select count(*)::int from audit_log
     where entity = 'journey' and entity_id = p_trainee::text and action = 'hr_extension'
       and detail->>'assessment' = (select code from assessments where id = p_assessment)))
$$;

-- ---------- Mentor: rate a shadow log against the rubric --------------------
create or replace function rate_shadow_log(p_log uuid, p_competencies jsonb, p_feedback text) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_avg numeric; l shadow_logs;
begin
  select * into l from shadow_logs where id = p_log for update;
  if l.id is null or l.mentor_id <> me() then raise exception 'Not a shadow log you mentor'; end if;
  if (select count(*) from jsonb_each_text(p_competencies) where value ~ '^[1-5]$') <> 6 then
    raise exception 'Rate all six competencies from 1 to 5';
  end if;
  select round(avg(value::int), 1) into v_avg from jsonb_each_text(p_competencies);
  update shadow_logs set competencies = p_competencies, mentor_rating = round(v_avg)::smallint,
         mentor_notes = p_feedback where id = p_log;
  return v_avg;
end $$;

grant select on ui_state to authenticated;
