// Local/demo only: create Supabase Auth users for every seeded person whose login HR has
// issued (account_status = 'active'), all with the same demo password.
// NEVER run against production. Real logins are created by HR in the app
// (hr-provision-user Edge Function), which issues a random temporary password each time.
//
// Usage: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... DEMO_PASSWORD='Academy@2026' node scripts/create_demo_logins.mjs
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.DEMO_PASSWORD ?? "Academy@2026";
if (!url || !key) throw new Error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY");
if (/supabase\.co/.test(url) && process.env.I_UNDERSTAND_THIS_IS_A_DEMO !== "yes") {
  throw new Error("This looks like a hosted project. Set I_UNDERSTAND_THIS_IS_A_DEMO=yes only for a demo project.");
}
const admin = createClient(url, key);
const { data: people, error } = await admin.from("profiles")
  .select("id, email, role, login_id").eq("account_status", "active").is("user_id", null);
if (error) throw error;
let ok = 0;
for (const p of people) {
  const { error: e } = await admin.auth.admin.createUser({
    email: p.email, password, email_confirm: true, app_metadata: { role: p.role, login_id: p.login_id },
  });
  if (e) console.log(p.login_id, e.message); else ok++;
}
console.log(`created ${ok} of ${people.length} demo logins (password: ${password})`);
