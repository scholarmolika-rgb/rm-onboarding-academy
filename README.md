# RM Onboarding Academy

A 30-day, gated onboarding platform for corporate Relationship Managers in a large private bank, with an AI assistant, automatic escalations and a leadership business case. Built on **Supabase** (Postgres, Auth, Edge Functions, Storage, pgvector), developed in **VS Code**, versioned on **GitHub**.

Sized for a cohort of **1,000 new RMs** (each with more than 3 and less than 5 years' experience), **20 Reporting Bosses** (10 to under 15 years, in the joinee's own department), **20 Mentors** (always from a different department) and **5 HR partners** (one per region). The cohort starts with 24 demo joinees; HR adds the rest. See `docs/PEOPLE_MODEL.md`.

## The programme

| Days | Phase | Gate |
|---|---|---|
| 1–3 | Governance, regulation & conduct (KYC/AML, RBI, FEMA, DPDP) | |
| 4–5 | People, culture & the RM role | |
| 6–10 | Corporate banking products | |
| 11–14 | Credit & operating processes | |
| **15** | **Foundation assessment** | **≥ 80%** — else email Mentor + Reporting Manager + HR; 1 coaching day each; pass or repeat named modules |
| 16–20 | Product pricing, RAROC, relationship P&L | |
| **21** | **Pricing & P&L assessment** | **≥ 75%** — else Mentor + Reporting Manager coach; pass or repeat |
| 22–29 | Live customer shadowing with mentor | |
| **30** | **Certification assessment + tri-party sign-off** | ≥ 80% and Mentor + Manager + HR approve |

Guardrails added: two attempts per gate (a second miss goes to an HR performance review), and an **assessment-integrity layer** so AI tools or shared answers cannot inflate a score. See `docs/ASSESSMENT_INTEGRITY.md`.

## What's in the repo

```
supabase/
  migrations/
    ..._schema.sql          tables: people, curriculum, attempts, journeys, escalations, coaching, shadow logs, sign-offs, outbox, audit
    ..._gating_engine.sql   start_attempt, submit_attempt, handle_gate_outcome, record_coaching, sign_off, risk score
    ..._rls_views_cron.sql  row-level security per role, dashboard views, cron schedule
    ..._chatbot_sla.sql     vector search for the assistant, SLA breach detection
    ..._assessment_integrity.sql  one-question-at-a-time delivery, server timers, integrity score, verification viva
    ..._people_model.sql    departments, personas, mentor-from-another-department rule, 1,000 seats, hr_create_joinee(s)
  seed.sql                  phases, 7 modules, 38 learning items, 3 assessments, 1,000/20/20/5 org
  seed_questions.sql        generated: 58 bank questions + 40 personalised calculation variants
  functions/
    notify-dispatch/        sends queued emails (Resend; swap for MS Graph/SMTP)
    chatbot/                RAG assistant (Claude or any OpenAI-compatible model, incl. on-prem Llama)
    daily-scheduler/        nightly risk scores, SLA breaches, inactivity nudges
content/                    readable notes per day + working files (KYC checklist, pricing & P&L workbook)
web/src/app.template.html   the app (four interfaces + chatbot); build with scripts/build_prototype.py
web/index.html              built app with the /content curriculum embedded – demo data
web/supabase-client.js      the calls that replace demo data with live Supabase data
design-system/              tokens.json, components.css, README (the design system)
docs/                       build pathway, business case, real-world additions
scripts/                    question seed builder, knowledge-base ingestion
```

## The app: four interfaces

| Interface | Menu | What they do |
|---|---|---|
| **New Joinee** | My day · Training programme · Assessments · Shadow log · Ask the Academy | Reads the day's notes, uses working files and calculators, takes the three gated tests, logs shadow interactions, asks the chatbot |
| **Mentor** | My trainees · Coaching & checks · Shadow reviews · Day-30 sign-off | Coaching day at Gate 1 and 2, verifies held results, rates shadow logs, runs the Day-30 viva and signs |
| **Reporting Boss** | My team · Coaching · Day-30 sign-off | Coaching day at Gate 1 and 2, signs Day 30 |
| **HR** | Programme health · New joinees · Coaching & reviews · Test integrity · People & capacity · Email log · Day-30 sign-off | Adds joinees one by one or by CSV (auto-assigned boss, mentor and HR partner), coaching day at Gate 1 and Day 30, decides after two failed attempts, watches attrition risk and capacity, signs Day 30 |

The chatbot is available in all four interfaces and answers from `/content`. In production each person signs in with SSO and sees only their own interface (`profiles.role`: `trainee`, `mentor`, `reporting_manager` = Reporting Boss, `hr`). There is no business-case screen; the numbers in `docs/BUSINESS_CASE.md` are for planning only.

After editing anything in `/content`, rebuild the app so trainees see the change: `python3 scripts/build_prototype.py`.

## Run it locally (about 30 minutes)

Prerequisites: VS Code, Git, Node 20+, Docker Desktop, Supabase CLI (`npm i -g supabase`), Deno extension for VS Code.

```bash
git clone https://github.com/<you>/rm-onboarding-academy.git && cd rm-onboarding-academy
supabase init                        # accept defaults; creates supabase/config.toml
```
In `supabase/config.toml` set the seed files:
```toml
[db.seed]
sql_paths = ["./seed.sql", "./seed_questions.sql"]
```
Then:
```bash
python3 scripts/build_question_seed.py   # regenerates seed_questions.sql after you edit the question bank
supabase start                           # local Postgres, Auth, Studio at http://localhost:54323
supabase db reset                        # runs migrations + seeds (5 HR, 20 bosses, 20 mentors, 24 demo joinees, 98 questions)
cp .env.example supabase/functions/.env  # fill keys
supabase functions serve --env-file supabase/functions/.env
node scripts/ingest-kb.mjs               # loads /content into the assistant's knowledge base
```
Open `web/index.html` with the VS Code *Live Server* extension to see the prototype.

## Deploy

```bash
supabase link --project-ref <ref>
supabase db push
supabase functions deploy notify-dispatch chatbot daily-scheduler
supabase secrets set --env-file supabase/functions/.env
```
Then enable `pg_cron` and `pg_net` in the dashboard and run the two `cron.schedule` statements at the bottom of the RLS migration. For a bank, use Supabase on AWS Mumbai (ap-south-1) or self-host Supabase inside the bank's network, and SSO through Azure AD / Okta (SAML).

See **docs/BUILD_PATHWAY.md** for the full 10-week plan.

## Tested

The gating engine was run end to end on Postgres 16: fail Gate 1 → three coaching sessions + emails queued → HR requests repeat → remediation → retake passes → Gate 2 → Final → three sign-offs → certified; coach-pass path; Gate 2 escalates to two coaches only; blocked when mandatory learning is open; mentor cannot sign off without a Day-30 viva.

Integrity suite: serving before the honour declaration, a second session, going back and late answers are all refused; leaving the screen + paste holds a 90% pass for review; mentor voids it; re-sit is refused until a supervised window opens, then passes without using an attempt; a clean candidate passes straight through.

People-model suite: 20 bosses all 10–15 years; every joinee 3–5 years; no mentor from the joinee's department; no boss from another department; 30- and 60-month joinees refused; wrong-department mentor or boss refused; auto-assignment and emails; bulk import with one bad row; full cohort refused; non-HR users cannot add joinees. Run it with the CI workflow or `psql -f supabase/tests/gating_test.sql`.
