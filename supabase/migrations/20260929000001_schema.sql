-- =====================================================================
-- RM Onboarding Academy — core schema
-- Supabase / Postgres 15+
-- =====================================================================
create extension if not exists "pgcrypto";
create extension if not exists "vector";

-- ---------- Enums ----------------------------------------------------
create type app_role        as enum ('trainee','mentor','reporting_manager','hr','leadership','admin');
create type journey_status  as enum ('active','awaiting_assessment','coaching','remediation',
                                     'hr_review','certified','exited');
create type escalation_state as enum ('open','coaching','decided','closed','sla_breached');
create type coach_decision  as enum ('pass','repeat');
create type item_kind       as enum ('read','video','worksheet','simulation','case','quiz','shadow_task');
create type progress_state  as enum ('not_started','in_progress','completed');

-- ---------- Organisation ---------------------------------------------
create table cohorts (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  start_date    date not null,
  -- training days skip weekends + bank holidays listed here
  holidays      date[] not null default '{}',
  created_at    timestamptz not null default now()
);

create table profiles (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid unique,                        -- linked to auth.users on first SSO login
  employee_code  text unique not null,
  full_name      text not null,
  email          text unique not null,
  phone          text,
  role           app_role not null,
  branch         text,
  region         text,
  cohort_id      uuid references cohorts(id),
  mentor_id      uuid references profiles(id),
  manager_id     uuid references profiles(id),
  hr_id          uuid references profiles(id),
  joined_on      date,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);
create index on profiles(mentor_id);
create index on profiles(manager_id);
create index on profiles(hr_id);
create index on profiles(cohort_id);

-- ---------- Curriculum -----------------------------------------------
create table phases (
  id        smallint primary key,
  code      text unique not null,
  title     text not null,
  day_from  smallint not null,
  day_to    smallint not null
);

create table modules (
  id        serial primary key,
  phase_id  smallint not null references phases(id),
  code      text unique not null,
  title     text not null,
  pillar    text not null,  -- governance | people | product | process | pricing | pnl | shadowing
  day_from  smallint not null,
  day_to    smallint not null,
  sort      smallint not null default 0
);

create table learning_items (
  id            serial primary key,
  module_id     int not null references modules(id) on delete cascade,
  day_no        smallint not null check (day_no between 1 and 30),
  title         text not null,
  kind          item_kind not null,
  storage_path  text,            -- Supabase Storage path: training/<module>/<file>
  est_minutes   smallint not null default 30,
  mandatory     boolean not null default true,
  sort          smallint not null default 0
);

create table progress (
  trainee_id    uuid not null references profiles(id) on delete cascade,
  item_id       int  not null references learning_items(id) on delete cascade,
  status        progress_state not null default 'not_started',
  minutes_spent int not null default 0,
  completed_at  timestamptz,
  primary key (trainee_id, item_id)
);

-- ---------- Assessments ----------------------------------------------
create table assessments (
  id              serial primary key,
  code            text unique not null,     -- GATE_1 | GATE_2 | FINAL
  title           text not null,
  unlocks_phase   smallint references phases(id),
  day_no          smallint not null,
  pass_pct        numeric(5,2) not null,
  question_count  smallint not null,
  duration_min    smallint not null,
  max_attempts    smallint not null default 2,
  coach_roles     app_role[] not null,       -- who is escalated to + must coach
  signoff_roles   app_role[] not null default '{}'
);

create table questions (
  id            serial primary key,
  assessment_id int not null references assessments(id) on delete cascade,
  module_id     int references modules(id),
  stem          text not null,
  options       jsonb not null,              -- ["A","B","C","D"]
  answer_idx    smallint not null,
  difficulty    smallint not null default 2 check (difficulty between 1 and 3),
  explanation   text,
  is_active     boolean not null default true
);

create table attempts (
  id            uuid primary key default gen_random_uuid(),
  trainee_id    uuid not null references profiles(id) on delete cascade,
  assessment_id int  not null references assessments(id),
  attempt_no    smallint not null,
  question_ids  int[] not null,
  answers       jsonb,
  started_at    timestamptz not null default now(),
  submitted_at  timestamptz,
  score_pct     numeric(5,2),
  passed        boolean,
  module_scores jsonb,                        -- {"GOV":85,"PPL":60,...} → drives targeted remediation
  unique (trainee_id, assessment_id, attempt_no)
);

-- ---------- Journey / state machine -----------------------------------
create table journeys (
  trainee_id          uuid primary key references profiles(id) on delete cascade,
  current_phase       smallint not null default 1 references phases(id),
  status              journey_status not null default 'active',
  phase2_unlocked_at  timestamptz,
  phase3_unlocked_at  timestamptz,
  certified_at        timestamptz,
  exit_reason         text,
  risk_score          numeric(5,2) not null default 0,  -- early attrition-risk signal 0-100
  updated_at          timestamptz not null default now()
);

create table escalations (
  id             uuid primary key default gen_random_uuid(),
  trainee_id     uuid not null references profiles(id) on delete cascade,
  attempt_id     uuid not null references attempts(id),
  assessment_id  int not null references assessments(id),
  state          escalation_state not null default 'open',
  sla_due        timestamptz not null,
  outcome        coach_decision,
  created_at     timestamptz not null default now(),
  closed_at      timestamptz
);

create table coaching_sessions (
  id             uuid primary key default gen_random_uuid(),
  escalation_id  uuid not null references escalations(id) on delete cascade,
  coach_id       uuid not null references profiles(id),
  coach_role     app_role not null,
  scheduled_on   date,
  completed_at   timestamptz,
  notes          text,
  decision       coach_decision,
  repeat_modules int[] not null default '{}',
  unique (escalation_id, coach_role)
);

create table remediation_assignments (
  id             uuid primary key default gen_random_uuid(),
  trainee_id     uuid not null references profiles(id) on delete cascade,
  escalation_id  uuid not null references escalations(id) on delete cascade,
  module_id      int not null references modules(id),
  due_on         date,
  completed_at   timestamptz,
  unique (escalation_id, module_id)
);

-- ---------- Shadowing (Day 22-29) — no raw customer PII stored ---------
create table shadow_logs (
  id               uuid primary key default gen_random_uuid(),
  trainee_id       uuid not null references profiles(id) on delete cascade,
  mentor_id        uuid not null references profiles(id),
  day_no           smallint not null check (day_no between 22 and 29),
  customer_ref     text not null,            -- masked / hashed CIF, never the raw id
  interaction      text not null,            -- call | visit | credit_note | kyc_review | pricing_discussion | complaint
  competencies     jsonb not null default '{}', -- {"needs_discovery":4,"compliance":5,...} 1-5
  mentor_rating    smallint check (mentor_rating between 1 and 5),
  trainee_reflection text,
  mentor_notes     text,
  created_at       timestamptz not null default now()
);

-- ---------- Final sign-off --------------------------------------------
create table signoffs (
  trainee_id  uuid not null references profiles(id) on delete cascade,
  role        app_role not null,
  signer_id   uuid not null references profiles(id),
  approved    boolean not null,
  comments    text,
  signed_at   timestamptz not null default now(),
  primary key (trainee_id, role)
);

-- ---------- Engagement & wellbeing ------------------------------------
create table pulse_surveys (
  id          uuid primary key default gen_random_uuid(),
  trainee_id  uuid not null references profiles(id) on delete cascade,
  day_no      smallint not null,
  confidence  smallint check (confidence between 1 and 5),
  belonging   smallint check (belonging between 1 and 5),
  workload    smallint check (workload between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now()
);

-- ---------- Notifications (transactional outbox) ----------------------
create table notification_outbox (
  id          uuid primary key default gen_random_uuid(),
  to_emails   text[] not null,
  cc_emails   text[] not null default '{}',
  template    text not null,
  payload     jsonb not null default '{}',
  status      text not null default 'pending',  -- pending | sent | failed
  tries       smallint not null default 0,
  last_error  text,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);
create index on notification_outbox(status) where status = 'pending';

-- ---------- Chatbot knowledge base + history --------------------------
create table kb_chunks (
  id         bigserial primary key,
  source     text not null,        -- file path in /content
  module_id  int references modules(id),
  heading    text,
  content    text not null,
  embedding  vector(384)           -- Supabase built-in gte-small
);
create index on kb_chunks using hnsw (embedding vector_cosine_ops);

create table chat_messages (
  id          bigserial primary key,
  profile_id  uuid not null references profiles(id) on delete cascade,
  role        text not null check (role in ('user','assistant')),
  content     text not null,
  sources     jsonb,
  created_at  timestamptz not null default now()
);

-- ---------- Audit trail (regulator-friendly, append only) --------------
create table audit_log (
  id          bigserial primary key,
  actor_id    uuid,
  action      text not null,
  entity      text not null,
  entity_id   text,
  detail      jsonb,
  at          timestamptz not null default now()
);
