# People model — personas and assignment rules

## Personas

| Role | Count | Experience | Department | Load limit |
|---|---|---|---|---|
| **New Joinee** (RM trainee) | up to 1,000 per cohort | **more than 3 and less than 5 years** (3y 1m – 4y 11m) | the RM business line they join after Day 30 | — |
| **Reporting Boss** | **20** (4 per department) | **10 to under 15 years** (10y 0m – 14y 11m) | same as their joinees | 50 joinees |
| **Mentor** | 20 (4 per department) | senior RM / product / credit partner, 12+ years | **always different** from their joinees | 50 joinees |
| **HR partner** | 5 (one per region) | — | all departments | 200 joinees |

Departments a joinee can join: Large Corporate Banking (LCB), Mid-Corporate Banking (MCB), Emerging Corporates / SME (ECB), Transaction Banking (TXB), Trade & Supply Chain Finance (TSF). Regions: North, South, East, West, Central.

## Why the mentor comes from another department
- **Independent assessment:** the mentor rates shadow logs, runs the verification and Day-30 vivas. Someone outside the joinee's future team has no stake in passing or failing them.
- **Wider view of the bank:** a Mid-Corporate joinee mentored by a Trade Finance or Transaction Banking specialist learns how the other product lines serve the same client.
- **Product depth still comes from the Reporting Boss**, who is in the joinee's own department and gives the coaching day on product and pricing.

## How a joinee is assigned (`create_joinee_internal`)
1. Validate: name, unique work email, department, region, experience 37–59 months, free seat in the cohort.
2. **Reporting Boss:** same department, below 50 joinees, same region first, then lowest load.
3. **Mentor:** any other department, below 50 joinees, same region first (in-person shadowing on Days 22–29), then lowest load.
4. **HR partner:** the joinee's region.
5. Welcome email to the joinee; assignment email to boss and mentor (HR in copy); audit-log entry.

HR can override the boss (same department only) or the mentor (other departments only); the database trigger `trg_assignment_rules` rejects anything else, including direct inserts.

## Capacity
- A cohort has **1,000 seats**. It starts with a demo intake of 24 so HR can test by adding joinees in the app or with `hr_create_joinee()` / `hr_create_joinees()` (bulk / CSV).
- Each department has 4 bosses × 50 = **200 joinees at most**. If hiring is uneven (for example 300 into Mid-Corporate), raise those bosses' `max_trainees` or add bosses before the cohort starts.
- Mentors outside a department: 16 × 50 = 800 places, so mentor capacity is never the constraint at a balanced intake.
- Four monthly waves of 250 keep shadowing to about 12 joinees per mentor at a time.

## Adding Reporting Bosses and Mentors
HR adds them in People & capacity (`hr_add_staff`): bosses need 10 to under 15 years and the programme allows 20 active; mentors need 12+ years. A boss or mentor can be deactivated only when no joinees are assigned to them. Everyone HR adds gets a login only when HR issues it (see `ACCESS_AND_LOGINS.md`).

## HR screens
- **New joinees:** add one joinee with a live assignment preview; paste or upload a CSV (`full_name, email, department, region, experience_months, previous_employer, previous_role, start_date`); roster with search and department filter; withdraw before Day 1 when an offer is declined (frees the seat).
- **People & capacity:** every boss, mentor and HR partner with experience, region and load.

## Production notes
- Feed joinees from the HRMS/ATS (for example a nightly file or API) into `hr_create_joinees`; the per-row report goes back to the recruiter.
- Mentor and boss records come from the HR master; keep `department`, `region`, `experience_months` and `max_trainees` current there.
