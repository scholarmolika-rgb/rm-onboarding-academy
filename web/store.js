// store.js — the "state store": one place where every change made in the UI is saved to Supabase.
//
// The prototype (web/index.html) keeps its data in memory. To make it live, each UI handler
// calls the matching method below instead of changing its in-memory objects, then re-reads
// the data it shows. Nothing is saved in the browser except what Supabase Auth keeps for the
// session. Screen state (last page, open day, filters, unsent drafts) goes to the ui_state table.
//
// Usage (see docs/SUPABASE_SETUP_GUIDE.md, Part 3):
//   import { api } from "./supabase-client.js";
//   import { createStore } from "./store.js";
//   const store = createStore(api);
//   await store.signIn("TRN0025", "…");
//   await store.markComplete("6-1");         // same "day-index" keys the UI uses

export function createStore(api) {
  const s = {
    session: null,          // {role, login_id, must_change_password}
    itemIdByKey: new Map(), // "6-1" (day 6, 2nd item) → learning_items.id
    ui: {},                 // key → value from ui_state
    listeners: new Set(),
  };

  // Every call goes through here: one error shape for the UI, and a refresh signal after writes.
  async function call(label, promise, { write = true } = {}) {
    const res = await promise;
    const error = res?.error;
    if (error) throw new Error(friendly(error.message || String(error), label));
    if (write) s.listeners.forEach((fn) => fn(label));
    return res.data;
  }
  // Database messages are already written for people (see the migrations); trim technical prefixes.
  const friendly = (m, label) => m.replace(/^(ERROR:\s*|P0001:\s*)/i, "") || `Could not ${label}.`;

  async function loadLearningKeys() {
    const items = await call("load learning items", api.learningItems(), { write: false });
    const byDay = new Map();
    for (const it of items) {                     // same ordering as the UI: day, then sort
      const list = byDay.get(it.day_no) ?? [];
      list.push(it);
      byDay.set(it.day_no, list);
    }
    s.itemIdByKey.clear();
    for (const [day, list] of byDay) list.forEach((it, i) => s.itemIdByKey.set(`${day}-${i}`, it.id));
  }
  const itemId = (key) => {
    const id = s.itemIdByKey.get(key);
    if (!id) throw new Error(`Unknown learning item ${key}`);
    return id;
  };

  // UI state: save quietly, at most once a second per key
  const timers = {};
  function saveUi(key, value) {
    s.ui[key] = value;
    clearTimeout(timers[key]);
    timers[key] = setTimeout(() => api.saveUiState(key, value).catch(() => {}), 1000);
  }

  return {
    get session() { return s.session; },
    onChange(fn) { s.listeners.add(fn); return () => s.listeners.delete(fn); },

    // ---------- sign-in ----------
    async signIn(loginId, password) {
      const res = await api.signIn(loginId, password);
      if (res.error) throw new Error(res.error.message);
      s.session = res.data;
      await loadLearningKeys();
      const rows = await call("load screen state", api.loadUiState(), { write: false });
      s.ui = Object.fromEntries((rows ?? []).map((r) => [r.key, r.value]));
      return s.session;                       // UI shows the change-password screen if must_change_password
    },
    changePassword: (pw) => api.changePassword(pw).then((r) => { if (r.error) throw new Error(r.error.message); }),
    signOut: () => { s.session = null; return api.signOut(); },
    uiState: (key, fallback) => s.ui[key] ?? fallback,
    saveUi,

    // ---------- New Joinee ----------
    myStatus: () => call("load your journey", api.myStatus(), { write: false }),
    async progressKeys() {                         // → Set of "day-index" keys already completed
      const rows = await call("load progress", api.myProgress(), { write: false });
      const done = new Set(rows.filter((r) => r.status === "completed").map((r) => r.item_id));
      return new Set([...s.itemIdByKey].filter(([, id]) => done.has(id)).map(([k]) => k));
    },
    markComplete: (key) => call("mark this item complete", api.completeItem(itemId(key))),
    startAttempt: (gateCode) => call("start the assessment", api.startAttempt(gateCode)),
    acceptDeclaration: (a, token) => call("accept the declaration", api.acceptDeclaration(a, token)),
    nextQuestion: (a, token) => call("load the next question", api.nextQuestion(a, token), { write: false }),
    answer: (a, token, seq, displayIdx) => call("save your answer", api.answer(a, token, seq, displayIdx)),
    logTestEvent: (a, kind, seq) => api.logEvent(a, kind, seq),          // fire and forget
    submitAttempt: (a) => call("submit the assessment", api.submitAttempt(a)),
    finishRefresher: (assignmentId) => call("complete the refresher", api.completeRemediation(assignmentId)),
    sendPulse: (row) => call("send your pulse", api.pulse(row)),
    addShadowLog: (row) => call("save the shadow log", api.logShadow(row)),

    // ---------- Mentor / Reporting Boss ----------
    coachingQueue: () => call("load coaching", api.myCoachingQueue(), { write: false }),
    decideCoaching: (sessionId, decision, notes, repeatModuleIds) =>
      call("record your decision", api.recordCoaching(sessionId, decision, notes, repeatModuleIds)),
    integrityReviews: () => call("load result checks", api.myIntegrityReviews(), { write: false }),
    verifyResult: (attemptId, outcome, vivaScore, notes) =>
      call("record the verification", api.verifyAttempt(attemptId, outcome, vivaScore, notes)),
    rateShadowLog: (logId, competencies, feedback) => call("rate the shadow log", api.rateShadow(logId, competencies, feedback)),
    recordViva: (traineeId, stage, score, notes) => call("record the viva", api.recordViva(traineeId, stage, score, notes)),
    signOff: (traineeId, approved, comments) => call("sign off", api.signOff(traineeId, approved, comments)),

    // ---------- HR ----------
    seats: () => call("load seats", api.seatUsage(), { write: false }),
    coachLoad: () => call("load people", api.coachLoad(), { write: false }),
    addJoinee: (row) => call("add the joinee", api.createJoinee(row)),
    addJoinees: (rows) => call("import joinees", api.createJoinees(rows)),       // per-row {ok, error}
    withdrawJoinee: (id, reason) => call("withdraw the joinee", api.withdrawJoinee(id, reason)),
    addStaff: (row) => call("add the person", api.addStaff(row)),
    setStaffActive: (id, active) => call("change the person", api.setStaffActive(id, active)),
    logins: () => call("load logins", api.logins(), { write: false }),
    async provision(action, profileIds) {        // create | reset | disable | enable → [{login_id, temp_password?, ok, error?}]
      const data = await call("change logins", api.provision(action, profileIds));
      return data?.results ?? [];
    },
    decideReview: (id, decision, notes) => call("record the HR decision", api.decideReview(id, decision, notes)),
    kpis: () => call("load programme health", api.kpis(), { write: false }),
    trainees: (filters) => call("load joinees", api.trainees(filters), { write: false }),

    // ---------- chatbot ----------
    ask: (message) => api.ask(message),

    // ---------- live updates for open screens ----------
    live(onChange) {
      return api.subscribe(["profiles", "journeys", "coaching_sessions", "signoffs", "shadow_logs", "progress"], onChange);
    },
  };
}
