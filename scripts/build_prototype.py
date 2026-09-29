#!/usr/bin/env python3
"""Build web/index.html from web/src/app.template.html + the training content in /content.

The prototype carries the real curriculum (readable notes, working files) so that
what L&D edits in /content is exactly what trainees read. Run after any content change:

    python scripts/build_prototype.py
"""
import csv, json, pathlib

root = pathlib.Path(__file__).resolve().parents[1]
C = root / "content"

# Mirrors supabase/seed.sql learning_items (day, module, title, kind, source)
ITEMS = [
 (1,"GOV","Bank structure & how the corporate bank earns","read","01-governance/day01-bank-structure.md"),
 (1,"GOV","Code of conduct, conflicts, gifts & whistleblowing","read","01-governance/day01-code-of-conduct.md"),
 (2,"GOV","Regulatory map: RBI, PMLA, FEMA, SEBI, DPDP","read","01-governance/day02-regulatory-map.md"),
 (2,"GOV","KYC / beneficial ownership checklist","worksheet","working-files/kyc-checklist.csv"),
 (3,"GOV","AML red flags: case vignettes","case","01-governance/day03-aml-cases.md"),
 (3,"GOV","Data privacy (DPDP Act 2023) & information security","read","01-governance/day03-data-privacy.md"),
 (4,"PPL","The RM role, KRAs and a day in the life","read","02-people/day04-rm-role.md"),
 (4,"PPL","Internal stakeholder map","worksheet","working-files/stakeholder-map.csv"),
 (5,"PPL","Consultative conversations: discovery & objections","simulation","02-people/day05-consultative-selling.md"),
 (5,"PPL","POSH, diversity & respectful workplace","read","02-people/day05-posh.md"),
 (6,"PRD","Working capital: CC, OD, WCDL, drawing power","read","03-product/day06-working-capital.md"),
 (6,"PRD","Drawing power calculator","worksheet","calc:dp"),
 (7,"PRD","Term loans, project finance basics, DSCR","read","03-product/day07-term-loans.md"),
 (8,"PRD","Trade finance: LC, BG, bill discounting, PCFC","read","03-product/day08-trade-finance.md"),
 (9,"PRD","Transaction banking: CMS, payroll, supply chain finance","read","03-product/day09-transaction-banking.md"),
 (10,"PRD","Treasury, FX hedging & liability products","read","03-product/day10-treasury-liabilities.md"),
 (10,"PRD","Case: facility design for Apex Auto Components","case","03-product/day10-product-case.md"),
 (11,"PRC","Client onboarding journey & account opening","read","04-process/day11-onboarding.md"),
 (12,"PRC","Credit Appraisal Memo (CAM) template","worksheet","04-process/day12-cam-template.md"),
 (13,"PRC","Sanction, documentation, CERSAI & disbursement","read","04-process/day13-documentation.md"),
 (14,"PRC","Monitoring: EWS, SMA, NPA norms, renewals","read","04-process/day14-monitoring.md"),
 (14,"PRC","Complaints, grievance redressal & CRM hygiene","read","04-process/day14-grievance-crm.md"),
 (15,"GATE","Day 15 Foundation Assessment · pass mark 80%","assessment","gate:G1"),
 (16,"PRI","How loans are priced: EBLR/MCLR, FTP, spread","read","05-pricing-pnl/day16-pricing-basics.md"),
 (17,"PRI","Risk-based pricing: PD × LGD × EAD, capital, RAROC","read","05-pricing-pnl/day17-raroc.md"),
 (17,"PRI","Loan pricing & RAROC calculator","worksheet","calc:raroc"),
 (18,"PRI","Fee income and pricing deviations","read","05-pricing-pnl/day18-fees-deviations.md"),
 (19,"PNL","Relationship P&L: NII, fees, cost, provisions, RoE","read","05-pricing-pnl/day19-relationship-pnl.md"),
 (19,"PNL","Relationship P&L builder","worksheet","calc:pnl"),
 (20,"PNL","Portfolio P&L, wallet share & cross-sell plan","simulation","05-pricing-pnl/day20-portfolio.md"),
 (21,"GATE","Day 21 Pricing & P&L Assessment · pass mark 75%","assessment","gate:G2"),
 (22,"SHD","Shadowing playbook & competency rubric","read","06-shadowing/shadowing-playbook.md"),
] + [(d,"SHD",f"Shadow day {d-21}: observe, log & reflect","shadow_task","shadow") for d in range(22,30)] + [
 (30,"GATE","Day 30 Certification Assessment, viva & sign-off","assessment","gate:F"),
]

days = {}
for day, mod, title, kind, src in ITEMS:
    item = {"t": title, "k": kind}
    if src.endswith(".md"):
        item["md"] = (C / src).read_text(encoding="utf-8"); item["src"] = src
    elif src.endswith(".csv"):
        with open(C / src, newline="", encoding="utf-8") as f:
            item["csv"] = list(csv.reader(f))
        item["src"] = src
    else:
        item["ref"] = src
    days.setdefault(str(day), {"m": mod, "items": []})["items"].append(item)

bank = json.loads((C / "assessments/question-bank.json").read_text(encoding="utf-8"))
bank.pop("_notes", None)

payload = "const CONTENT=" + json.dumps({"days": days, "bank": bank}, ensure_ascii=False) + ";"
payload = payload.replace("</", "<\\/")      # never close the <script> early
tpl = (root / "web/src/app.template.html").read_text(encoding="utf-8")
out = tpl.replace("/*__CONTENT__*/", payload)
(root / "web/index.html").write_text(out, encoding="utf-8")
print(f"web/index.html: {len(days)} days, {sum(len(v['items']) for v in days.values())} items, {len(out)//1024} KB")
