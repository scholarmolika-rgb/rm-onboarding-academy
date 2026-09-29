# Access and logins

## Rules
- The app opens on the **Academy front page** with a sign-in box. There is **no self-registration**.
- **Only HR** can add people (New Joinees, Reporting Bosses, Mentors) and create their logins. HR partners' own logins are created by the platform administrator.
- **Login ID = employee code**: `TRN0025` (joinee), `RB005` (Reporting Boss), `MN012` (Mentor), `HR001` (HR). Not case-sensitive.
- HR issues a **temporary password**, shown once on the HR screen. HR shares it through a secure channel (in person or the bank's secure messaging), never by ordinary email. The platform emails only the login ID.
- At **first sign-in** the person must set their own password: at least 10 characters with letters and numbers, different from the temporary one.
- A wrong ID and a wrong password get the same message, so login IDs cannot be guessed. In the prototype, **5 wrong attempts lock** the login until HR resets it; in Supabase, Auth's built-in rate limits apply (see Production hardening to add the same lock).
- HR can **reset**, **disable** and **enable** any login. A Reporting Boss or Mentor can be **deactivated** only after their joinees are reassigned; deactivation disables their login.
- Sessions end after **15 minutes** without activity.
- Each person sees only their own interface: joinees their journey, bosses and mentors only the joinees assigned to them, HR everything.

## Who can add whom

| Added by HR | Rule checked when adding |
|---|---|
| New Joinee | more than 3 and less than 5 years' experience; department they join after Day 30; free seat (1,000 per cohort) |
| Reporting Boss | 10 to under 15 years' experience; at most 20 active in the programme |
| Mentor | at least 12 years' experience; always mentors joinees from other departments |

## How it works in Supabase
1. HR adds the person (`hr_create_joinee` or `hr_add_staff`).
2. HR clicks **Create login**. The app calls the `hr-provision-user` Edge Function with HR's session. The function:
   - checks the caller is HR;
   - marks the login as issued (`apply_login_change 'create'`);
   - creates the Supabase Auth user with a random temporary password (service role, never in the browser);
   - returns the temporary password once.
3. The database trigger on `auth.users` **refuses any account** whose email does not belong to an HR-added person with an issued login, even if sign-up were switched on by mistake. Also switch sign-up **off** in Authentication settings.
4. Sign-in: login ID → `resolve_login` → email → `signInWithPassword`. If `must_change_password` is true the app shows the change-password screen, then calls `password_changed()`.
5. Disable = the Edge Function bans the auth user, so they cannot sign in or refresh a session. Reset = new temporary password and forced change.
6. Every create, reset, disable, enable and staff change is written to `audit_log`.

## Demo accounts (prototype and local testing only)
The front page lists four demo accounts (one per interface) so the prototype can be explored. For a local Supabase, `scripts/create_demo_logins.mjs` creates auth users with a shared demo password; it refuses to run against a hosted project unless explicitly told it is a demo. **Remove the demo panel and never run the script in production.**

## Production hardening
- Put the sign-in page behind the bank's network or SSO gateway; optionally replace passwords with Azure AD / Okta SSO and keep HR-issued access as the authorisation step.
- Turn on MFA (TOTP) for HR accounts.
- Supabase Auth's built-in rate limits slow brute-force attempts. If the bank's policy requires a hard lock after 5 failures, route sign-in through a small Edge Function that counts failures per login ID and bans the auth user, as the prototype does.
- Review `audit_log` for `login_*` events monthly.
