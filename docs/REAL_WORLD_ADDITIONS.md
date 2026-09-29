# What was added beyond the original brief

Each item below closes a gap a real bank would hit in the first pilot.

## Programme design
| Gap | Addition |
|---|---|
| Unlimited retries could loop forever | Two attempts per gate; a second miss goes to an **HR performance review** (extend, change role, or exit). |
| Coaches may not act | **3-working-day SLA** on coaching decisions; nightly job flags breaches and emails HR + reporting manager. |
| "Repeat" is vague | Coaches tick **specific modules**; if none ticked, modules scoring < 70% are assigned automatically. |
| Three coaches may disagree | Rule written down: **any one "repeat" → repeat** (conservative for a regulated role). Change in `record_coaching` if the bank prefers majority vote. |
| Day 30 had no pass mark | Final assessment set at **80%**, plus **tri-party sign-off**; any rejection → HR review. |
| Tests before study | A gate opens only when all **mandatory items** of that phase are complete. |
| Calendar days ≠ training days | Training days **skip weekends and bank holidays** (per cohort). |
| Knowledge fades after Day 30 | **60/90-day check-ins** and pulse surveys continue the attrition signal. |

## Capacity (important at 1,000 : 20 : 20 : 5)
- One mentor per 50 trainees cannot shadow 50 people on Days 22–29. **Run four monthly waves of 250** (≈12 trainees per mentor per wave) or add senior RMs as shadow buddies.
- If ~20% miss Gate 1 in a single 1,000 cohort, each HR partner owes ~40 coaching days in a week. HR can **delegate its coaching day to a trained L&D coach**, keeping HR's decision.

## Risk, compliance and data
- **No customer PII** in shadow logs (masked reference only); the assistant redacts PAN, Aadhaar, account numbers and IFSC before any model call.
- **Row-level security**: trainees see only themselves; mentors/managers their own trainees; pulse (wellbeing) data visible to HR only.
- **Answer keys never reach the browser**; questions are randomised and graded in the database.
- **Append-only audit log** for scores, coaching decisions, unlocks and sign-offs.
- **System access** (maker-checker in core systems) requested only after Gate 2.
- **DPDP Act 2023**: purpose-limited processing of employee data; document a retention period.
- **Data residency**: Supabase on AWS Mumbai or self-hosted; LLM can be switched to an on-prem open model.
- **Regulatory content owner**: Compliance re-validates regulatory figures in the question bank each quarter against the latest RBI Master Directions.

## Assessment integrity (AI and answer sharing)
Full design in `ASSESSMENT_INTEGRITY.md`. In short: personalised calculation numbers per trainee; one question at a time on a server clock with no going back; assistant paused and question bank never indexed; behaviour signals build an integrity score; a held pass is verified by the mentor in a 20-minute viva; voided results mean a supervised re-sit and a conduct review; Day-30 sign-off requires a viva. Signals never fail anyone automatically.

## Engagement
- Supportive email to the trainee when coaching starts (no scores in subject lines).
- Inactivity nudges after 48 hours; attrition-risk score for HR.
- The assistant answers questions 24×7, so trainees are not blocked waiting for a busy mentor.
