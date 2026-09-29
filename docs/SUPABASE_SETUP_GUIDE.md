# Supabase setup: CSV upload and saving every UI change

This guide takes you from an empty Supabase project to a live Academy where every change made in the app (a joinee added, a login issued, a lesson completed, a coaching decision, a sign-off) is saved in Supabase. It has five parts:

1. Create the project and the tables
2. Upload the CSV files
3. Create the first logins
4. Link the app to Supabase (the state store)
5. Check that changes are being saved

Everything referred to below is in the GitHub repository `scholarmolika-rgb/rm-onboarding-academy`.

---

## Part 1 · Create the project and the tables

**Step 1. Create the Supabase project**
1. Go to supabase.com → **New project**.
2. Region: **Mumbai (ap-south-1)**, so data stays in India.
3. Set a strong database password and store it in your password manager.
4. When it is ready, open **Project Settings → API** and note three values: the **Project URL**, the **anon public key** and the **service_role key**. The service_role key is secret: never put it in the app or on GitHub.

**Step 2. Switch settings on and off**
1. **Authentication → Sign In / Providers → Email**: turn **off** "Allow new users to sign up". Only HR creates accounts.
2. **Database → Extensions**: turn on **vector**, **pg_cron** and **pg_net**.

**Step 3. Create the tables and rules (migrations)**

Run the eight files in `supabase/migrations/` **in number order**. Choose one way:

- **Low-code (SQL Editor):** open **SQL Editor → New query**, open `20260929000001_schema.sql` from the repository, copy all of it, paste, click **Run**. Repeat for `…02` through `…08`. Each should finish with "Success. No rows returned".
- **Command line (VS Code terminal):**
  ```bash
  supabase link --project-ref <your-project-ref>
  supabase db push
  ```

| File | What it creates |
|---|---|
| 01_schema | all tables |
| 02_gating_engine | tests, gates, coaching, sign-off rules |
| 03_rls_views_cron | who can see what, dashboard views |
| 04_chatbot_sla | chatbot search, coaching deadlines |
| 05_assessment_integrity | secure tests, result checks |
| 06_people_model | the 5 departments, personas, assignment rules, 1,000 seats |
| 07_logins | HR-issued logins, no self sign-up |
| 08_state_store | `ui_state` table, withdraw joinee, HR review decision, shadow ratings |

---

## Part 2 · Upload the CSV files

The files are in `supabase/csv/`. They were exported from a database built with these same migrations and re-imported into a fresh copy as a test, so the columns match exactly.

**Step 4. Upload in this order.** Each file depends on the ones before it (joinees point to their boss, mentor and HR partner, so those must exist first).

| # | File | Upload into table | Rows | Notes |
|---|---|---|---|---|
| 1 | `01_cohorts.csv` | `cohorts` | 1 | Cohort 2026-10, 1,000 seats, bank holidays |
| 2 | `02_phases.csv` | `phases` | 3 | the three phases of the 30 days |
| 3 | `03_modules.csv` | `modules` | 7 | Governance, People, Product, Process, Pricing, P&L, Shadowing |
| 4 | `04_learning_items.csv` | `learning_items` | 38 | the daily reading and working files |
| 5 | `05_assessments.csv` | `assessments` | 3 | Day 15 (80%), Day 21 (75%), Day 30 (80%) |
| 6 | `06_questions.csv` | `questions` | 98 | question bank incl. personalised calculation variants |
| 7 | `07_profiles_hr.csv` | `profiles` | 5 | HR partners, one per region |
| 8 | `08_profiles_reporting_bosses.csv` | `profiles` | 20 | 10 to under 15 years, 4 per department |
| 9 | `09_profiles_mentors.csv` | `profiles` | 20 | 12+ years, 4 per department |
| 10 | `10_profiles_joinees_demo.csv` | `profiles` | 24 | **optional** demo joinees; skip for a real cohort |

Do **not** upload `reference/departments.csv`; migration 06 already loaded the departments.

**How to upload one file (Table Editor):**
1. **Table Editor** → click the table name (e.g. `cohorts`).
2. **Insert → Import data from CSV** → choose the file.
3. Check the preview: the column names at the top must match the table's columns. Leave "First row is header" ticked.
4. Click **Import data**. Wait for the green confirmation before the next file.

**Step 5. Finish the import.** Open **SQL Editor**, paste all of `supabase/csv/after_import.sql`, click **Run**. It:
- moves the numbering counters past the imported IDs, so new questions and items get new numbers;
- makes sure every joinee has a journey record;
- runs checks. Every result should read **ok**, and the last line shows seats used and free (24 and 976 with the demo joinees).

**Command-line alternative for Steps 4–5** (one command, all files, stops on the first error):
```bash
psql "<your database connection string>" -f supabase/csv/import_all.sql
```
Find the connection string under **Project Settings → Database → Connection string (URI)**.

**If an upload fails**

| Message | Cause | Fix |
|---|---|---|
| `duplicate key value` | file already uploaded | skip it, or delete those rows first |
| `violates foreign key constraint` | uploaded out of order | upload the earlier file first, then retry |
| `violates check constraint "persona_experience"` | experience outside the persona | joinees 37–59 months, bosses 120–179 months |
| `violates check constraint "mentor_experience"` | mentor under 12 years | experience_months 144 or more |
| `Reporting Boss must be from the joinee's department` | wrong manager_id | pick a boss from the same department |
| `Mentor must come from a different department` | wrong mentor_id | pick a mentor from another department |
| `Cohort is full` | more than 1,000 joinees | raise `cohorts.capacity` or open a new cohort |
| `invalid input value for enum` | typo in `role` or `kind` | roles: trainee, mentor, reporting_manager, hr |

**Adding your real people later**
- **Joinees:** do **not** edit the profiles CSV. Use the HR screen **New joinees → Add many at once** with `supabase/csv/templates/joinees_bulk_template.csv`. It assigns boss, mentor and HR partner automatically and gives a per-row report. Columns: `full_name, email, department (LCB|MCB|ECB|TXB|TSF), region (North|South|East|West|Central), experience_months, previous_employer, previous_role, start_date`.
- **Reporting Bosses and Mentors:** use **People & capacity → Add a Reporting Boss or Mentor**, or bulk with `templates/staff_template.csv` through the `hr_add_staff` function (see the SQL below).
- If you must upload your own profiles CSV: leave the `id` column empty (Supabase creates it), upload HR and staff first, then copy their `id` values from the Table Editor into the joinees' `hr_id`, `manager_id` and `mentor_id` columns.

```sql
-- bulk-add staff from the template, run as an HR user from the app, or as admin in the SQL Editor:
select hr_add_staff(jsonb_build_object('role','mentor','full_name','Leena Paul','email','leena.paul@bank.example',
  'department','LCB','region','East','experience_months',192,'designation','Senior Relationship Manager'));
```

---

## Part 3 · Create the first logins

**Step 6. Deploy the server functions** (VS Code terminal):
```bash
supabase functions deploy hr-provision-user chatbot notify-dispatch daily-scheduler
supabase secrets set --env-file supabase/functions/.env     # copy .env.example first and fill it
```

**Step 7. Create the HR partners' logins** (the only logins not created by HR):
1. SQL Editor, run:
   ```sql
   update profiles set login_id = employee_code, account_status = 'active', must_change_password = true
   where role = 'hr';
   ```
2. **Authentication → Users → Add user → Create new user**, for each HR email (`hr1@…` to `hr5@…` or your real addresses): enter a temporary password and tick **Auto confirm user**. The database links each account to the HR profile automatically.
3. Give each HR partner their login ID (`HR001`…`HR005`) and temporary password in person. They set their own password at first sign-in.

**Step 8. HR creates everyone else's login** in the app: **Logins & access → Create login** (or "Create logins for N without one"). The temporary passwords appear once on screen.

*Demo project only:* to give every seeded person the same demo password, run the SQL from Step 7 without the `where` line, then `node scripts/create_demo_logins.mjs`. Never do this in production.

---

## Part 4 · Link the app to Supabase (the state store)

Today the app (`web/index.html`) runs on demo data held in the browser, and everything resets when the page reloads. To save every change in Supabase, the app's actions call the **state store** (`web/store.js`), which calls Supabase through `web/supabase-client.js`.

Where each kind of change is saved:
- **Business data** goes to its own table through the database functions. The rules (personas, gates, coaching, logins) are enforced there, so the app cannot bypass them.
- **Screen state** goes to the `ui_state` table: one private record per person per key (last page, open training day, roster filters, unsent drafts). Nobody else can read another person's screen state.

**Step 9. Connect the app to your project**
1. Open `web/supabase-client.js`. Replace `<project-ref>` and `<anon-key>` with your Project URL and **anon** key. Never use the service_role key here.
2. In `web/src/app.template.html`, just before the main `<script>`, add:
   ```html
   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
   <script type="module">
     import { api } from "./supabase-client.js";
     import { createStore } from "./store.js";
     window.store = createStore(api);
   </script>
   ```

**Step 10. Point each UI action at the store.** In `app.template.html`, find each handler below and replace the in-memory change with the store call. Then re-read the data and call `render()`.

| UI action (screen) | Handler in app.template.html | Store method | Saved in |
|---|---|---|---|
| Sign in | `signIn()` | `store.signIn(id, pw)` | Supabase Auth, `profiles.last_sign_in_at` |
| Set own password | submit of `#pwForm` | `store.changePassword(pw)` | Auth, `profiles.must_change_password` |
| **HR** add joinee | `case 'jfAdd'` | `store.addJoinee(row)` | `profiles`, `journeys`, `notification_outbox`, `audit_log` |
| **HR** import CSV | `importCSV()` | `store.addJoinees(rows)` | same, per row |
| **HR** withdraw joinee | `data-withdraw` | `store.withdrawJoinee(id, reason)` | `profiles`, `journeys`, `audit_log` |
| **HR** add boss / mentor | `case 'sfAdd'` | `store.addStaff(row)` | `profiles`, `audit_log` |
| **HR** deactivate staff | `data-deact` | `store.setStaffActive(id, false)` | `profiles` |
| **HR** create / reset / disable / enable login | `issueLogin()`, `accAction()` | `store.provision(action, ids)` | Auth, `profiles`, `audit_log` |
| **HR** extend or exit after two attempts | `data-hrextend`, `data-hrexit` | `store.decideReview(id, 'extend'\|'exit', notes)` | `journeys`, `audit_log` |
| Joinee mark item complete | `data-done` | `store.markComplete("6-1")` | `progress` |
| Joinee assessment | `beginSecure()`, `saveAnswer()`, `rec()`, `finishSecure()` | `startAttempt`, `acceptDeclaration`, `nextQuestion`, `answer`, `logTestEvent`, `submitAttempt` | `attempts`, `attempt_answers`, `attempt_events` |
| Joinee refresher done | `case 'finishRem'` | `store.finishRefresher(assignmentId)` | `remediation_assignments`, `journeys` |
| Joinee pulse survey | `case 'pulseSend'` | `store.sendPulse(row)` | `pulse_surveys` |
| Joinee shadow log | `case 'shSave'` | `store.addShadowLog(row)` | `shadow_logs` |
| Coach pass / repeat | `decide()` | `store.decideCoaching(sessionId, d, notes, moduleIds)` | `coaching_sessions`, `remediation_assignments` |
| Mentor confirm / void held result | `data-confirm`, `data-void` | `store.verifyResult(attemptId, outcome, score, notes)` | `integrity_reviews`, `vivas` |
| Mentor rate shadow log | `rateShadow()` | `store.rateShadowLog(logId, ratings, feedback)` | `shadow_logs` |
| Mentor Day-30 viva | `saveViva` | `store.recordViva(id, 'FINAL', score, notes)` | `vivas` |
| Day-30 sign-off | `data-signyes` / `signNo` | `store.signOff(id, approved, comments)` | `signoffs`, `journeys` |
| Chatbot question | `ask()` | `store.ask(message)` | `chat_messages` |
| Page, day, filters, drafts | `render()`, roster and form `change` handlers | `store.saveUi(key, value)` | `ui_state` |

Example, HR adding a joinee:
```js
case 'jfAdd': {
  try {
    const r = await store.addJoinee({ full_name: jf.name, email: jf.email, department: jf.dept, region: jf.region,
      experience_months: jfExp(), previous_employer: jf.prevEmp, previous_role: jf.prevRole, start_date: jf.start,
      manager_id: jf.boss || null, mentor_id: jf.mentor || null });
    if ($('#jf_login').checked) await store.provision('create', [r.id]);
    toast(`${jf.name} added as ${r.employee_code}.`);
    await reloadPeople();          // re-read seats, roster and coach load from Supabase
    render();
  } catch (e) { toast(e.message); }   // the database's own message, e.g. the persona rule
  return;
}
```

Example, saving screen state:
```js
// after changing the roster filter
store.saveUi('hr.roster', { q: rosterQ, dept: rosterDept });
// after sign-in, restore it
({ q: rosterQ, dept: rosterDept } = store.uiState('hr.roster', { q: '', dept: '' }));
```

**Step 11. Replace the demo data with reads.** After sign-in, load what the screen shows instead of the built-in demo arrays:
- Joinee: `store.myStatus()` and `store.progressKeys()`.
- Coaches: `store.coachingQueue()` and `store.integrityReviews()`.
- HR: `store.seats()`, `store.coachLoad()`, `store.trainees()`, `store.logins()`, `store.kpis()`.

**Step 12. Keep open screens up to date.** In the **Table Editor**, open each of these tables and switch **Realtime** on (or add them to the `supabase_realtime` publication under **Database → Publications**): `profiles`, `journeys`, `coaching_sessions`, `signoffs`, `shadow_logs` and `progress`. Then call `store.live(() => { reloadForMyRole(); render(); })` once after sign-in. When HR adds a joinee, that joinee's boss and mentor see them without refreshing.

**Step 13. Rebuild and publish**
1. Remove the demo-accounts panel from the front page (search for `lp-demo` in `app.template.html`).
2. Run `python3 scripts/build_prototype.py`.
3. Open `web/index.html` with VS Code's Live Server and test Part 5.
4. Commit and push; host `web/` on GitHub Pages, Netlify or the bank's web server.

---

## Part 5 · Check that changes are being saved

Do each action in the app, then run the matching query in the SQL Editor (or look in the Table Editor):

| Do this in the app | Then check |
|---|---|
| HR adds a joinee | `select employee_code, full_name, department, manager_id, mentor_id from profiles order by created_at desc limit 1;` |
| HR creates a login | `select login_id, account_status, must_change_password from profiles where login_id = 'TRN0025';` |
| Joinee sets password and signs in | same query: `must_change_password` is now `false` |
| Joinee marks a lesson complete | `select * from progress order by completed_at desc limit 5;` |
| Joinee takes a test | `select attempt_no, score_pct, passed, integrity_score, review_state from attempts order by started_at desc limit 3;` |
| Coach records a decision | `select coach_role, decision, left(notes,40) from coaching_sessions order by completed_at desc limit 3;` |
| Anyone changes page or filters | `select key, value, updated_at from ui_state order by updated_at desc limit 5;` |
| Any change at all | `select at, action, entity, detail from audit_log order by at desc limit 10;` |
| Emails queued | `select template, to_emails, status from notification_outbox order by created_at desc limit 5;` |

If a query shows nothing after an action, that handler is still using demo data: go back to Step 10 for that row.

---

## What has been tested, and what you need to test
- **Tested here:** the migrations; the CSV files (imported into a fresh database in this order, all checks ok, then HR login, adding a joinee and new question numbering worked); the database rules for every action in the Step 10 table (six automated test suites, which also run on GitHub for every push); the state store's mapping and error handling (against a stand-in for Supabase).
- **Test on your project:** Steps 9–13 against your live Supabase URL, because this environment cannot reach your project. Work through Part 5 once per role.
