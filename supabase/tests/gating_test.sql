\set ON_ERROR_STOP 1
-- link auth users for trainee1, trainee2, mentor1, manager1, hr1
insert into auth.users(email) select email from profiles where email in
 ('trainee1@bank.example','trainee2@bank.example','mentor1@bank.example','manager1@bank.example','hr1@bank.example');
create temp table u as select p.email, p.user_id from profiles p where user_id is not null;
select email from u order by 1;

-- helper: act as someone
create or replace function pg_temp.act(e text) returns void language sql as $$ select set_config('test.uid',(select user_id::text from profiles where email=e),false) $$;
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

select pg_temp.act('mentor1@bank.example');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Strong on product, needs some revision on AML thresholds; confident overall.');
select pg_temp.act('manager1@bank.example');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Discussed credit process in depth; understands CAM flow reasonably well.');
select pg_temp.act('hr1@bank.example');
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
select pg_temp.act('mentor1@bank.example');  select sign_off((select id from profiles where email='trainee1@bank.example'), true, 'Ready');
select pg_temp.act('manager1@bank.example'); select sign_off((select id from profiles where email='trainee1@bank.example'), true, 'Ready');
select pg_temp.act('hr1@bank.example');      select sign_off((select id from profiles where email='trainee1@bank.example'), true, 'Ready');
select status, certified_at is not null from journeys j join profiles p on p.id=j.trainee_id where p.email='trainee1@bank.example';

-- === Trainee 2: fail Gate 1 twice path → coaches pass on first; check coach-pass unlock
select pg_temp.act('trainee2@bank.example');
select pg_temp.done('trainee2@bank.example',1);
select (start_attempt('GATE_1')->>'attempt_id')::uuid as b1 \gset
select submit_attempt(:'b1', pg_temp.answer(:'b1', false)) ->> 'passed';
select pg_temp.act('mentor1@bank.example');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Nervous in test; verbal understanding is solid across all four pillars.');
select pg_temp.act('manager1@bank.example');
select record_coaching((select session_id from v_my_coaching_queue), 'pass', 'Walked through three live deals; answers were accurate and well reasoned.');
select pg_temp.act('hr1@bank.example');
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
