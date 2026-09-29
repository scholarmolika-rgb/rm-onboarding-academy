// Load all training markdown into the chatbot knowledge base.
// Usage: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/ingest-kb.mjs
import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";

const root = new URL("../content/", import.meta.url).pathname;
const moduleByFolder = { "01-governance": "GOV", "02-people": "PPL", "03-product": "PRD",
  "04-process": "PRC", "05-pricing-pnl": "PRI", "06-shadowing": "SHD" };

async function* walk(dir) {
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    // never index the question bank: the assistant must not be able to leak test content
    if (e.isDirectory()) { if (e.name !== "assessments") yield* walk(p); }
    else if (p.endsWith(".md")) yield p;
  }
}

const chunks = [];
for await (const file of walk(root)) {
  const rel = relative(root, file);
  const module = moduleByFolder[rel.split("/")[0]];
  const text = await readFile(file, "utf8");
  // split on H2 headings; keep sections ≤ ~1,500 chars
  for (const section of text.split(/\n(?=## )/)) {
    const heading = (section.match(/^#+\s*(.+)/) ?? [, rel])[1].trim();
    for (let i = 0; i < section.length; i += 1500) {
      chunks.push({ source: rel, heading, module, content: section.slice(i, i + 1500) });
    }
  }
}

const url = `${process.env.SUPABASE_URL}/functions/v1/chatbot`;
for (let i = 0; i < chunks.length; i += 20) {
  const r = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ action: "ingest", reset: i === 0, chunks: chunks.slice(i, i + 20) }),
  });
  console.log(i, r.status, await r.text());
}
console.log(`ingested ${chunks.length} chunks`);
