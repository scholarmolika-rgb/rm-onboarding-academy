// Shared email templates — plain, professional, mobile-friendly.
// Keep scores out of subject lines (privacy on lock screens).

const shell = (title: string, body: string) => `
<div style="font-family:Inter,Segoe UI,Arial,sans-serif;background:#F6F7F9;padding:24px">
  <div style="max-width:560px;margin:auto;background:#fff;border:1px solid #E3E6EB;border-radius:8px">
    <div style="padding:16px 24px;border-bottom:1px solid #E3E6EB;font-weight:600;color:#12263F">
      RM Onboarding Academy</div>
    <div style="padding:24px;color:#1F2933;font-size:14px;line-height:1.6">
      <h2 style="margin:0 0 12px;font-size:18px;color:#12263F">${title}</h2>${body}</div>
    <div style="padding:12px 24px;border-top:1px solid #E3E6EB;font-size:12px;color:#6B7280">
      Internal — confidential. Automated message from the onboarding platform.</div>
  </div></div>`;

const btn = (href: string, label: string) =>
  `<p><a href="${href}" style="display:inline-block;background:#1F3A5F;color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">${label}</a></p>`;

type P = Record<string, any>;
const APP = Deno.env.get("APP_URL") ?? "https://rm-academy.example";

export const templates: Record<string, (p: P) => { subject: string; html: string }> = {
  gate_failed_coaching_required: (p) => ({
    subject: `Action required: 1-day coaching for ${p.trainee} (${p.employee_code})`,
    html: shell("Coaching required", `
      <p><b>${p.trainee}</b> (${p.employee_code}, ${p.branch ?? ""}) scored <b>${p.score}%</b>
      on the <b>${p.assessment}</b> against a pass mark of ${p.pass_pct}%.</p>
      <p>Each of you is asked to hold a one-day, one-on-one coaching session and record
      your decision — <b>Pass</b> or <b>Repeat modules</b> — by
      <b>${new Date(p.sla_due).toLocaleDateString("en-IN")}</b>.</p>
      <p>Module scores: ${Object.entries(p.module_scores ?? {}).map(([k, v]) => `${k} ${v}%`).join(" · ")}</p>
      ${btn(`${APP}/coaching/${p.escalation_id}`, "Open coaching workspace")}`),
  }),
  trainee_coaching_scheduled: (p) => ({
    subject: "Your personalised coaching sessions are scheduled",
    html: shell(`Hi ${p.trainee},`, `
      <p>Thank you for completing the <b>${p.assessment}</b>. Your mentor, reporting manager
      and HR partner will each spend a day with you to strengthen a few areas before you move on.
      This is a normal part of the programme.</p>${btn(`${APP}/journey`, "View my plan")}`),
  }),
  remediation_assigned: (p) => ({
    subject: "Refresher modules assigned",
    html: shell(`Hi ${p.trainee},`, `<p>Your coaches recommend revisiting:</p>
      <ul>${(p.modules ?? []).map((m: string) => `<li>${m}</li>`).join("")}</ul>
      <p>Once complete, your re-assessment will unlock.</p>${btn(`${APP}/journey`, "Start refresher")}`),
  }),
  phase_unlocked: (p) => ({
    subject: "Next phase unlocked",
    html: shell(`Well done, ${p.trainee}`, `<p>You have cleared the <b>${p.assessment}</b>
      ${p.via === "coach_pass" ? "on your coaches' recommendation" : ""}. Your next phase is now open.</p>
      ${btn(`${APP}/journey`, "Continue")}`),
  }),
  hr_review_required: (p) => ({
    subject: `HR review: ${p.trainee} (${p.employee_code}) exhausted attempts`,
    html: shell("Performance review required", `<p>${p.trainee} has not cleared the
      <b>${p.assessment}</b> after ${p.attempts} attempts (latest ${p.score}%).
      Please convene a review to decide extension, role change or exit.</p>
      ${btn(`${APP}/hr/reviews`, "Open review")}`),
  }),
  final_signoff_request: (p) => ({
    subject: `Sign-off needed: ${p.trainee} passed Day 30 certification`,
    html: shell("Final sign-off", `<p>${p.trainee} (${p.employee_code}) has passed the
      certification assessment. Mentor, Reporting Manager and HR each need to sign off.</p>
      ${btn(`${APP}/signoff`, "Review & sign")}`),
  }),
  certified: (p) => ({
    subject: `${p.trainee} is now a certified Relationship Manager`,
    html: shell("Certified", `<p>Congratulations ${p.trainee}. You are cleared for an
      independent portfolio. Your 60/90-day check-ins are scheduled.</p>`),
  }),
  sla_breach: (p) => ({
    subject: `Overdue coaching for ${p.trainee}`,
    html: shell("Coaching overdue", `<p>Coaching decisions for <b>${p.trainee}</b> are past SLA.
      Pending: ${(p.pending ?? []).join(", ")}.</p>${btn(`${APP}/hr/escalations`, "View escalations")}`),
  }),
  integrity_review_required: (p) => ({
    subject: `Verification needed: ${p.trainee} (${p.employee_code})`,
    html: shell("Please verify an assessment result", `<p><b>${p.trainee}</b> passed the
      <b>${p.assessment}</b>, but the attempt showed unusual activity:
      ${Object.entries(p.flags ?? {}).map(([k, v]) => `${k.replaceAll("_", " ")} (${v})`).join(", ")}.</p>
      <p>These signals are not proof of misconduct. Please hold a 20-minute viva: ask the trainee to
      explain 3–4 answers from the paper in their own words, then confirm or void the result within
      2 working days. The result stays on hold until you decide.</p>
      ${btn(`${APP}/integrity/${p.attempt_id}`, "Open verification")}`),
  }),
  result_under_review: (p) => ({
    subject: "Your assessment result is being confirmed",
    html: shell(`Hi ${p.trainee},`, `<p>Thank you for completing the <b>${p.assessment}</b>.
      Your mentor will have a short conversation with you about a few of your answers before the
      result is confirmed. This is a routine check.</p>`),
  }),
  attempt_voided: (p) => ({
    subject: `Assessment result voided: ${p.trainee} (${p.employee_code})`,
    html: shell("Result voided after verification", `<p>The mentor voided ${p.trainee}'s
      <b>${p.assessment}</b> result after a verification viva.</p><p>Notes: ${p.notes}</p>
      <p>The trainee will re-sit in a supervised centre. Please review under the code of conduct.</p>
      ${btn(`${APP}/hr/conduct`, "Open conduct review")}`),
  }),
  resit_supervised: (p) => ({
    subject: "Your re-sit will be supervised",
    html: shell(`Hi ${p.trainee},`, `<p>Your <b>${p.assessment}</b> result could not be confirmed.
      You will re-sit it at a supervised test centre; HR will share the slot. This does not use
      one of your two attempts.</p>`),
  }),
  inactivity_nudge: (p) => ({
    subject: "We missed you on the Academy",
    html: shell(`Hi ${p.trainee},`, `<p>You have ${p.open_items} items open for today.
      Need help? Ask the Academy assistant or your mentor.</p>${btn(`${APP}/journey`, "Resume")}`),
  }),
};
