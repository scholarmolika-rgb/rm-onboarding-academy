# Build pathway — from repo to a live bank pilot

Ten weeks, one small team: 1 full-stack developer (you, in VS Code), 1 L&D content owner, 1 HR partner, part-time Information Security and Compliance reviewers. The agent and the app are built in parallel tracks so a demo exists from Week 1.

## Architecture in one picture

```
Trainee / Mentor / Manager / HR / Leadership
        │  browser or mobile (SSO via Azure AD / Okta)
        ▼
Front end ── low-code option A: this web/ app (HTML + supabase-js), hosted on Vercel / Netlify / bank CDN
          └─ low-code option B: Appsmith or Budibase (open source, self-hostable) dashboards on Supabase
        │
        ▼
Supabase
  ├─ Auth (SAML SSO)             who you are → profiles.role
  ├─ Postgres + RLS              curriculum, journeys, gates, coaching, audit (rules enforced here)
  ├─ Storage                     training files (PDF, XLSX, video) per module
  ├─ pgvector                    assistant knowledge base
  ├─ Edge Functions              notify-dispatch · chatbot · daily-scheduler
  └─ pg_cron                     every 2 min: emails · nightly: risk, SLA
        │
        ├─ Email: Resend (pilot) → Microsoft Graph / bank SMTP relay (production)
        └─ LLM: Claude API (default) or on-prem Llama / Mistral via OpenAI-compatible endpoint
```

## Track A — the app

| Week | Build | Done when |
|---|---|---|
| 1 | Repo on GitHub, Supabase project, run migrations + seed. Deploy `web/index.html` as the clickable demo. | Leadership demo link works |
| 2 | Supabase Auth with magic-link (pilot) → SAML SSO. Replace demo data in `web/` with `supabase-js` calls: `v_trainee_status`, `start_attempt`, `submit_attempt`. | A seeded trainee logs in and sees their own journey only |
| 3 | Trainee screens: journey strip, today's items (files from Storage), mark complete. **Secure assessment runner**: honour declaration, `serve_question` / `answer_question` one at a time, server timer, event capture (`log_attempt_event`), full screen. | Gate 1 can be taken end to end; refresh, back and second tab are all refused |
| 4 | Coach screens: `v_my_coaching_queue`, `record_coaching`, remediation, **verification viva** (`v_my_integrity_reviews`, `verify_attempt`). HR screens: escalations, integrity dashboard, outbox log, risk list. | Fail → 3 emails → 3 decisions → unlock/repeat works live; held pass → viva → confirm/void |
| 5 | Shadow log (Days 22–29) with masked client reference + mentor rating; Day-30 sign-off with `sign_off`. | A trainee reaches Certified |
| 6 | Leadership dashboard from `v_programme_kpis`; ROI model with the bank's real numbers; CSV export for HRMS. | Head of CB signs off the business case |

## Track B — the agent (Academy Assistant)

| Week | Build | Done when |
|---|---|---|
| 1 | Write/approve content in `content/` (markdown + working files). | L&D owner approves Days 1–15 |
| 2 | Deploy `chatbot` function; `node scripts/ingest-kb.mjs`. | Assistant answers from content with sources |
| 3 | Guardrails: PII redaction, no answer keys, escalate policy questions. Build a 50-question test set; measure accuracy. | ≥ 90% correct, 0 leaks of answers/PII |
| 4 | Personalisation: assistant sees trainee phase, weak modules; suggests the next item. | Weak-module nudges appear after Gate 1 |
| 5 | Mentor co-pilot: drafts coaching notes from module scores; HR co-pilot: weekly cohort summary email. | Coaches accept ≥ 70% of drafts with light edits |
| 6 | Option: move LLM on-prem (vLLM + Llama/Mistral) if InfoSec requires; same function, `LLM_PROVIDER=openai_compatible`. | InfoSec approval |

## Weeks 7–10 — pilot and scale

7. Security review: RLS tests per role, VAPT, DPDP data-flow note, audit-log retention (align with bank policy). **Test integrity set-up**: Safe Exam Browser / MDM kiosk profile on bank laptops, test-room network blocks public AI endpoints, sitting windows per region, L&D rewrites 40% of questions as bank-specific scenarios.
8. Pilot wave: 50 trainees, 4 mentors, 4 managers, 1 HR partner. Daily stand-up on issues.
9. Fix, tune question bank (item analysis: drop questions everyone gets right/wrong), calibrate pass marks and **integrity weights** (target: under 3% of results held, and most held results confirmed).
10. Scale to waves of 250 per month. Leadership readout: Gate pass rates, coaching load, early attrition vs last year's cohort.

## GitHub workflow

- `main` protected; feature branches; pull request with one reviewer.
- CI (`.github/workflows/ci.yml`) spins up Postgres, applies migrations and seeds, and runs `supabase/tests/gating_test.sql` on every PR, so a change can never silently break the gates.
- Content changes (markdown, question bank) go through the same PR flow, reviewed by L&D and Compliance.

## Low-code choices, honestly compared

| Option | Good for | Watch-outs |
|---|---|---|
| `web/` HTML + supabase-js (this repo) | Full control, free, fast to demo | Needs basic JS |
| Appsmith / Budibase (self-hosted) | HR and mentor admin screens in days | Trainee UX less polished |
| FlutterFlow | Native mobile app for trainees | Paid; export code for bank review |
| Retool | Fast internal tools | Cloud data residency; licence cost at 1,045 users |

All options read the same Supabase database, so the rules stay in one place.
