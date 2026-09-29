-- Load every CSV in the right order (command-line alternative to the Table Editor upload).
-- Run from the repository root:  psql "$SUPABASE_DB_URL" -f supabase/csv/import_all.sql
-- Needs the migrations applied first (supabase db push); departments come from migration 006.
-- Run once on an empty project.
\set ON_ERROR_STOP on
-- demo joinees are optional: psql -v include_demo=true ... (default false)
\if :{?include_demo}
\else
\set include_demo false
\endif
begin;
\echo 01_cohorts.csv -> cohorts
\copy cohorts(id, name, start_date, holidays, capacity) from 'supabase/csv/01_cohorts.csv' with (format csv, header true)
\echo 02_phases.csv -> phases
\copy phases(id, code, title, day_from, day_to) from 'supabase/csv/02_phases.csv' with (format csv, header true)
\echo 03_modules.csv -> modules
\copy modules(id, phase_id, code, title, pillar, day_from, day_to, sort) from 'supabase/csv/03_modules.csv' with (format csv, header true)
\echo 04_learning_items.csv -> learning_items
\copy learning_items(id, module_id, day_no, title, kind, storage_path, est_minutes, mandatory, sort) from 'supabase/csv/04_learning_items.csv' with (format csv, header true)
\echo 05_assessments.csv -> assessments
\copy assessments(id, code, title, unlocks_phase, day_no, pass_pct, question_count, duration_min, max_attempts, coach_roles, signoff_roles, secure_delivery, seconds_per_question, integrity_review_threshold) from 'supabase/csv/05_assessments.csv' with (format csv, header true)
\echo 06_questions.csv -> questions
\copy questions(id, assessment_id, module_id, stem, options, answer_idx, difficulty, explanation, family, is_calc, is_active) from 'supabase/csv/06_questions.csv' with (format csv, header true)
\echo 07_profiles_hr.csv -> profiles
\copy profiles(id, employee_code, full_name, email, phone, role, region, department, designation, experience_months, previous_employer, previous_role, start_date, joined_on, cohort_id, mentor_id, manager_id, hr_id, max_trainees, is_active) from 'supabase/csv/07_profiles_hr.csv' with (format csv, header true)
\echo 08_profiles_reporting_bosses.csv -> profiles
\copy profiles(id, employee_code, full_name, email, phone, role, region, department, designation, experience_months, previous_employer, previous_role, start_date, joined_on, cohort_id, mentor_id, manager_id, hr_id, max_trainees, is_active) from 'supabase/csv/08_profiles_reporting_bosses.csv' with (format csv, header true)
\echo 09_profiles_mentors.csv -> profiles
\copy profiles(id, employee_code, full_name, email, phone, role, region, department, designation, experience_months, previous_employer, previous_role, start_date, joined_on, cohort_id, mentor_id, manager_id, hr_id, max_trainees, is_active) from 'supabase/csv/09_profiles_mentors.csv' with (format csv, header true)
\if :include_demo
\echo 10_profiles_joinees_demo.csv -> profiles
\copy profiles(id, employee_code, full_name, email, phone, role, region, department, designation, experience_months, previous_employer, previous_role, start_date, joined_on, cohort_id, mentor_id, manager_id, hr_id, max_trainees, is_active) from 'supabase/csv/10_profiles_joinees_demo.csv' with (format csv, header true)
\else
\echo 10_profiles_joinees_demo.csv skipped (include_demo=false)
\endif
\i supabase/csv/after_import.sql
commit;
