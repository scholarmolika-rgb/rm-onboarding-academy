// hr-provision-user — the ONLY way an account is created. Called from the HR interface.
// POST { action: "create" | "reset" | "disable" | "enable", profile_ids: string[] }   (HR user's JWT)
// → { results: [{ profile_id, login_id, temp_password?, ok, error? }] }
// Temporary passwords are returned once to the HR screen and never stored in plain text.
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*",
               "Access-Control-Allow-Headers": "authorization, content-type, apikey" };

function tempPassword(): string {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const b = crypto.getRandomValues(new Uint32Array(10));
  const core = Array.from(b, (x) => a[x % a.length]).join("");
  return `Rm-${core.slice(0, 4)}-${core.slice(4)}`;   // e.g. Rm-7kQ2-x9mPwa
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  // who is calling? must be HR
  const caller = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: me } = await caller.rpc("me");
  const { data: role } = await caller.rpc("my_role");
  if (!me || !["hr", "admin"].includes(role)) {
    return Response.json({ error: "Only HR can create or change logins" }, { status: 403, headers: cors });
  }

  const { action, profile_ids } = await req.json();
  const results = [];
  for (const id of (profile_ids ?? []).slice(0, 500)) {
    try {
      const { data: p, error } = await admin.from("profiles")
        .select("id, email, full_name, role, employee_code, user_id, account_status").eq("id", id).single();
      if (error || !p) throw new Error("Person not found");
      if (!["trainee", "mentor", "reporting_manager", "hr"].includes(p.role)) throw new Error("This role cannot sign in");

      if (action === "create") {
        if (p.user_id) throw new Error("Login already exists; use reset");
        const pw = tempPassword();
        // 1. mark the login as issued by HR (the auth trigger refuses accounts without this)
        const { error: e1 } = await admin.rpc("apply_login_change", { p_profile: id, p_action: "create", p_actor: me });
        if (e1) throw e1;
        // 2. create the auth user; the trigger links it to the profile
        const { error: e } = await admin.auth.admin.createUser({
          email: p.email, password: pw, email_confirm: true,
          app_metadata: { role: p.role, login_id: p.employee_code },
        });
        if (e) {
          await admin.rpc("apply_login_change", { p_profile: id, p_action: "revert", p_actor: me });
          throw e;
        }
        results.push({ profile_id: id, login_id: p.employee_code, temp_password: pw, ok: true });
      } else if (action === "reset") {
        if (!p.user_id) throw new Error("No login yet; use create");
        const pw = tempPassword();
        const { error: e } = await admin.auth.admin.updateUserById(p.user_id, { password: pw, ban_duration: "none" });
        if (e) throw e;
        await admin.rpc("apply_login_change", { p_profile: id, p_action: "reset", p_actor: me });
        results.push({ profile_id: id, login_id: p.employee_code, temp_password: pw, ok: true });
      } else if (action === "disable" || action === "enable") {
        if (!p.user_id) throw new Error("No login yet");
        const { error: e } = await admin.auth.admin.updateUserById(p.user_id,
          { ban_duration: action === "disable" ? "876000h" : "none" });  // banned users cannot sign in or refresh a session
        if (e) throw e;
        await admin.rpc("apply_login_change", { p_profile: id, p_action: action, p_actor: me });
        results.push({ profile_id: id, login_id: p.employee_code, ok: true });
      } else throw new Error("Unknown action");
    } catch (err) {
      results.push({ profile_id: id, ok: false, error: String((err as Error).message ?? err) });
    }
  }
  return Response.json({ results }, { headers: cors });
});
