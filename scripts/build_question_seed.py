#!/usr/bin/env python3
"""Build supabase/seed_questions.sql from content/assessments/question-bank.json
plus generated calculation variants.

Why variants: each calculation question exists in several versions with different
numbers ("families"). start_attempt() serves ONE random variant per family, so two
trainees rarely see the same numbers, answers cannot be shared, and a pre-computed
answer list found online (or produced by an AI before the test) is useless.

Usage:  python scripts/build_question_seed.py
"""
import json, pathlib, random

root = pathlib.Path(__file__).resolve().parents[1]
bank = json.loads((root / "content/assessments/question-bank.json").read_text())
rng = random.Random(2026)   # deterministic output → reviewable diffs in pull requests

def q(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"

def cr(v: float) -> str:
    """Indian-format money: ₹ lakh below 1 Cr, else ₹ Cr."""
    if abs(v) < 1:
        return f"₹{v*100:,.2f} lakh".replace(".00 ", " ")
    return f"₹{v:,.2f} Cr".replace(".00 ", " ")

def mcq(correct: str, wrong: list[str]):
    opts = [correct] + [w for w in dict.fromkeys(wrong) if w != correct][:3]
    while len(opts) < 4:
        opts.append(cr(rng.uniform(1, 90)))
    rng.shuffle(opts)
    return opts, opts.index(correct)

# ---- calculation families ----------------------------------------------
def dp():
    s, r, c = rng.choice([80, 90, 110, 120, 140]), rng.choice([40, 50, 60, 70]), rng.choice([20, 30, 35, 45])
    m = rng.choice([0.20, 0.25, 0.30])
    ok = (s + r - c) * (1 - m)
    opts, a = mcq(cr(ok), [cr(s + r - c), cr((s + r) * (1 - m)), cr((s + r + c) * (1 - m))])
    return ("GATE_1", "PRD", f"Stock ₹{s} Cr, eligible receivables ₹{r} Cr, trade creditors ₹{c} Cr, margin {int(m*100)}%. Drawing power is:",
            opts, a, "(Stock + receivables − creditors) × (1 − margin).")

def nii():
    amt, y, f = rng.choice([10, 15, 20, 25, 40]), rng.choice([9.25, 9.5, 9.75, 10.0]), rng.choice([6.75, 7.0, 7.25])
    ok = amt * (y - f) / 100
    opts, a = mcq(cr(ok), [cr(amt * y / 100), cr(amt * f / 100), cr(ok * 10)])
    return (None, "PRI", f"Loan ₹{amt} Cr at {y:.2f}% with an FTP of {f:.2f}%. Annual net interest income is:",
            opts, a, "(Yield − FTP) × balance.")

def el():
    pd, lgd, ead = rng.choice([0.5, 1, 1.5, 2, 3]), rng.choice([35, 40, 45, 50]), rng.choice([20, 30, 40, 50, 60])
    ok = pd / 100 * lgd / 100 * ead
    opts, a = mcq(cr(ok), [cr(pd / 100 * ead), cr(lgd / 100 * ead), cr(ok * 10)])
    return (None, "PRI", f"PD {pd}%, LGD {lgd}%, EAD ₹{ead} Cr. Expected loss is:", opts, a, "PD × LGD × EAD.")

def capital():
    exp, rw = rng.choice([50, 80, 100, 150]), rng.choice([20, 30, 50, 100])
    ok = exp * rw / 100 * 0.115
    opts, a = mcq(cr(ok), [cr(exp * 0.115), cr(exp * rw / 100), cr(exp * rw / 100 * 0.09)])
    return ("GATE_2", "PRI", f"Exposure ₹{exp} Cr to a corporate with a {rw}% risk weight; capital ratio 11.5%. Capital required is:",
            opts, a, "Exposure × risk weight × capital ratio.")

def lc_fee():
    lim, u, c = rng.choice([20, 30, 50, 75]), rng.choice([40, 50, 60, 80]), rng.choice([0.4, 0.5, 0.75, 1.0])
    ok = lim * u / 100 * c / 100
    opts, a = mcq(cr(ok), [cr(lim * c / 100), cr(ok * 10), cr(lim * u / 100 * c / 1000)])
    return ("GATE_2", "PRI", f"LC limit ₹{lim} Cr, average utilisation {u}%, commission {c}% p.a. Annual LC fee is:",
            opts, a, "Limit × utilisation × commission rate.")

FAMILIES = [("CALC_DP", dp, 6), ("CALC_NII", nii, 6), ("CALC_EL", el, 6), ("CALC_CAP", capital, 5), ("CALC_LCFEE", lc_fee, 5)]
# static bank questions that belong to the same family (served as one more variant)
STATIC_FAMILY = {"Stock ₹100 Cr": "CALC_DP", "Loan ₹10 Cr at 9.50%": "CALC_NII", "Loan ₹25 Cr, yield": "CALC_NII",
                 "PD 2%, LGD 45%": "CALC_EL", "PD 1%, LGD 40%": "CALC_EL", "Exposure ₹100 Cr": "CALC_CAP",
                 "LC limit ₹50 Cr": "CALC_LCFEE"}
CALC_HINTS = ("₹", "bps", "%", "wallet")

rows = []
def add(code, module, stem, opts, ans, exp, family, is_calc, difficulty=2):
    rows.append("((select id from assessments where code={c}),(select id from modules where code={m}),"
                "{stem},{opts}::jsonb,{ans},{exp},{fam},{calc},{d})".format(
                    c=q(code), m=q(module), stem=q(stem), opts=q(json.dumps(opts, ensure_ascii=False)),
                    ans=int(ans), exp=q(exp), fam=q(family) if family else "null",
                    calc="true" if is_calc else "false", d=difficulty))

for code, items in bank.items():
    if code.startswith("_"):
        continue
    for it in items:
        fam = next((f for k, f in STATIC_FAMILY.items() if it["stem"].startswith(k)), None)
        is_calc = fam is not None or (it["module"] in ("PRI", "PNL") and any(h in it["stem"] for h in CALC_HINTS))
        add(code, it["module"], it["stem"], it["options"], it["answer"], it.get("explanation", ""),
            fam if fam else None, is_calc, 3 if is_calc else 2)

gen = 0
for fam, fn, n in FAMILIES:
    for _ in range(n):
        code, module, stem, opts, a, exp = fn()
        targets = [code] if code else ["GATE_2", "FINAL"]   # NII / EL appear in Gate 2 and Final
        for tgt in targets:
            add(tgt, module, stem, opts, a, exp, fam, True, 3)
            gen += 1

sql = ("-- generated by scripts/build_question_seed.py — do not edit by hand\n"
       "insert into questions(assessment_id, module_id, stem, options, answer_idx, explanation, family, is_calc, difficulty) values\n"
       + ",\n".join(rows) + ";\n")
(root / "supabase/seed_questions.sql").write_text(sql, encoding="utf-8")
print(f"wrote {len(rows)} questions ({gen} generated calculation variants) → supabase/seed_questions.sql")
