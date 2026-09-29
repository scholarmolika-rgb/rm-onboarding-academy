\set ON_ERROR_STOP 1
-- link auth users for trainee1, trainee2, mentor1, manager1, hr1
insert into auth.users(email) select email from profiles where account_status = 'active';
create temp table u as select p.email, p.user_id from profiles p where user_id is not null;
select email from u order by 1;

-- Part A: gate/coaching/sign-off rules (whole-paper delivery)
update assessments set secure_delivery = false;
-- helper: act as someone
create or replace function pg_temp.act(e text) returns void language sql as $$ select set_config('test.uid',(select user_id::text from profiles where email=e),false) $$;
create or replace function pg_temp.coach(trainee_email text, r text) returns void language sql as $$
  select set_config('test.uid',(select c.user_id::text from profiles t join profiles c on c.id =
    case r when 'mentor' then t.mentor_id when 'reporting_manager' then t.manager_id else t.hr_id end
    where t.email = trainee_email), false) $$;
create or replace function pg_temp.done(e text, ph int) returns void language sql as $$
 insert into progress(trainee_id,item_id,status,completed_at)
 select (select id from profiles where email=e), li.id,'completed',now() from learning_items li join modules m on m.id=li.module_id where m.phase_id=ph
 on conflict (trainee_id,item_id) do update set status='completed' $$;
create or replace function pg_temp.answer(att uuid, correct bool) returns jsonb language sql as $$
 select jsonb_object_agg(q.id::text, case when correct then q.answer_idx else (q.answer_idx+1)%4 end)
 from questions q where q.id = any(array(select unnest(question_ids) from attempts where id=att)) $$;

-- === Trainee 1: fail Gate 1 → 3 coaches; HR says repeat → remediation → retake pass
select pg_temp.act('trainee1@bank.example');
do $$ begin perform start_attempt('GATE_1'); exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end $$;
select pg_temp.done('trainee1@bank.example',1);
select (start_attempt('GATE_1')->>'attempt_id')::uuid as a1 \gset
select submit_attempt(:'a1', pg_temp.answer(:'a1', false)) ->> 'score_pct' as score;
select status from journeys where trainee_id = me();
select coach_role, scheduled_on is not null sched from coaching_sessions order by coach_role;
select template, to_emails from notification_outbox order by created_at;

select pg_temp.coach('trainee1@bank.example','mentor');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Strong on product, needs some revision on AML thresholds; confident overall.');
select pg_temp.coach('trainee1@bank.example','reporting_manager');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Discussed credit process in depth; understands CAM flow reasonably well.');
select pg_temp.coach('trainee1@bank.example','hr');
select record_coaching((select session_id from v_my_coaching_queue), 'repeat', 'Governance gaps are material for a customer-facing role; repeat GOV module.', array[(select id from modules where code='GOV')]);
select j.status, (select count(*) from remediation_assignments) rem from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee1@bank.example';

select pg_temp.act('trainee1@bank.example');
select complete_remediation(id) from remediation_assignments;
select (start_attempt('GATE_1')->>'attempt_id')::uuid as a2 \gset
select submit_attempt(:'a2', pg_temp.answer(:'a2', true)) ->> 'passed' as passed;
select current_phase, status from journeys where trainee_id = me();

-- Gate 2 pass, then Final pass, then tri-party sign-off
select pg_temp.done('trainee1@bank.example',2);
select (start_attempt('GATE_2')->>'attempt_id')::uuid as g2 \gset
select submit_attempt(:'g2', pg_temp.answer(:'g2', true)) ->> 'passed' as gate2;
select pg_temp.done('trainee1@bank.example',3);
select (start_attempt('FINAL')->>'attempt_id')::uuid as f1 \gset
select submit_attempt(:'f1', pg_temp.answer(:'f1', true)) ->> 'passed' as final;
select pg_temp.coach('trainee1@bank.example','mentor');
do $$ begin perform sign_off((select id from profiles where email='trainee1@bank.example'), true, 'Ready'); exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end $$;
select record_viva((select id from profiles where email='trainee1@bank.example'),'FINAL',4,'Explained pricing, KYC escalation and DP calculation clearly under questioning.');
select sign_off((select id from profiles where email='trainee1@bank.example'), true, 'Ready');
select pg_temp.coach('trainee1@bank.example','reporting_manager'); select sign_off((select id from profiles where email='trainee1@bank.example'), true, 'Ready');
select pg_temp.coach('trainee1@bank.example','hr');      select sign_off((select id from profiles where email='trainee1@bank.example'), true, 'Ready');
select status, certified_at is not null from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee1@bank.example';

-- === Trainee 2: fail Gate 1 twice path → coaches pass on first; check coach-pass unlock
select pg_temp.act('trainee2@bank.example');
select pg_temp.done('trainee2@bank.example',1);
select (start_attempt('GATE_1')->>'attempt_id')::uuid as b1 \gset
select submit_attempt(:'b1', pg_temp.answer(:'b1', false)) ->> 'passed';
select pg_temp.coach('trainee2@bank.example','mentor');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Nervous in test; verbal understanding is solid across all four pillars.');
select pg_temp.coach('trainee2@bank.example','reporting_manager');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Walked through three live deals; answers were accurate and well reasoned.');
select pg_temp.coach('trainee2@bank.example','hr');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Good conduct awareness; no further remediation needed from HR perspective.');
select current_phase, status from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee2@bank.example';

-- Gate 2 fail → only mentor + manager coach
select pg_temp.act('trainee2@bank.example');
select pg_temp.done('trainee2@bank.example',2);
select (start_attempt('GATE_2')->>'attempt_id')::uuid as b2 \gset
select submit_attempt(:'b2', pg_temp.answer(:'b2', false)) ->> 'passed';
select cs.coach_role from coaching_sessions cs join escalations e on e.id=cs.escalation_id join assessments a on a.id=e.assessment_id where a.code='GATE_2';
select template, count(*) from notification_outbox group by 1 order by 1;
select * from v_programme_kpis;
select count(*) audit_rows from audit_log;
-- assertions
do $$ begin
  assert (select status from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee1@bank.example')='certified', 'trainee1 should be certified';
  assert (select current_phase from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee2@bank.example')=2, 'trainee2 should be in phase 2';
  assert (select count(*) from notification_outbox where template='gate_failed_coaching_required')=3, 'three coaching emails expected';
  raise notice 'ALL GATING TESTS PASSED';
end $$;

-- =====================================================================
-- Part B: assessment integrity (secure one-question-at-a-time delivery)
-- =====================================================================
update assessments set secure_delivery = true;
create or replace function pg_temp.sit(e text, correct bool) returns jsonb language plpgsql as $$
declare st jsonb; qq jsonb; aa attempt_answers; q questions; disp int; tok uuid; att uuid;
begin
  perform pg_temp.act(e);
  st := start_attempt('GATE_1'); att := (st->>'attempt_id')::uuid; tok := (st->>'session_token')::uuid;
  perform accept_declaration(att, tok);
  loop
    qq := serve_question(att, tok);
    exit when qq ? 'done';
    select * into aa from attempt_answers where attempt_id = att and seq = (qq->>'seq')::int;
    select * into q from questions where id = aa.question_id;
    disp := array_position(aa.option_order, q.answer_idx::smallint) - 1;       -- where the right option was displayed
    if not correct then disp := (disp + 1) % array_length(aa.option_order,1); end if;
    perform answer_question(att, tok, (qq->>'seq')::int, disp);
  end loop;
  return submit_attempt(att, null) || jsonb_build_object('attempt_id', att);
end $$;

-- B1: serve before declaration is refused; token from another session is refused; no going back
select pg_temp.act('trainee3@bank.example');
select pg_temp.done('trainee3@bank.example',1);
select start_attempt('GATE_1') as st \gset
do $$ declare st jsonb := (select jsonb_build_object('attempt_id',id,'session_token',session_token) from attempts where trainee_id=me() and submitted_at is null);
begin
  begin perform serve_question((st->>'attempt_id')::uuid, (st->>'session_token')::uuid); raise exception 'should block';
  exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  perform accept_declaration((st->>'attempt_id')::uuid, (st->>'session_token')::uuid);
  begin perform serve_question((st->>'attempt_id')::uuid, gen_random_uuid()); raise exception 'should block';
  exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  perform serve_question((st->>'attempt_id')::uuid, (st->>'session_token')::uuid);
  perform answer_question((st->>'attempt_id')::uuid, (st->>'session_token')::uuid, 1, 0);
  perform serve_question((st->>'attempt_id')::uuid, (st->>'session_token')::uuid);
  begin perform answer_question((st->>'attempt_id')::uuid, (st->>'session_token')::uuid, 1, 1); raise exception 'should block';
  exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  -- timeout: question 2 was served 2 minutes ago
  update attempt_answers set served_at = now() - interval '2 minutes' where attempt_id = (st->>'attempt_id')::uuid and seq = 2;
  raise notice 'late answer recorded? %', answer_question((st->>'attempt_id')::uuid, (st->>'session_token')::uuid, 2, 0)->>'recorded';
  -- behaviour events during the test
  perform log_attempt_event((st->>'attempt_id')::uuid, 'focus_lost', 2);
  perform log_attempt_event((st->>'attempt_id')::uuid, 'focus_lost', 2);
  perform log_attempt_event((st->>'attempt_id')::uuid, 'focus_lost', 3);
  perform log_attempt_event((st->>'attempt_id')::uuid, 'paste', 3);
  begin perform start_attempt('GATE_1'); raise exception 'should block';
  exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
end $$;
-- finish trainee3's paper correctly and fast
do $$ declare att uuid; tok uuid; qq jsonb; aa attempt_answers; q questions; begin
  select id, session_token into att, tok from attempts where trainee_id = me() and submitted_at is null;
  loop qq := serve_question(att, tok); exit when qq ? 'done';
    select * into aa from attempt_answers where attempt_id = att and seq = (qq->>'seq')::int;
    select * into q from questions where id = aa.question_id;
    perform answer_question(att, tok, (qq->>'seq')::int, array_position(aa.option_order, q.answer_idx::smallint) - 1);
  end loop;
  raise notice 'trainee3 result: %', submit_attempt(att, null);
end $$;
select score_pct, passed, integrity_score, integrity_flags, review_state from attempts where trainee_id = me() and submitted_at is not null;
select status from journeys where trainee_id = me();

-- B2: mentor holds a viva and voids the result → supervised re-sit only
select pg_temp.coach('trainee3@bank.example','mentor');
select trainee, gate, integrity_score from v_my_integrity_reviews;
select verify_attempt((select attempt_id from v_my_integrity_reviews limit 1), 'voided', 2,
  'Could not explain the drawing power or KYC answers given in the paper; re-sit supervised.');
select pg_temp.act('trainee3@bank.example');
do $$ begin perform start_attempt('GATE_1'); raise exception 'should block';
exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end $$;
insert into assessment_windows(cohort_id, assessment_id, opens_at, closes_at, mode, venue)
select cohort_id, (select id from assessments where code='GATE_1'), now()-interval '1 hour', now()+interval '2 hours',
       'proctored_centre', 'Mumbai BKC test room' from profiles where email='trainee3@bank.example';
select (pg_temp.sit('trainee3@bank.example', true)) ->> 'passed' as supervised_resit_passed;
select attempt_no, review_state, passed from attempts where trainee_id = me() order by attempt_no;

-- B3: a clean candidate passes straight through
delete from assessment_windows;
select pg_temp.done('trainee4@bank.example',1);
select pg_temp.sit('trainee4@bank.example', true) ->> 'status' as clean_status;
select current_phase, status from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee4@bank.example';

do $$ begin
  assert (select review_state from attempts a join profiles p on p.id=a.trainee_id where p.email='trainee3@bank.example' and attempt_no=1)='voided', 'attempt 1 voided';
  assert (select supervised_only from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee3@bank.example'), 'supervised flag';
  assert (select current_phase from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee4@bank.example')=2, 'clean pass unlocks';
  assert (select count(*) from notification_outbox where template='integrity_review_required')=1, 'one integrity email';
  raise notice 'ALL INTEGRITY TESTS PASSED';
end $$;

-- =====================================================================
-- Part C: people model — personas, assignment rules, seats
-- =====================================================================
select set_config('test.uid', (select user_id::text from profiles where email='hr1@bank.example'), false);
do $$ declare r jsonb; n int; begin
  -- personas
  assert (select count(*) from profiles where role='reporting_manager') = 20, '20 reporting bosses';
  assert not exists (select 1 from profiles where role='reporting_manager' and experience_months not between 120 and 179), 'boss experience 10-<15y';
  assert not exists (select 1 from profiles where role='trainee' and experience_months not between 37 and 59), 'joinee experience >3-<5y';
  assert not exists (select 1 from profiles t join profiles m on m.id=t.mentor_id where t.role='trainee' and m.department=t.department), 'mentor from another department';
  assert not exists (select 1 from profiles t join profiles b on b.id=t.manager_id where t.role='trainee' and b.department<>t.department), 'boss from same department';
  assert (select free from v_seat_usage) = 1000 - (select count(*) from profiles where role='trainee'), 'seats';

  -- experience outside the persona is refused
  begin perform hr_create_joinee('{"full_name":"Too Junior","email":"junior@bank.example","department":"MCB","region":"North","experience_months":30}');
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  begin perform hr_create_joinee('{"full_name":"Too Senior","email":"senior@bank.example","department":"MCB","region":"North","experience_months":60}');
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  -- mentor from the same department is refused
  begin perform hr_create_joinee(jsonb_build_object('full_name','Same Dept','email','same@bank.example','department','MCB','region','North',
          'experience_months',48,'mentor_id',(select id from profiles where role='mentor' and department='MCB' limit 1)));
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  -- boss from another department is refused
  begin perform hr_create_joinee(jsonb_build_object('full_name','Wrong Boss','email','wrongboss@bank.example','department','MCB','region','North',
          'experience_months',48,'manager_id',(select id from profiles where role='reporting_manager' and department='LCB' limit 1)));
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;

  -- happy path: auto-assignment
  r := hr_create_joinee('{"full_name":"Test Joinee","email":"test.joinee@bank.example","department":"TSF","region":"West","experience_months":50,"previous_employer":"Yes Bank","previous_role":"Trade Finance Officer"}');
  raise notice 'created: %', r;
  assert r->>'mentor_department' <> 'TSF' and r->>'boss_department' = 'TSF', 'auto-assignment rules';
  assert (select count(*) from notification_outbox where template in ('welcome_joinee','new_joinee_assigned')
          and payload->>'trainee'='Test Joinee') = 2, 'welcome + assignment emails';

  -- bulk: one bad row does not stop the others
  r := hr_create_joinees('[{"full_name":"Bulk One","email":"bulk1@bank.example","department":"LCB","region":"South","experience_months":40},
                           {"full_name":"Bulk Bad","email":"bulk2@bank.example","department":"LCB","region":"South","experience_months":24},
                           {"full_name":"Bulk Three","email":"bulk3@bank.example","department":"ECB","region":"East","experience_months":55}]');
  raise notice 'bulk: %', r;
  assert (select count(*) from jsonb_array_elements(r) e where (e->>'ok')::boolean) = 2, 'bulk 2 ok';

  -- capacity
  update cohorts set capacity = (select count(*) from profiles where role='trainee');
  begin perform hr_create_joinee('{"full_name":"Over Capacity","email":"over@bank.example","department":"ECB","region":"East","experience_months":45}');
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  update cohorts set capacity = 1000;
end $$;
select pg_temp.act('trainee5@bank.example');
do $$ begin perform hr_create_joinee('{"full_name":"X","email":"x@bank.example","department":"ECB","region":"East","experience_months":45}');
  raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end $$;
select role, department, count(*) filter (where role<>'hr') n, min(trainees), max(trainees) from v_coach_load group by 1,2 order by 1,2;
do $$ begin raise notice 'ALL PEOPLE-MODEL TESTS PASSED'; end $$;

-- =====================================================================
-- Part D: HR-provisioned logins and staff
-- =====================================================================
do $$ declare hr uuid := (select id from profiles where email='hr1@bank.example');
              j uuid := (select id from profiles where email='test.joinee@bank.example');
              b uuid := (select id from profiles where role='reporting_manager' limit 1); r jsonb; begin
  -- self sign-up for someone HR never added is refused
  begin insert into auth.users(email) values ('stranger@gmail.com'); raise exception 'should block';
  exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  -- HR added this joinee but has not issued a login yet: still refused
  begin insert into auth.users(email) values ('test.joinee@bank.example'); raise exception 'should block';
  exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  -- a non-HR actor cannot create logins
  begin perform apply_login_change(j, 'create', b); raise exception 'should block';
  exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  -- HR issues the login, then the Edge Function creates the auth user (trigger links it)
  perform apply_login_change(j, 'create', hr);
  insert into auth.users(email) values ('test.joinee@bank.example');
  assert (select user_id is not null from profiles where id=j), 'auth user linked';
  assert (select login_id from profiles where id=j) like 'TRN%', 'login id = employee code';
  assert (select must_change_password from profiles where id=j), 'must change at first sign-in';
  assert resolve_login(lower((select login_id from profiles where id=j))) = 'test.joinee@bank.example', 'resolve by login id, any case';
  perform apply_login_change(j, 'disable', hr);
  assert resolve_login((select login_id from profiles where id=j)) is null, 'disabled cannot sign in';
  assert resolve_login('NOBODY999') is null, 'unknown id';
  perform apply_login_change(j, 'enable', hr);
  -- revert after a failed auth-user creation
  perform apply_login_change((select id from profiles where email='bulk1@bank.example'), 'create', hr);
  perform apply_login_change((select id from profiles where email='bulk1@bank.example'), 'revert', hr);
  assert (select account_status from profiles where email='bulk1@bank.example') = 'none', 'revert';
  assert exists (select 1 from audit_log where action = 'login_create'), 'audited';
end $$;

-- the person replaces the temporary password
select pg_temp.act('test.joinee@bank.example');
select password_changed();
do $$ begin assert not (select must_change_password from profiles where email='test.joinee@bank.example'), 'password changed';
  -- joinees cannot add staff
  begin perform hr_add_staff('{"role":"mentor","full_name":"X","email":"x2@bank.example","department":"LCB","region":"East","experience_months":160}');
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
end $$;

-- HR adds Reporting Bosses and Mentors with persona checks
select set_config('test.uid', (select user_id::text from profiles where email='hr1@bank.example'), false);
do $$ declare r jsonb; begin
  begin perform hr_add_staff('{"role":"reporting_manager","full_name":"Boss 21","email":"boss21@bank.example","department":"MCB","region":"North","experience_months":150}');
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  begin perform hr_set_staff_active((select id from profiles where email='boss1@bank.example'), false);
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  update profiles set is_active = false where email = 'boss20@bank.example';
  begin perform hr_add_staff('{"role":"reporting_manager","full_name":"Too Junior Boss","email":"jb@bank.example","department":"MCB","region":"North","experience_months":100}');
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  r := hr_add_staff('{"role":"reporting_manager","full_name":"New Boss","email":"newboss@bank.example","department":"TSF","region":"Central","experience_months":130,"designation":"Cluster Head"}');
  assert r->>'employee_code' = 'RB021', 'boss code';
  begin perform hr_add_staff('{"role":"mentor","full_name":"Junior Mentor","email":"jm@bank.example","department":"LCB","region":"East","experience_months":100}');
        raise exception 'should block'; exception when others then raise notice 'EXPECTED BLOCK: %', sqlerrm; end;
  r := hr_add_staff('{"role":"mentor","full_name":"New Mentor","email":"newmentor@bank.example","department":"LCB","region":"East","experience_months":160}');
  assert r->>'employee_code' = 'MN021', 'mentor code';
  perform apply_login_change((r->>'id')::uuid, 'create', me());
  insert into auth.users(email) values ('newmentor@bank.example');
  assert resolve_login('MN021') = 'newmentor@bank.example', 'new mentor can sign in';
  raise notice 'ALL LOGIN TESTS PASSED';
end $$;
