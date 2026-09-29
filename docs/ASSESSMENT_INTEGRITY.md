# Assessment integrity — keeping AI and answer-sharing out of the tests

Trainees are **encouraged** to learn with AI: the Academy Assistant explains topics and works through calculations 24×7. The three gate tests are different. They certify that the **person** can handle KYC, pricing and client conversations alone, because that is what happens in a client meeting. A score earned with AI help puts an unready RM in front of clients, which is a conduct, credit and reputation risk for the bank, and it hides the learning gaps coaching is meant to fix.

No single control stops a determined person (a second phone on the desk is invisible to any browser). The platform therefore layers five controls, and **people make every final decision**.

## 1. Question design — make AI help useless or slow
| Control | How | Where |
|---|---|---|
| Personalised numbers | Calculation questions exist as families of 5–7 variants with different figures; each attempt gets one random variant. Shared or pre-computed answers don't match. | `scripts/build_question_seed.py`, `questions.family` |
| Bank-specific scenarios | Questions reference the bank's own policies, delegation matrix and products, which public AI tools do not know. **Action for L&D:** convert at least 40% of the bank into such items. | `content/assessments/question-bank.json` |
| Large, rotating bank | Aim for 3× `question_count` per gate; retire items that leak (item analysis after each wave). | Quarterly review |
| Explain-your-answer | The Day-30 viva and every verification viva ask the trainee to explain answers aloud. | `vivas` table |

## 2. Delivery — the server is in charge
- **One question at a time** (`serve_question`), **75–90 s each**, **no going back**; the clock is the server's, so changing the device time or refreshing does not add time.
- **Options shuffled per trainee**; the answer key never leaves the database (`attempt_answers.option_order` maps display position → original).
- **One session per attempt** (`session_token`); a second tab or device is refused and logged.
- **Honour declaration** before the first question (`accept_declaration`).
- **Sitting windows** (`assessment_windows`): gates open only in scheduled slots, either at a supervised test room in the branch/regional office or remote-proctored.

## 3. Environment
- **Academy Assistant is paused** for anyone with an open attempt (`has_open_attempt()` in the chatbot); trying to use it is logged.
- The question bank is **never indexed** into the assistant's knowledge base.
- **Bank devices:** run gates in **Safe Exam Browser** (open source) or the bank's managed kiosk browser via MDM (Intune), which blocks other apps, copy/paste and screen sharing. Allow-list only the Academy URL.
- **Network:** during gate windows, block known public AI endpoints on the test-room network (proxy category "Generative AI").
- **Supervised re-sits:** anyone whose result is voided can only re-sit in a supervised room (`journeys.supervised_only`).
- **Optional remote proctoring** (webcam) only with explicit consent under the DPDP Act 2023, a documented purpose and short retention; prefer in-person rooms.

## 4. Signals — recorded, weighted, never a verdict
`compute_integrity()` builds a 0–100 score from:

| Signal | Weight |
|---|---|
| Left the test screen (first time forgiven) | 15 each, max 45 |
| Copy / paste | 30 |
| Exited full screen | 15 each, max 30 |
| IP change, second session, dev-tools | 25 |
| Tried to use the assistant during the test | 20 |
| ≥ 2 calculation answers correct in under 8 s | 10 each, max 30 |
| ≥ 4 long pauses followed by correct answers | 15 |
| ≥ 3 identical **wrong** answers with a cohort peer | 25 |

Trainees are told the rules and see their own recorded activity during the test. The weights are starting values: calibrate them after the pilot wave.

## 5. People decide
- **Fail + signals:** normal coaching route; the flags are included in the coaching email so coaches can probe.
- **Pass + integrity score ≥ 40:** the result is **held** (`review_state = 'review'`). The mentor (HR in copy) holds a **20-minute verification viva** within 2 working days: the trainee explains 3–4 of their answers in their own words.
  - **Confirm** → result stands, next phase unlocks.
  - **Void** → result removed, **supervised re-sit** that does not use one of the two attempts, HR **conduct review** under the code of conduct.
- **Day 30:** the mentor cannot sign off without a certification viva score of 3/5 or more (`sign_off` enforces it).
- **Appeal:** a trainee may ask HR for a second viva with another mentor; HR's decision is final.

## What this cannot catch, and what covers it
| Gap | Covered by |
|---|---|
| A second phone or another person in a remote setting | Supervised rooms for gates; personalised numbers; viva |
| Memorised leaked questions | Rotating bank, variants, item analysis |
| Someone who is simply lucky | Shadow ratings (Days 22–29) and the Day-30 viva test real understanding |

## Operating metrics (HR dashboard)
Held results %, confirmed vs voided, time to verification, signal frequency by cluster (a spike can mean a leaked paper), and first-attempt pass rate before/after controls.
