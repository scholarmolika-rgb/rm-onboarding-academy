// Supabase adapter for web/index.html — swap the prototype's demo data for live calls.
// Load in index.html before the app script:
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script type="module"> import { api } from "./supabase-client.js"; … </script>
// Create a private Storage bucket named "training" and upload /content into it.
// Use only the ANON key in the browser; Row Level Security decides what each user sees.
const SUPABASE_URL = "https://<project-ref>.supabase.co";
const SUPABASE_ANON_KEY = "<anon-key>";
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export const api = {
  // Auth: magic link for the pilot; switch to SAML SSO (Azure AD / Okta) for production
  signIn: (email) => sb.auth.signInWithOtp({ email }),
  signOut: () => sb.auth.signOut(),

  // Trainee
  myStatus: () => sb.from("v_trainee_status").select("*").single(),
  myItems: (phase) => sb.from("learning_items").select("*, modules!inner(phase_id, code, title)")
                        .eq("modules.phase_id", phase).order("day_no").order("sort"),
  completeItem: async (itemId) => {
    const { data: me } = await sb.rpc("me");
    return sb.from("progress").upsert({ trainee_id: me, item_id: itemId, status: "completed",
                                        completed_at: new Date().toISOString() });
  },
  fileUrl: (path) => sb.storage.from("training").createSignedUrl(path, 3600),
  // Secure assessment flow (migration 005): start → declaration → serve/answer one at a time → submit
  startAttempt: (code) => sb.rpc("start_attempt", { p_code: code }),          // GATE_1 | GATE_2 | FINAL → {attempt_id, session_token, ...}
  acceptDeclaration: (a, token) => sb.rpc("accept_declaration", { p_attempt: a, p_token: token }),
  nextQuestion: (a, token) => sb.rpc("serve_question", { p_attempt: a, p_token: token }),  // {seq, stem, options, seconds_left} | {done:true}
  answer: (a, token, seq, displayIdx) =>
    sb.rpc("answer_question", { p_attempt: a, p_token: token, p_seq: seq, p_display_idx: displayIdx }),
  logEvent: (a, kind, seq) => sb.rpc("log_attempt_event", { p_attempt: a, p_kind: kind, p_seq: seq }),
  // wire once per attempt: visibilitychange/blur → focus_lost, copy/paste → paste, fullscreenchange → fullscreen_exit
  submitAttempt: (attemptId) => sb.rpc("submit_attempt", { p_attempt: attemptId, p_answers: null }),
  myIntegrityReviews: () => sb.from("v_my_integrity_reviews").select("*"),
  verifyAttempt: (a, outcome, vivaScore, notes) =>
    sb.rpc("verify_attempt", { p_attempt: a, p_outcome: outcome, p_viva_score: vivaScore, p_notes: notes }),
  recordViva: (trainee, stage, score, notes) =>
    sb.rpc("record_viva", { p_trainee: trainee, p_stage: stage, p_score: score, p_notes: notes }),
  logShadow: (row) => sb.from("shadow_logs").insert(row),                     // customer_ref must be masked
  pulse: (row) => sb.from("pulse_surveys").insert(row),

  // HR: people
  seatUsage: () => sb.from("v_seat_usage").select("*"),
  coachLoad: () => sb.from("v_coach_load").select("*").order("role").order("department"),
  departments: () => sb.from("departments").select("*"),
  // {full_name, email, phone, department, region, experience_months, previous_employer, previous_role, start_date, manager_id?, mentor_id?}
  createJoinee: (row) => sb.rpc("hr_create_joinee", { p: row }),
  createJoinees: (rows) => sb.rpc("hr_create_joinees", { p_rows: rows }),   // per-row {ok, error}

  // Coaches
  myCoachingQueue: () => sb.from("v_my_coaching_queue").select("*").order("sla_due"),
  recordCoaching: (sessionId, decision, notes, repeatModules = []) =>
    sb.rpc("record_coaching", { p_session: sessionId, p_decision: decision, p_notes: notes,
                                p_repeat_modules: repeatModules }),
  signOff: (traineeId, approved, comments) =>
    sb.rpc("sign_off", { p_trainee: traineeId, p_approved: approved, p_comments: comments }),

  // HR / leadership
  kpis: () => sb.from("v_programme_kpis").select("*").single(),
  trainees: (filters = {}) => {
    let q = sb.from("v_trainee_status").select("*");
    Object.entries(filters).forEach(([k, v]) => (q = q.eq(k, v)));
    return q.order("risk_score", { ascending: false }).limit(200);
  },

  // Assistant
  ask: async (message) => {
    const { data: { session } } = await sb.auth.getSession();
    const r = await fetch(`${SUPABASE_URL}/functions/v1/chatbot`, {
      method: "POST",
      headers: { Authorization: `Bearer ${session.access_token}`, apikey: SUPABASE_ANON_KEY,
                 "content-type": "application/json" },
      body: JSON.stringify({ message }),
    });
    return r.json(); // { answer, sources }
  },
};
