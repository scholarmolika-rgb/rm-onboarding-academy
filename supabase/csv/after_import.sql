-- Run once after uploading the CSVs (Table Editor path: paste into the SQL Editor and Run).
-- 1. Serial ids were imported explicitly, so move each counter past the highest id.
select setval(pg_get_serial_sequence('modules','id'),        (select max(id) from modules));
select setval(pg_get_serial_sequence('learning_items','id'), (select max(id) from learning_items));
select setval(pg_get_serial_sequence('assessments','id'),    (select max(id) from assessments));
select setval(pg_get_serial_sequence('questions','id'),      (select max(id) from questions));
-- 2. Every joinee needs a journey row (the insert trigger creates it; this covers any import path).
insert into journeys(trainee_id) select id from profiles where role = 'trainee' on conflict do nothing;
-- 3. Checks: each line should say ok.
select case when count(*) = 5 then 'ok' else 'CHECK departments (migration 006)' end as departments from departments;
select case when count(*) = 5 then 'ok' else 'CHECK HR partners' end as hr from profiles where role = 'hr';
select case when count(*) = 20 then 'ok' else 'CHECK Reporting Bosses' end as bosses from profiles where role = 'reporting_manager';
select case when count(*) = 20 then 'ok' else 'CHECK mentors' end as mentors from profiles where role = 'mentor';
select case when count(*) = 0 then 'ok' else 'CHECK mentor from same department' end as mentor_rule
  from profiles t join profiles m on m.id = t.mentor_id where t.role = 'trainee' and m.department = t.department;
select case when count(*) = (select count(*) from profiles where role = 'trainee') then 'ok' else 'CHECK journeys' end as journeys from journeys;
select name, capacity, used, free from v_seat_usage;
