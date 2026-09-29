# Master prompt — RM Onboarding Academy

Two parts:
- **Part A** rebuilds this exact project in one go. Paste it into a new Claude conversation.
- **Part B** is a reusable template for other training or onboarding platforms. Fill in the `[brackets]`.

Tip: if the tool you paste into has a length limit, paste Part A section by section and say "wait for all sections before starting" in the first message.

---

## Part A — Full prompt for this project

```
ROLE
You are an expert full-stack engineer and product designer who knows the major open and closed
AI models and tools. Build a working onboarding agent and web app for Relationship Managers (RMs)
joining the corporate banking business of a large private bank in India. Build it end to end:
database, back-end logic, training content, app, chatbot, design system, documentation and a
GitHub repository. Where my brief misses something a real bank would need, add it and tell me
what you added.

TECH STACK
- Low-code friendly: plain HTML/JS front end editable in Visual Studio Code, no heavy framework.
- Supabase: Postgres (all business rules as SQL functions and triggers), Row Level Security,
  Auth, Storage, Edge Functions (Deno), pg_cron, pgvector.
- GitHub repository with the code, the training files, and a CI workflow that runs database tests
  on every push.
- Chatbot: retrieval over the training content; Claude by default, swappable for any
  OpenAI-compatible model (Azure OpenAI, or on-premises Llama/Mistral) through one setting.
- Email: transactional outbox table drained by an Edge Function (Resend for the pilot,
  Microsoft Graph or the bank's SMTP relay in production).

SCALE
One cohort of up to 1,000 New Joinees, 20 Reporting Bosses, 20 Mentors and 5 HR partners
(one per region: North, South, East, West, Central).

THE 30-DAY PROGRAMME
Training days skip weekends and bank holidays.
- Days 1–15, Foundation: Governance (RBI, PMLA/KYC/AML, FEMA, SEBI, DPDP Act 2023, code of
  conduct), People (RM role, KRAs, consultative selling, POSH), Products (working capital,
  term loans, trade finance, transaction banking, treasury/FX), Processes (onboarding, credit
  appraisal/CAM, documentation, CERSAI, monitoring, SMA/NPA, complaints).
  Every day has readable notes AND working files (checklists, calculators, templates, cases).
- Day 15, Gate 1: assessment, pass mark 80%. Next modules open only on a pass.
  Below 80%: email the Mentor, Reporting Boss and HR together. Each gives one day of one-on-one
  coaching. Each then records Pass or Repeat, naming modules to repeat. If any coach says Repeat,
  the named modules are reassigned and the trainee re-takes the test; if all say Pass, the next
  phase opens.
- Days 16–20, Product pricing and P&L: EBLR/MCLR, funds transfer pricing, spreads, PD × LGD × EAD,
  capital, RAROC, fees, pricing deviations, relationship P&L, portfolio P&L and wallet share.
  Include an Excel workbook with live formulas (drawing power, loan pricing/RAROC, relationship P&L).
- Day 21, Gate 2: pass mark 75%. Below it: Mentor and Reporting Boss each coach one day, then
  Pass or Repeat, as above.
- Days 22–29, shadowing: real customer handling alongside the Mentor. The trainee logs each
  interaction (masked client reference only, never names, PAN, Aadhaar or account numbers); the
  Mentor rates it against a 6-competency rubric. 4 approved logs are needed before Day 30.
- Day 30: certification assessment (80%), a Mentor viva (score 3/5 or more), then sign-off by
  Mentor, Reporting Boss and HR. Certified only when all three approve; any rejection goes to
  HR review.

REAL-WORLD RULES TO ADD
- Two attempts per gate; a second miss goes to an HR performance review (extend or exit).
- Coaching decisions due within 3 working days; overdue ones escalate to HR and the Reporting Boss.
- A gate opens only when that phase's mandatory learning is complete.
- Attrition-risk score per trainee (test gaps, coaching events, inactivity, pulse surveys),
  recomputed nightly; pulse surveys visible to HR only.
- Inactivity nudges after 48 hours; supportive tone to trainees; never put scores in email subjects.
- Append-only audit log of every score, coaching decision, unlock, sign-off and access change.
- Row Level Security: trainees see only themselves; bosses and mentors only their own joinees;
  HR sees everyone.
- Maker-checker system access only after Gate 2. DPDP-compliant data handling, data residency
  in India, quarterly compliance review of regulatory figures in the content.
- Capacity: warn HR that one wave of 1,000 overloads coaches; recommend four monthly waves of 250.

ASSESSMENT INTEGRITY (candidates using AI during tests)
Trainees may learn with AI through the chatbot, but tests must measure what the person knows.
Layer these controls; people make every final decision, signals never fail anyone automatically:
1. Question design: calculation questions in families with different numbers per trainee;
   bank-specific scenario questions; a large rotating question bank.
2. Delivery: one question at a time, server-side timer (about 75 s each), no going back, options
   shuffled per trainee, answer key never sent to the browser, one session per attempt, honour
   declaration before starting.
3. Environment: chatbot paused while a test is open; question bank never indexed by the chatbot;
   notes hidden during tests; full-screen; scheduled sitting windows; locked-down browser
   (e.g. Safe Exam Browser) on bank laptops; supervised re-sits.
4. Signals → integrity score 0–100: leaving the screen, copy/paste, full-screen exit, IP change,
   second session, trying the chatbot, correct calculations in under 8 seconds, identical wrong
   answers to a cohort peer. The trainee sees their own recorded activity.
5. Humans decide: a pass with a high integrity score is held; the Mentor holds a 20-minute
   verification viva (trainee explains 3–4 answers) and confirms or voids. A voided result means a
   supervised re-sit that does not use an attempt, plus an HR conduct review.

PEOPLE MODEL
- New Joinee persona: more than 3 and less than 5 years' experience (37–59 months).
- Reporting Boss persona: 20 in total, 10 to under 15 years' experience, in the SAME department the
  joinee joins after Day 30; up to 50 joinees each.
- Mentor: always from a DIFFERENT department than the joinee (independent assessment, wider view of
  the bank); 12+ years' experience; up to 50 joinees each.
- Departments: Large Corporate, Mid-Corporate, Emerging Corporates (SME), Transaction Banking,
  Trade & Supply Chain Finance.
- Auto-assignment when HR adds a joinee: boss from the same department, mentor from another
  department, same region first, then lowest load; HR partner by region. Enforce the rules with
  a database trigger so nothing can bypass them.
- The cohort has 1,000 seats but must NOT be pre-filled: seed only a small demo intake
  (about 24) so HR can test by adding joinees.

APP: FRONT PAGE AND FOUR INTERFACES
- The app opens on the Academy's front page (programme overview, notices) with a sign-in box.
  Use a generic academy name, not a real bank's branding.
- Four interfaces, each seeing only its own: New Joinee, Mentor, Reporting Boss, HR.
  No business-case or ROI screen in the app (keep those numbers in a planning document only).
- New Joinee: My day (30-day strip, today's items, what's next, private pulse survey),
  Training programme (all 30 days, full readable notes, working files, interactive calculators,
  later phases locked until the gate is passed), Assessments (secure test mode), Shadow log,
  Ask the Academy (chatbot page).
- Mentor: My trainees, Coaching & checks (coaching cards, held-result verification), Shadow reviews,
  Day-30 sign-off with required viva.
- Reporting Boss: My team, Coaching, Day-30 sign-off.
- HR: Programme health, New joinees (add one with a live assignment preview, CSV bulk import with a
  per-row error report, roster with search and filter, withdraw before Day 1 to free the seat,
  seat counter "N of 1,000"), Logins & access, Coaching & reviews (including the two-attempt
  decision), Test integrity, People & capacity (all bosses, mentors, HR with experience and load,
  plus a form to add Reporting Bosses and Mentors with persona checks), Email log, Day-30 sign-off.
- The chatbot is available in all four interfaces, answers only from the training content, names
  its source, adapts to the role, refuses to give test answers or handle customer personal data,
  and masks PAN/Aadhaar/account numbers.

ACCESS AND LOGINS
- No self-registration. Only people HR has added (New Joinee, Reporting Boss, Mentor) can sign in.
  Only HR can add people and create login IDs and passwords.
- Login ID = employee code (TRN0025, RB005, MN012, HR001), not case-sensitive.
- HR creates a login and sees a temporary password once, to hand over in person or by secure
  message; the email to the person carries only the login ID.
- First sign-in forces a new password (10+ characters, letters and numbers). The same error message
  for a wrong ID or a wrong password. 5 failed attempts lock the login until HR resets it.
  HR can reset, disable and enable. Sessions end after 15 minutes idle.
- In Supabase: a trigger on auth.users refuses any account without an HR-issued login; an HR-only
  Edge Function creates, resets, disables and enables auth users with the service role; sign-up
  switched off.
- The prototype front page shows four demo accounts (one per interface), clearly marked for
  removal before real use.

DESIGN
Minimal colours and a professional, calm look. One ink-blue accent used only where something is
actionable or selected; neutral greys biased toward that blue; green/amber/red only for states
(cleared / gate or coaching / fail or breach). Serif display face for titles, clean sans for body,
mono for codes. Borders, not shadows. Light and dark themes. Works on phones. Indian number and
money formats (₹ lakh, ₹ Cr).
Also create a DESIGN SYSTEM to refer to later: colour, type, spacing, radius and shadow tokens
with usage notes; principles; content and tone rules; components (Button, StatusPill, StatTile,
Panel, the 30-day strip, CoachingCard, SecureQuestion, AssignmentPreview); rules for assessment,
people and sign-in screens.

DELIVERABLES
1. Supabase migrations: schema; gating engine (start/submit attempt, gate outcome, coaching,
   remediation, sign-off, risk score); RLS and views; chatbot search and SLA checks; assessment
   integrity; people model; HR-issued logins. Seed data and a question bank with calculation variants.
2. Edge Functions: email dispatcher, chatbot (retrieval), nightly scheduler, HR login provisioning.
3. Training content for every day (markdown), working files (CSV checklists, Excel workbook with
   formulas), question bank (JSON) and a script that builds the question seed.
4. The web app (one HTML file built from a template plus the /content folder), and a
   supabase-client.js showing every live call that replaces demo data.
5. SQL test suite covering gates, coaching, integrity, people rules and logins, run by GitHub Actions.
6. Docs: README, 10-week build pathway (app and chatbot tracks in parallel, with a low-code options
   comparison), business case (planning only: attrition cost, client loss, net benefit),
   assessment integrity, people model, access and logins, real-world additions.
7. The design system.
8. The repository pushed to GitHub.

HOW TO WORK
Build in stages and test each one: run the SQL tests on a real Postgres, click through every role
in a browser, and check phone width. Keep a task list. Show me a working prototype early, then
refine. At the end, give me a short summary of what exists, what you assumed, and what the bank
must do itself (e.g. Compliance review of content, IT set-up of the locked-down browser, HR
approval of the viva and conduct process).
```

---

## Part B — Reusable template for other projects

```
ROLE
You are an expert full-stack engineer and product designer who knows the major open and closed
AI models and tools. Build a working [AGENT/APP TYPE, e.g. onboarding platform] for
[AUDIENCE, e.g. new Relationship Managers] at [ORGANISATION TYPE, e.g. a large private bank in
India]. Build it end to end: database, back-end logic, content, app, chatbot, design system,
documentation and a GitHub repository. Where my brief misses real-world needs, add them and list
what you added.

TECH STACK
[Default: plain HTML/JS editable in VS Code; Supabase (Postgres + RLS + Auth + Storage + Edge
Functions + pg_cron + pgvector); GitHub with CI running database tests; chatbot swappable between
Claude and OpenAI-compatible or on-prem models.]

SCALE
[Number of learners, coaches/mentors, managers, admins/HR; regions; cohorts or waves.]

PROGRAMME
[Duration and phases. For each phase: days, topics, and the readable notes and working files needed.]
[Gates: day, pass mark, what unlocks, who is emailed on a fail, who coaches and for how long,
 how the coaches decide pass or repeat, maximum attempts, what happens after the last attempt.]
[Practical phase (shadowing, projects): what is logged, who rates it, what is required to finish.]
[Final certification: test, oral check, who signs off.]

REAL-WORLD RULES
[SLAs for coaches, prerequisites before tests, working-day calendar, risk/attrition signals,
 audit log, data protection law, data residency, compliance review of content, capacity warnings.]

ASSESSMENT INTEGRITY
[Keep the five layers: question design (personalised numbers, organisation-specific scenarios),
 server-controlled delivery, locked environment (chatbot paused), behaviour signals → score,
 human verification before any penalty.]

PEOPLE MODEL
[Personas with experience ranges; who must be from the same or a different department;
 load limits; auto-assignment rules; seat capacity and whether to pre-fill it.]

APP
[Front page content. Interfaces per role and the menu items for each. Screens that must NOT
 appear in the app. What the chatbot may and may not answer.]

ACCESS
[Who can create people and logins; login ID format; temporary-password and first-sign-in rules;
 lockout; session timeout; SSO plans.]

DESIGN
[Colour mood (e.g. minimal and professional), accent colour, fonts, light/dark, mobile,
 local number/currency formats.] Also create a reusable design system (tokens with usage notes,
 principles, content rules, components, screen rules).

DELIVERABLES
[Migrations, Edge Functions, content and working files, question bank, web app, client API file,
 tests with CI, docs (README, build pathway, business case for planning, integrity, people model,
 access), design system, GitHub repository.]

HOW TO WORK
Build in stages and test each stage (SQL tests on real Postgres, click through every role in a
browser, phone width). Keep a task list, show a prototype early, then refine. Finish with what
exists, what you assumed, and what the organisation must do itself.
```

---

## What each part of the prompt produced in this project
| Prompt section | Where it lives in the repository |
|---|---|
| Programme, gates, coaching, sign-off | `supabase/migrations/…02_gating_engine.sql`, `…03_rls_views_cron.sql` |
| Assessment integrity | `…05_assessment_integrity.sql`, `docs/ASSESSMENT_INTEGRITY.md` |
| People model | `…06_people_model.sql`, `docs/PEOPLE_MODEL.md` |
| Access and logins | `…07_logins.sql`, `supabase/functions/hr-provision-user/`, `docs/ACCESS_AND_LOGINS.md` |
| Content and working files | `content/`, `scripts/build_question_seed.py` |
| App and chatbot | `web/src/app.template.html`, `scripts/build_prototype.py`, `supabase/functions/chatbot/` |
| Design system | `design-system/` |
| Build pathway and business case | `docs/BUILD_PATHWAY.md`, `docs/BUSINESS_CASE.md` |
