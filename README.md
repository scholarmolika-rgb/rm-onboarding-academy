# RM Onboarding Academy

A 30-day, gated onboarding platform for corporate Relationship Managers in a large private bank, with an AI assistant, automatic escalations and a leadership business case. Built on **Supabase** (Postgres, Auth, Edge Functions, Storage, pgvector), developed in **VS Code**, versioned on **GitHub**.

Sized for one intake of **1,000 new RMs, 20 mentors, 20 reporting managers and 5 HR partners**.

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
  seed.sql                  phases, 7 modules, 38 learning items, 3 assessments, 1,000/20/20/5 org
  seed_questions.sql        generated: 58 bank questions + 40 personalised calculation variants
  functions/
    notify-dispatch/        sends queued emails (Resend; swap for MS Graph/SMTP)
    chatbot/                RAG assistant (Claude or any OpenAI-compatible model, incl. on-prem Llama)
    daily-scheduler/        nightly risk scores, SLA breaches, inactivity nudges
content/                    readable notes per day + working files (KYC checklist, pricing & P&L workbook)
web/index.html              clickable prototype (all five roles + assistant) – demo data
design-system/              tokens.json, components.css, README (the design system)
docs/                       build pathway, business case, real-world additions
scripts/                    question seed builder, knowledge-base ingestion
```

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
supabase db reset                        # runs migrations + seeds (1,046 people, 98 questions)
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

Integrity suite: serving before the honour declaration, a second session, going back and late answers are all refused; leaving the screen + paste holds a 90% pass for review; mentor voids it; re-sit is refused until a supervised window opens, then passes without using an attempt; a clean candidate passes straight through. Run it with the CI workflow or `psql -f supabase/tests/gating_test.sql`.
