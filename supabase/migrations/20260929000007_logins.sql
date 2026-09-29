-- =====================================================================
-- RM Onboarding Academy — HR-provisioned logins
--  * Nobody can sign themselves up: an auth account is accepted only for a
--    person HR has already added (joinee, Reporting Boss, Mentor, HR).
--  * HR creates the login (login ID + temporary password) through the
--    hr-provision-user Edge Function, which uses the service role.
--  * First sign-in forces a password change; HR can reset, disable, enable.
--  In Supabase also set Authentication → "Allow new users to sign up" = OFF.
-- =====================================================================

alter table profiles
  add column login_id              text unique,
  add column account_status        text not null default 'none'
    check (account_status in ('none','active','disabled')),
  add column must_change_password  boolean not null default false,
  add column login_created_by      uuid references profiles(id),
  add column login_created_at      timestamptz,
  add column last_sign_in_at       timestamptz;

-- Login ID convention: the employee code (TRN0025, RB005, MN012, HR001)

-- ---------- block self sign-up; link HR-provisioned accounts ----------
create or replace function trg_link_auth_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  -- only people HR has added AND issued a login for (account_status set by HR first)
  select id into v_id from profiles
  where lower(email) = lower(new.email) and user_id is null and is_active and account_status = 'active';
  if v_id is null then
    raise exception 'Accounts are created by HR only. % has no login issued by HR.', new.email;
  end if;
  update profiles set user_id = new.id where id = v_id;
  return new;
end $$;

-- Sign-in page: turn a login ID (or email) into the email Supabase Auth needs.
-- Returns null for unknown or disabled accounts (same answer, so IDs cannot be probed).
create or replace function resolve_login(p_login text) returns text
language sql stable security definer set search_path = public as $$
  select email from profiles
  where (upper(login_id) = upper(trim(p_login)) or lower(email) = lower(trim(p_login)))
    and account_status = 'active' and user_id is not null
  limit 1
$$;
grant execute on function resolve_login(text) to anon, authenticated;

-- Called by the app right after the user sets their own password
create or replace function password_changed() returns void
language sql security definer set search_path = public as $$
  update profiles set must_change_password = false, last_sign_in_at = now() where id = me()
$$;

create or replace function record_sign_in() returns jsonb
language sql security definer set search_path = public as $$
  update profiles set last_sign_in_at = now() where id = me()
  returning jsonb_build_object('role', role, 'login_id', login_id, 'must_change_password', must_change_password,
                               'account_status', account_status)
$$;

-- HR's view of who can sign in
create or replace view v_logins with (security_invoker = on) as
select p.id, p.full_name, p.role, p.department, p.region, p.email, p.login_id, p.account_status,
       p.must_change_password, p.login_created_at, p.last_sign_in_at
from profiles p
where p.role in ('trainee','mentor','reporting_manager','hr');

-- Called only by the hr-provision-user Edge Function (service role) after it
-- created / reset / disabled the auth user. Records who did it.
create or replace function apply_login_change(p_profile uuid, p_action text, p_actor uuid, p_user_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if (select role from profiles where id = p_actor) not in ('hr','admin') then
    raise exception 'Only HR can create or change logins';
  end if;
  if p_action = 'create' then          -- called BEFORE the auth user is created; the trigger links user_id
    if (select role from profiles where id = p_profile) not in ('trainee','mentor','reporting_manager','hr') then
      raise exception 'This role cannot sign in';
    end if;
    update profiles set login_id = employee_code, account_status = 'active', must_change_password = true,
           user_id = coalesce(p_user_id, user_id), login_created_by = p_actor, login_created_at = now()
    where id = p_profile;
    -- the email carries only the login ID; HR hands over the temporary password separately
    perform enqueue_email(array[(select email from profiles where id = p_profile)], 'login_issued',
      (select jsonb_build_object('name', full_name, 'login_id', employee_code) from profiles where id = p_profile));
  elsif p_action = 'revert' then        -- auth user creation failed: undo the issue
    update profiles set account_status = 'none', login_id = null where id = p_profile and user_id is null;
  elsif p_action = 'reset' then
    update profiles set must_change_password = true, account_status = 'active' where id = p_profile;
  elsif p_action = 'disable' then
    update profiles set account_status = 'disabled' where id = p_profile;
  elsif p_action = 'enable' then
    update profiles set account_status = 'active' where id = p_profile;
  else raise exception 'Unknown action %', p_action;
  end if;
  insert into audit_log(actor_id, action, entity, entity_id, detail)
  values (p_actor, 'login_' || p_action, 'profile', p_profile::text, '{}');
end $$;
revoke execute on function apply_login_change(uuid, text, uuid, uuid) from public, anon, authenticated;

-- mentor persona (joinees and bosses are checked by persona_experience in migration 006)
alter table profiles add constraint mentor_experience check (
  role <> 'mentor' or experience_months is null or experience_months >= 144);

-- ---------- HR: add a Reporting Boss or Mentor (they then get a login) -------
-- p: {role: 'reporting_manager'|'mentor', full_name, email, phone, department, region,
--     experience_months, designation, max_trainees?}
create or replace function hr_add_staff(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_role app_role := (p->>'role')::app_role; v_exp int := (p->>'experience_months')::int;
        v_dept text := upper(p->>'department'); v_prefix text; v_code text; v_id uuid;
begin
  if my_role() not in ('hr','admin') then raise exception 'Only HR can add Reporting Bosses and Mentors'; end if;
  if v_role not in ('reporting_manager','mentor') then raise exception 'Role must be Reporting Boss or Mentor'; end if;
  if coalesce(trim(p->>'full_name'),'') = '' then raise exception 'Name is required'; end if;
  if coalesce(p->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'A valid work email is required'; end if;
  if exists (select 1 from profiles where lower(email) = lower(p->>'email')) then
    raise exception 'Email % is already registered', p->>'email'; end if;
  if not exists (select 1 from departments where code = v_dept) then raise exception 'Unknown department %', p->>'department'; end if;
  if v_role = 'reporting_manager' then
    if v_exp is null or v_exp not between 120 and 179 then
      raise exception 'Reporting Bosses must have 10 to under 15 years of experience (got % months)', coalesce(v_exp::text,'none');
    end if;
    if (select count(*) from profiles where role = 'reporting_manager' and is_active) >= 20 then
      raise exception 'The programme already has 20 Reporting Bosses. Deactivate one before adding another.';
    end if;
    v_prefix := 'RB';
  else
    if v_exp is null or v_exp < 144 then
      raise exception 'Mentors must have at least 12 years of experience (got % months)', coalesce(v_exp::text,'none');
    end if;
    v_prefix := 'MN';
  end if;
  select v_prefix || lpad((coalesce(max(substring(employee_code from 3)::int), 0) + 1)::text, 3, '0') into v_code
  from profiles where employee_code ~ ('^' || v_prefix || '\d+$');
  insert into profiles(employee_code, full_name, email, phone, role, department, region, designation,
                       experience_months, max_trainees)
  values (v_code, trim(p->>'full_name'), lower(p->>'email'), p->>'phone', v_role, v_dept, initcap(p->>'region'),
          p->>'designation', v_exp, coalesce((p->>'max_trainees')::int, 50))
  returning id into v_id;
  perform log_audit('staff_added','profile',v_id::text, jsonb_build_object('role',v_role,'department',v_dept));
  return jsonb_build_object('id', v_id, 'employee_code', v_code);
end $$;

-- HR can mark a boss or mentor inactive (e.g. leaves the bank); their joinees must be reassigned first
create or replace function hr_set_staff_active(p_profile uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_role() not in ('hr','admin') then raise exception 'Only HR can change staff'; end if;
  if not p_active and exists (select 1 from profiles t where t.role = 'trainee' and t.is_active
                              and p_profile in (t.mentor_id, t.manager_id)) then
    raise exception 'Reassign this person''s joinees before deactivating them';
  end if;
  update profiles set is_active = p_active,
         account_status = case when p_active then account_status else 'disabled' end
  where id = p_profile and role in ('mentor','reporting_manager');
  perform log_audit(case when p_active then 'staff_activated' else 'staff_deactivated' end,'profile',p_profile::text,'{}');
end $$;

grant select on v_logins to authenticated;
