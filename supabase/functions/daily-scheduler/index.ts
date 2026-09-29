// daily-scheduler — runs nightly (01:00 IST) via pg_cron.
// 1. Recompute attrition-risk scores
// 2. Flag coaching SLA breaches → email HR + reporting manager
// 3. Nudge trainees inactive for 2+ days
// (Extend here: pulse-survey reminders on training days 7, 15, 25; 60/90-day check-ins)
import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  if (req.headers.get("Authorization") !== `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`) {
    return new Response("forbidden", { status: 403 });
  }
  const out: Record<string, number> = {};

  await sb.rpc("refresh_risk_scores");

  const { data: breaches } = await sb.rpc("flag_sla_breaches");
  for (const b of breaches ?? []) {
    await sb.rpc("enqueue_email", {
      p_to: [b.hr_email, b.manager_email].filter(Boolean),
      p_cc: b.pending_coaches,
      p_template: "sla_breach",
      p_payload: { trainee: b.trainee, pending: b.pending_coaches },
    });
  }
  out.sla_breaches = breaches?.length ?? 0;

  // Inactive trainees: no completed item in 48h while status is active
  const since = new Date(Date.now() - 48 * 3600e3).toISOString();
  const { data: active } = await sb.from("v_trainee_status")
    .select("id, full_name, status, training_day").eq("status", "active");
  let nudged = 0;
  for (const t of active ?? []) {
    const { count } = await sb.from("progress").select("*", { count: "exact", head: true })
      .eq("trainee_id", t.id).gte("completed_at", since);
    if ((count ?? 0) === 0 && t.training_day > 1) {
      const { data: p } = await sb.from("profiles").select("email").eq("id", t.id).single();
      await sb.rpc("enqueue_email", { p_to: [p!.email], p_template: "inactivity_nudge",
        p_payload: { trainee: t.full_name, open_items: "a few" } });
      nudged++;
    }
  }
  out.nudged = nudged;
  return Response.json(out);
});
