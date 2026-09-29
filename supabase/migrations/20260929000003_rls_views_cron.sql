-- =====================================================================
-- RM Onboarding Academy — Row Level Security, dashboard views, schedules
-- =====================================================================

alter table profiles                enable row level security;
alter table cohorts                 enable row level security;
alter table phases                  enable row level security;
alter table modules                 enable row level security;
alter table learning_items          enable row level security;
alter table progress                enable row level security;
alter table assessments             enable row level security;
alter table questions               enable row level security;
alter table attempts                enable row level security;
alter table journeys                enable row level security;
alter table escalations             enable row level security;
alter table coaching_sessions       enable row level security;
alter table remediation_assignments enable row level security;
alter table shadow_logs             enable row level security;
alter table signoffs                enable row level security;
alter table pulse_surveys           enable row level security;
alter table notification_outbox     enable row level security;   -- service role only
alter table kb_chunks               enable row level security;   -- service role only
alter table chat_messages           enable row level security;
alter table audit_log               enable row level security;

-- Curriculum is readable by any signed-in user
create policy read_curriculum on phases         for select to authenticated using (true);
create policy read_modules    on modules        for select to authenticated using (true);
create policy read_items      on learning_items for select to authenticated using (true);
create policy read_assess     on assessments    for select to authenticated using (true);
create policy read_cohorts    on cohorts        for select to authenticated using (true);

-- Questions (with answers) — only HR / admin can read or author. Trainees get
-- questions through start_attempt(), which strips the answer key.
create policy questions_admin on questions for all to authenticated
  using (my_role() in ('hr','admin')) with check (my_role() in ('hr','admin'));

-- People
create policy profiles_visible on profiles for select to authenticated
  using (can_see_trainee(id) or role <> 'trainee');
create policy profiles_admin on profiles for all to authenticated
  using (my_role() in ('hr','admin')) with check (my_role() in ('hr','admin'));

-- Trainee-scoped data: visible to self, their coaches, HR, leadership
create policy progress_read  on progress for select to authenticated using (can_see_trainee(trainee_id));
create policy progress_write on progress for insert to authenticated with check (trainee_id = me());
create policy progress_upd   on progress for update to authenticated using (trainee_id = me());

create policy attempts_read  on attempts    for select to authenticated using (can_see_trainee(trainee_id));
create policy journeys_read  on journeys    for select to authenticated using (can_see_trainee(trainee_id));
create policy esc_read       on escalations for select to authenticated using (can_see_trainee(trainee_id));
create policy rem_read       on remediation_assignments for select to authenticated using (can_see_trainee(trainee_id));
create policy signoff_read   on signoffs    for select to authenticated using (can_see_trainee(trainee_id));

create policy coaching_read on coaching_sessions for select to authenticated
  using (coach_id = me() or exists (select 1 from escalations e
         where e.id = escalation_id and can_see_trainee(e.trainee_id)));
create policy coaching_schedule on coaching_sessions for update to authenticated
  using (coach_id = me());   -- decisions go through record_coaching()

create policy shadow_read   on shadow_logs for select to authenticated using (can_see_trainee(trainee_id));
create policy shadow_insert on shadow_logs for insert to authenticated
  with check (trainee_id = me() or mentor_id = me());
create policy shadow_mentor on shadow_logs for update to authenticated using (mentor_id = me());

create policy pulse_insert on pulse_surveys for insert to authenticated with check (trainee_id = me());
create policy pulse_read   on pulse_surveys for select to authenticated
  using (trainee_id = me() or my_role() in ('hr','leadership','admin'));  -- wellbeing data: HR only

create policy chat_own on chat_messages for all to authenticated
  using (profile_id = me()) with check (profile_id = me());

create policy audit_read on audit_log for select to authenticated using (my_role() in ('hr','admin'));

-- ---------- Dashboard views (security_invoker → RLS applies) ------------
create or replace view v_trainee_status with (security_invoker = on) as
select p.id, p.employee_code, p.full_name, p.branch, p.region,
       m.full_name as mentor, rm.full_name as manager, h.full_name as hr,
       j.current_phase, j.status, j.risk_score,
       training_day(p.id) as training_day,
       (select max(score_pct) from attempts a join assessments s on s.id = a.assessment_id
        where a.trainee_id = p.id and s.code = 'GATE_1') as gate1_best,
       (select max(score_pct) from attempts a join assessments s on s.id = a.assessment_id
        where a.trainee_id = p.id and s.code = 'GATE_2') as gate2_best,
       (select max(score_pct) from attempts a join assessments s on s.id = a.assessment_id
        where a.trainee_id = p.id and s.code = 'FINAL')  as final_best
from profiles p
join journeys j on j.trainee_id = p.id
left join profiles m  on m.id  = p.mentor_id
left join profiles rm on rm.id = p.manager_id
left join profiles h  on h.id  = p.hr_id
where p.role = 'trainee';

create or replace view v_my_coaching_queue with (security_invoker = on) as
select cs.id as session_id, cs.coach_role, cs.scheduled_on, cs.decision,
       e.sla_due, e.state, a.code as gate, at.score_pct, at.module_scores,
       p.full_name as trainee, p.employee_code, p.branch
from coaching_sessions cs
join escalations e on e.id = cs.escalation_id
join attempts at   on at.id = e.attempt_id
join assessments a on a.id = e.assessment_id
join profiles p    on p.id = e.trainee_id
where cs.coach_id = me() and cs.decision is null;

create or replace view v_programme_kpis with (security_invoker = on) as
select count(*)                                              as trainees,
       count(*) filter (where status = 'certified')          as certified,
       count(*) filter (where status = 'coaching')           as in_coaching,
       count(*) filter (where status = 'remediation')        as in_remediation,
       count(*) filter (where status = 'hr_review')          as hr_review,
       count(*) filter (where status = 'exited')             as exited,
       count(*) filter (where risk_score >= 60)              as high_risk,
       round(avg(risk_score),1)                              as avg_risk
from journeys;

-- ---------- Schedules (enable pg_cron + pg_net in Supabase dashboard) ----
-- Every 2 minutes: drain the email outbox via Edge Function
-- Nightly 01:00 IST: SLA breaches, reminders, risk scores
-- (Run these in the SQL editor after replacing <project-ref> and <service-role-key>;
--  store the key in Supabase Vault in production.)
-- select cron.schedule('notify-dispatch', '*/2 * * * *', $$
--   select net.http_post(
--     url := 'https://<project-ref>.supabase.co/functions/v1/notify-dispatch',
--     headers := jsonb_build_object('Authorization','Bearer <service-role-key>'));
-- $$);
-- 
-- select cron.schedule('daily-scheduler', '30 19 * * *', $$   -- 19:30 UTC = 01:00 IST
--   select net.http_post(
--     url := 'https://<project-ref>.supabase.co/functions/v1/daily-scheduler',
--     headers := jsonb_build_object('Authorization','Bearer <service-role-key>'));
-- $$);
