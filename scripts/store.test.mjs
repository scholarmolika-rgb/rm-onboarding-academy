import assert from "node:assert/strict";
import { createStore } from "../web/store.js";
const calls = [];
const ok = (data) => Promise.resolve({ data });
const api = new Proxy({
  signIn: async () => ({ data: { role: "trainee", login_id: "TRN0025", must_change_password: false } }),
  learningItems: () => ok([{ id: 11, day_no: 1, sort: 1 }, { id: 12, day_no: 1, sort: 2 }, { id: 13, day_no: 6, sort: 1 }, { id: 14, day_no: 6, sort: 2 }]),
  loadUiState: () => ok([{ key: "joinee.programme", value: { day: 6 } }]),
  myProgress: () => ok([{ item_id: 14, status: "completed" }]),
  createJoinee: () => Promise.resolve({ error: { message: "New joinees must have more than 3 and less than 5 years of experience (got 30 months)" } }),
}, { get: (t, k) => t[k] ?? ((...a) => { calls.push([k, a]); return ok({ results: [] }); }) });
const store = createStore(api);
let changes = 0; store.onChange(() => changes++);
await store.signIn("TRN0025", "x");
assert.deepEqual(store.uiState("joinee.programme"), { day: 6 });
await store.markComplete("6-1");
assert.equal(calls.find(c => c[0] === "completeItem")[1][0], 14);
assert.deepEqual([...await store.progressKeys()], ["6-1"]);
await assert.rejects(store.addJoinee({}), /more than 3 and less than 5 years/);
assert.throws(() => store.markComplete("99-0"), /Unknown learning item/);
assert.equal(changes, 1);
console.log("state store adapter: all checks passed");
