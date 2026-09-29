// chatbot — "Academy Assistant"
// RAG over the training content (pgvector + Supabase built-in gte-small embeddings),
// personalised with the trainee's journey state, answered by an LLM.
//
// LLM_PROVIDER=anthropic          → Claude via Anthropic API (default)
// LLM_PROVIDER=openai_compatible  → any OpenAI-compatible endpoint: Azure OpenAI,
//                                   vLLM / Ollama hosting Llama, Mistral, Qwen on-prem
//                                   (useful when data must stay inside the bank's network)
//
// POST { message: string }                     (user JWT)  → { answer, sources }
// POST { action: "ingest", chunks: [...] }     (service key) → embeds & stores chunks
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(URL_, SERVICE);
// @ts-ignore Supabase edge runtime global
const embedder = new Supabase.ai.Session("gte-small");

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

const embed = async (text: string) =>
  (await embedder.run(text, { mean_pool: true, normalize: true })) as number[];

// Redact anything that looks like customer identifiers before it leaves the bank
const redact = (s: string) => s
  .replace(/\b[A-Z]{5}[0-9]{4}[A-Z]\b/g, "[PAN]")
  .replace(/\b\d{4}\s?\d{4}\s?\d{4}\b/g, "[AADHAAR]")
  .replace(/\b\d{9,18}\b/g, "[ACCOUNT]")
  .replace(/\b[A-Z]{4}0[A-Z0-9]{6}\b/g, "[IFSC]");

const SYSTEM = `You are the RM Onboarding Academy assistant for a large private-sector corporate bank in India.
You help new Relationship Managers during their 30-day onboarding.
Rules:
- Answer ONLY from the provided CONTEXT excerpts and the trainee's journey data. If the context does not cover it, say so and suggest asking the mentor.
- Cite the source file names you used in a final line "Sources: ...".
- For calculations (drawing power, NII, expected loss, RAROC, P&L) show the formula, then the working, then the answer in ₹ lakh / ₹ Cr.
- Never reveal assessment answers or answer keys. If asked for test answers, explain the concept instead.
- Never request, store or repeat customer personal data. If the user pastes any, tell them to remove it.
- For policy exceptions, credit decisions or HR matters, direct them to their mentor, reporting manager or HR partner by role.
- Be concise, professional and encouraging.`;

async function callLLM(system: string, messages: { role: string; content: string }[]) {
  const provider = Deno.env.get("LLM_PROVIDER") ?? "anthropic";
  if (provider === "anthropic") {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("LLM_MODEL") ?? "claude-sonnet-5-5",
        max_tokens: 900, system, messages,
      }),
    });
    if (!r.ok) throw new Error(`LLM ${r.status}: ${await r.text()}`);
    const j = await r.json();
    return j.content?.map((c: any) => c.text ?? "").join("") ?? "";
  }
  // OpenAI-compatible (Azure OpenAI, vLLM, Ollama, etc.)
  const r = await fetch(`${Deno.env.get("LLM_BASE_URL")}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${Deno.env.get("LLM_API_KEY")}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: Deno.env.get("LLM_MODEL"), max_tokens: 900,
      messages: [{ role: "system", content: system }, ...messages],
    }),
  });
  if (!r.ok) throw new Error(`LLM ${r.status}: ${await r.text()}`);
  return (await r.json()).choices[0].message.content as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const auth = req.headers.get("Authorization") ?? "";
  const body = await req.json();

  // ---------- ingestion (service role only) ----------
  if (body.action === "ingest") {
    if (auth !== `Bearer ${SERVICE}`) return new Response("forbidden", { status: 403 });
    if (body.reset) await admin.from("kb_chunks").delete().neq("id", 0);
    const rows = [];
    for (const c of body.chunks as { source: string; heading: string; content: string; module?: string }[]) {
      const { data: m } = c.module
        ? await admin.from("modules").select("id").eq("code", c.module).maybeSingle()
        : { data: null };
      rows.push({ source: c.source, heading: c.heading, content: c.content,
                  module_id: m?.id ?? null, embedding: await embed(`${c.heading}\n${c.content}`) });
    }
    const { error } = await admin.from("kb_chunks").insert(rows);
    return Response.json({ inserted: error ? 0 : rows.length, error: error?.message }, { headers: cors });
  }

  // ---------- chat (signed-in user) ----------
  const userClient = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: me } = await userClient.rpc("me");
  if (!me) return new Response("unauthorised", { status: 401, headers: cors });

  // Assessment integrity: the assistant is closed while the trainee has a test open
  const { data: testOpen } = await userClient.rpc("has_open_attempt");
  if (testOpen) {
    await admin.from("attempt_events").insert({
      attempt_id: (await admin.from("attempts").select("id").eq("trainee_id", me).is("submitted_at", null)
                     .order("started_at", { ascending: false }).limit(1).single()).data?.id,
      trainee_id: me, kind: "assistant_during_test",
    });
    return Response.json({
      answer: "The Academy Assistant is paused while your assessment is in progress. It will be back as soon as you submit. Good luck.",
      sources: [], locked: true,
    }, { headers: cors });
  }

  const question = redact(String(body.message ?? "").slice(0, 2000));
  const [{ data: hits }, { data: status }, { data: history }] = await Promise.all([
    admin.rpc("match_kb", { query_embedding: await embed(question), match_count: 6 }),
    userClient.from("v_trainee_status").select("*").eq("id", me).maybeSingle(),
    admin.from("chat_messages").select("role,content").eq("profile_id", me)
      .order("created_at", { ascending: false }).limit(6),
  ]);

  const context = (hits ?? []).map((h: any) => `[${h.source} › ${h.heading}]\n${h.content}`).join("\n\n");
  const journey = status
    ? `Trainee: ${status.full_name}; phase ${status.current_phase}; status ${status.status}; training day ${status.training_day}; Gate1 best ${status.gate1_best ?? "—"}%; Gate2 best ${status.gate2_best ?? "—"}%; mentor ${status.mentor}.`
    : "User is a mentor/manager/HR, not a trainee.";

  const past = (history ?? []).reverse();
  while (past.length && past[0].role !== "user") past.shift();   // API needs user-first turns
  const messages = [
    ...past,
    { role: "user", content: `JOURNEY: ${journey}\n\nCONTEXT:\n${context || "(no matching content)"}\n\nQUESTION: ${question}` },
  ];

  try {
    const answer = await callLLM(SYSTEM, messages);
    const sources = [...new Set((hits ?? []).map((h: any) => h.source))];
    await admin.from("chat_messages").insert([
      { profile_id: me, role: "user", content: question },
      { profile_id: me, role: "assistant", content: answer, sources },
    ]);
    return Response.json({ answer, sources }, { headers: cors });
  } catch (e) {
    return Response.json({ answer: "The assistant is unavailable right now. Please try again or ask your mentor.",
                           error: String(e) }, { status: 502, headers: cors });
  }
});
