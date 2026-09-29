-- =====================================================================
-- RM Onboarding Academy — people model
--  * Departments: the RM business line a joinee joins after Day 30.
--  * New Joinee persona: more than 3 and less than 5 years' experience (37–59 months).
--  * Reporting Boss persona: 20 in total, 10 to under 15 years' experience (120–179 months),
--    in the SAME department as the joinee (the post-Day-30 reporting line).
--  * Mentor: always from a DIFFERENT department than the joinee, so the mentor brings
--    cross-functional perspective and never assesses a future member of their own team.
--  * Cohort seats: 1,000 per cohort; HR adds joinees one by one or in bulk.
-- =====================================================================

create table departments (
  code        text primary key,
  name        text not null,
  description text
);
insert into departments(code, name, description) values
 ('LCB','Large Corporate Banking','Groups and corporates above ₹1,500 Cr turnover'),
 ('MCB','Mid-Corporate Banking','Corporates ₹250–1,500 Cr turnover'),
 ('ECB','Emerging Corporates (SME)','Growing businesses ₹50–250 Cr turnover'),
 ('TXB','Transaction Banking','Cash management, payroll, escrow and collections relationships'),
 ('TSF','Trade & Supply Chain Finance','Import/export, guarantees, dealer and vendor finance programmes');

alter table departments enable row level security;
create policy departments_read on departments for select to authenticated using (true);

alter table profiles
  add column department        text references departments(code),
  add column designation       text,
  add column experience_months int,
  add column previous_employer text,
  add column previous_role     text,
  add column start_date        date,
  add column max_trainees      int not null default 50;   -- load cap for mentors / bosses / HR

-- persona rules, enforced for every row
alter table profiles add constraint persona_experience check (
     (role = 'trainee'           and experience_months between 37 and 59)
  or (role = 'reporting_manager' and experience_months between 120 and 179)
  or  role not in ('trainee','reporting_manager'));

alter table cohorts add column capacity int not null default 1000;

-- ---------- assignment rules (trigger: nothing can bypass them) ---------
create or replace function trg_assignment_rules() returns trigger
language plpgsql security definer set search_path = public as $$
declare b profiles; m profiles; h profiles; v_used int; v_cap int;
begin
  if new.role <> 'trainee' then return new; end if;
  if new.department is null then raise exception 'A new joinee needs the department they will join after Day 30'; end if;

  if new.manager_id is not null then
    select * into b from profiles where id = new.manager_id;
    if b.role <> 'reporting_manager' then raise exception 'Reporting Boss must have the reporting_manager role'; end if;
    if b.department is distinct from new.department then
      raise exception 'Reporting Boss must be from the joinee''s department (%), not %', new.department, b.department;
    end if;
  end if;
  if new.mentor_id is not null then
    select * into m from profiles where id = new.mentor_id;
    if m.role <> 'mentor' then raise exception 'Mentor must have the mentor role'; end if;
    if m.department = new.department then
      raise exception 'Mentor must come from a different department than the joinee (%)', new.department;
    end if;
  end if;
  if new.hr_id is not null then
    select * into h from profiles where id = new.hr_id;
    if h.role <> 'hr' then raise exception 'HR partner must have the hr role'; end if;
  end if;

  if tg_op = 'INSERT' and new.cohort_id is not null then
    select capacity into v_cap from cohorts where id = new.cohort_id;
    select count(*) into v_used from profiles where cohort_id = new.cohort_id and role = 'trainee';
    if v_used >= v_cap then raise exception 'Cohort is full (% of % seats used)', v_used, v_cap; end if;
  end if;
  return new;
end $$;
create trigger profile_assignment_rules before insert or update on profiles
for each row execute function trg_assignment_rules();

-- ---------- load of every coach ------------------------------------------
create or replace view v_coach_load with (security_invoker = on) as
select c.id, c.full_name, c.role, c.department, d.name as department_name, c.region,
       c.experience_months, c.max_trainees,
       (select count(*) from profiles t where t.role = 'trainee' and t.is_active and
          c.id = case c.role when 'mentor' then t.mentor_id when 'reporting_manager' then t.manager_id
                              when 'hr' then t.hr_id end)::int as trainees
from profiles c left join departments d on d.code = c.department
where c.role in ('mentor','reporting_manager','hr') and c.is_active;

create or replace view v_seat_usage with (security_invoker = on) as
select co.id as cohort_id, co.name, co.start_date, co.capacity,
       count(p.id)::int as used, (co.capacity - count(p.id))::int as free
from cohorts co left join profiles p on p.cohort_id = co.id and p.role = 'trainee'
group by co.id;

-- ---------- pick the least-loaded eligible coach ---------------------------
create or replace function pick_coach(p_role app_role, p_department text, p_region text, p_same_dept boolean)
returns uuid language sql stable security definer set search_path = public as $$
  select l.id from v_coach_load l
  where l.role = p_role and l.trainees < l.max_trainees
    and (p_department is null
         or (p_same_dept and l.department = p_department)
         or (not p_same_dept and l.department is distinct from p_department))
  order by (l.region is not distinct from p_region) desc,   -- same region first (in-person shadowing)
           l.trainees asc, l.full_name
  limit 1
$$;

-- ---------- create one joinee with automatic assignment ---------------------
-- p: {full_name, email, phone, department, region, experience_months, previous_employer,
--     previous_role, start_date, cohort_id?, manager_id?, mentor_id?}
create or replace function create_joinee_internal(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cohort uuid; v_dept text := upper(p->>'department'); v_region text := initcap(p->>'region');
  v_exp int := (p->>'experience_months')::int; v_boss uuid; v_mentor uuid; v_hr uuid;
  v_code text; v_id uuid; b profiles; m profiles; h profiles;
begin
  if coalesce(trim(p->>'full_name'),'') = '' then raise exception 'Name is required'; end if;
  if coalesce(p->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'A valid work email is required'; end if;
  if exists (select 1 from profiles where lower(email) = lower(p->>'email')) then
    raise exception 'Email % is already registered', p->>'email'; end if;
  if not exists (select 1 from departments where code = v_dept) then raise exception 'Unknown department %', p->>'department'; end if;
  if v_exp is null or v_exp not between 37 and 59 then
    raise exception 'New joinees must have more than 3 and less than 5 years of experience (got % months)', coalesce(v_exp::text,'none');
  end if;

  v_cohort := coalesce((p->>'cohort_id')::uuid,
                       (select id from cohorts where start_date >= current_date - 30 order by start_date limit 1),
                       (select id from cohorts order by start_date desc limit 1));

  v_boss   := coalesce((p->>'manager_id')::uuid, pick_coach('reporting_manager', v_dept, v_region, true));
  v_mentor := coalesce((p->>'mentor_id')::uuid,  pick_coach('mentor', v_dept, v_region, false));
  v_hr     := coalesce((select id from v_coach_load where role = 'hr' and region = v_region and trainees < max_trainees limit 1),
                       pick_coach('hr', null, v_region, false));
  if v_boss is null   then raise exception 'No Reporting Boss in % has a free place (all at their limit)', v_dept; end if;
  if v_mentor is null then raise exception 'No mentor outside % has a free place', v_dept; end if;
  if v_hr is null     then raise exception 'No HR partner has a free place'; end if;

  select 'TRN' || lpad((coalesce(max(substring(employee_code from 4)::int), 0) + 1)::text, 4, '0') into v_code
  from profiles where employee_code ~ '^TRN\d+$';

  insert into profiles(employee_code, full_name, email, phone, role, region, department, designation,
                       experience_months, previous_employer, previous_role, start_date, joined_on,
                       cohort_id, mentor_id, manager_id, hr_id)
  values (v_code, trim(p->>'full_name'), lower(p->>'email'), p->>'phone', 'trainee', v_region, v_dept,
          'Relationship Manager (trainee)', v_exp, p->>'previous_employer', p->>'previous_role',
          coalesce((p->>'start_date')::date, (select start_date from cohorts where id = v_cohort)),
          coalesce((p->>'start_date')::date, (select start_date from cohorts where id = v_cohort)),
          v_cohort, v_mentor, v_boss, v_hr)
  returning id into v_id;

  select * into b from profiles where id = v_boss;
  select * into m from profiles where id = v_mentor;
  select * into h from profiles where id = v_hr;
  perform enqueue_email(array[lower(p->>'email')], 'welcome_joinee',
    jsonb_build_object('trainee', p->>'full_name', 'mentor', m.full_name, 'boss', b.full_name, 'hr', h.full_name,
                       'department', v_dept, 'start_date', p->>'start_date'));
  perform enqueue_email(array[m.email, b.email], 'new_joinee_assigned',
    jsonb_build_object('trainee', p->>'full_name', 'employee_code', v_code, 'department', v_dept,
                       'mentor', m.full_name, 'boss', b.full_name), array[h.email]);
  perform log_audit('joinee_created','profile',v_id::text,
    jsonb_build_object('department',v_dept,'mentor_dept',m.department,'boss',b.full_name));

  return jsonb_build_object('id', v_id, 'employee_code', v_code,
    'boss', b.full_name, 'boss_department', b.department,
    'mentor', m.full_name, 'mentor_department', m.department, 'hr', h.full_name);
end $$;

-- HR-facing: one joinee
create or replace function hr_create_joinee(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if my_role() not in ('hr','admin') then raise exception 'Only HR can add new joinees'; end if;
  return create_joinee_internal(p);
end $$;

-- HR-facing: bulk (CSV import). Each row succeeds or fails on its own.
create or replace function hr_create_joinees(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; out jsonb := '[]'; n int := 0;
begin
  if my_role() not in ('hr','admin') then raise exception 'Only HR can add new joinees'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    n := n + 1;
    begin
      out := out || jsonb_build_array(jsonb_build_object('row', n, 'ok', true) || create_joinee_internal(r));
    exception when others then
      out := out || jsonb_build_array(jsonb_build_object('row', n, 'ok', false, 'error', sqlerrm, 'email', r->>'email'));
    end;
  end loop;
  return out;
end $$;

grant select on v_coach_load, v_seat_usage to authenticated;
