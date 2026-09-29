// notify-dispatch — drains notification_outbox and sends emails.
// Triggered every 2 minutes by pg_cron. Provider: Resend (swap for Microsoft Graph /
// bank SMTP relay in production — only sendEmail() changes).
import { createClient } from "npm:@supabase/supabase-js@2";
import { templates } from "../_shared/templates.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const FROM = Deno.env.get("MAIL_FROM") ?? "RM Academy <academy@bank.example>";
const DRY_RUN = Deno.env.get("MAIL_DRY_RUN") === "true";   // log instead of send in dev

async function sendEmail(to: string[], cc: string[], subject: string, html: string) {
  if (DRY_RUN) { console.log("[dry-run]", to, subject); return; }
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to, cc: cc.length ? cc : undefined, subject, html }),
  });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
}

Deno.serve(async (req) => {
  if (req.headers.get("Authorization") !== `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`) {
    return new Response("forbidden", { status: 403 });
  }
  const { data: rows, error } = await sb.from("notification_outbox")
    .select("*").eq("status", "pending").lt("tries", 5).order("created_at").limit(50);
  if (error) return new Response(error.message, { status: 500 });

  let sent = 0, failed = 0;
  for (const row of rows ?? []) {
    const tpl = templates[row.template];
    try {
      if (!tpl) throw new Error(`unknown template ${row.template}`);
      const { subject, html } = tpl(row.payload);
      await sendEmail(row.to_emails, row.cc_emails ?? [], subject, html);
      await sb.from("notification_outbox").update({ status: "sent", sent_at: new Date().toISOString(),
        tries: row.tries + 1 }).eq("id", row.id);
      sent++;
    } catch (e) {
      await sb.from("notification_outbox").update({
        status: row.tries + 1 >= 5 ? "failed" : "pending", tries: row.tries + 1, last_error: String(e),
      }).eq("id", row.id);
      failed++;
    }
  }
  return Response.json({ sent, failed });
});
