-- =====================================================================
-- Seed: curriculum, assessments, cohort and the 1,000 / 20 / 20 / 5 org
-- Questions are loaded separately from content/assessments/*.json by
-- scripts/build_question_seed.py → supabase/seed_questions.sql
-- =====================================================================

insert into phases(id, code, title, day_from, day_to) values
 (1,'FOUNDATION','Foundation: Governance, People, Product, Process', 1, 15),
 (2,'PRICING_PNL','Product Pricing & Relationship P&L',               16, 21),
 (3,'SHADOWING','Live Customer Shadowing & Certification',           22, 30);

insert into modules(phase_id, code, title, pillar, day_from, day_to, sort) values
 (1,'GOV','Governance, Regulation & Conduct',              'governance', 1, 3, 1),
 (1,'PPL','People, Culture & the RM Role',                 'people',     4, 5, 2),
 (1,'PRD','Corporate Banking Products',                    'product',    6,10, 3),
 (1,'PRC','Credit & Operating Processes',                  'process',   11,14, 4),
 (2,'PRI','Product Pricing & Calculations',                'pricing',   16,18, 5),
 (2,'PNL','Relationship P&L and Portfolio Economics',      'pnl',       19,20, 6),
 (3,'SHD','Shadow Customer Handling',                      'shadowing', 22,29, 7);

-- Learning items: readable (read/video) + working (worksheet/simulation/case)
insert into learning_items(module_id, day_no, title, kind, storage_path, est_minutes, sort)
select m.id, v.day_no, v.title, v.kind::item_kind, v.path, v.mins, v.sort
from (values
 ('GOV', 1,'Welcome, bank structure & how the corporate bank makes money','read','01-governance/day01-bank-structure.md',60,1),
 ('GOV', 1,'Code of conduct, conflict of interest, gifts & whistleblowing','read','01-governance/day01-code-of-conduct.md',45,2),
 ('GOV', 2,'Regulatory map: RBI, SEBI, FEMA, PMLA — what an RM must know','read','01-governance/day02-regulatory-map.md',90,1),
 ('GOV', 2,'KYC / CDD / EDD and beneficial ownership walk-through','worksheet','working-files/kyc-checklist.csv',60,2),
 ('GOV', 3,'AML red flags — 10 case vignettes','case','01-governance/day03-aml-cases.md',90,1),
 ('GOV', 3,'Data privacy (DPDP Act 2023) & information security','read','01-governance/day03-data-privacy.md',45,2),
 ('PPL', 4,'The RM role, KRAs and a day in the life','read','02-people/day04-rm-role.md',60,1),
 ('PPL', 4,'Internal stakeholder map: credit, ops, treasury, trade, legal','worksheet','working-files/stakeholder-map.csv',45,2),
 ('PPL', 5,'Consultative conversations: needs discovery & objection handling','simulation','02-people/day05-consultative-selling.md',90,1),
 ('PPL', 5,'POSH, diversity & respectful workplace','read','02-people/day05-posh.md',30,2),
 ('PRD', 6,'Working capital: CC, OD, WCDL, drawing power','read','03-product/day06-working-capital.md',90,1),
 ('PRD', 6,'Drawing power calculator','worksheet','working-files/RM_Pricing_and_PnL_Workbook.xlsx#DrawingPower',45,2),
 ('PRD', 7,'Term loans, project finance basics, DSCR','read','03-product/day07-term-loans.md',90,1),
 ('PRD', 8,'Trade finance: LC, BG, bill discounting, PCFC','read','03-product/day08-trade-finance.md',90,1),
 ('PRD', 9,'Transaction banking: cash management, payroll, supply chain finance','read','03-product/day09-transaction-banking.md',90,1),
 ('PRD',10,'Treasury & FX hedging for corporates; liability products','read','03-product/day10-treasury-liabilities.md',90,1),
 ('PRD',10,'Product-fit case: design the facility structure for "Apex Auto Components"','case','03-product/day10-product-case.md',60,2),
 ('PRC',11,'Client onboarding journey & account opening TAT','read','04-process/day11-onboarding.md',60,1),
 ('PRC',12,'Credit appraisal & writing a Credit Appraisal Memo (CAM)','worksheet','04-process/day12-cam-template.md',120,1),
 ('PRC',13,'Sanction, documentation, security creation & disbursement','read','04-process/day13-documentation.md',90,1),
 ('PRC',14,'Monitoring: EWS, SMA-0/1/2, NPA norms, renewals','read','04-process/day14-monitoring.md',90,1),
 ('PRC',14,'Complaints, grievance redressal & CRM hygiene','read','04-process/day14-grievance-crm.md',45,2),
 ('PRI',16,'How loans are priced: EBLR/MCLR, FTP, spread build-up','read','05-pricing-pnl/day16-pricing-basics.md',90,1),
 ('PRI',17,'Risk-based pricing: PD × LGD × EAD, capital charge, RAROC','read','05-pricing-pnl/day17-raroc.md',90,1),
 ('PRI',17,'Loan pricing & RAROC calculator','worksheet','working-files/RM_Pricing_and_PnL_Workbook.xlsx#Pricing',60,2),
 ('PRI',18,'Fee income, trade & CMS pricing; deviation approvals','read','05-pricing-pnl/day18-fees-deviations.md',60,1),
 ('PNL',19,'Relationship P&L: NII, fees, cost, provisions, RoE','read','05-pricing-pnl/day19-relationship-pnl.md',90,1),
 ('PNL',19,'Relationship P&L builder','worksheet','working-files/RM_Pricing_and_PnL_Workbook.xlsx#RelationshipPnL',60,2),
 ('PNL',20,'Portfolio P&L, wallet share & cross-sell planning','simulation','05-pricing-pnl/day20-portfolio.md',120,1),
 ('SHD',22,'Shadowing playbook & competency rubric','read','06-shadowing/shadowing-playbook.md',45,1)
) as v(code, day_no, title, kind, path, mins, sort)
join modules m on m.code = v.code;

-- one shadow task per day 22-29 (logged in shadow_logs, signed by mentor)
insert into learning_items(module_id, day_no, title, kind, est_minutes, sort)
select (select id from modules where code='SHD'), d,
       'Shadow day ' || (d-21) || ': observe, log & reflect', 'shadow_task', 420, 2
from generate_series(22,29) d;

insert into assessments(code, title, unlocks_phase, day_no, pass_pct, question_count, duration_min,
                        max_attempts, coach_roles, signoff_roles) values
 ('GATE_1','Day 15 Foundation Assessment', 2, 15, 80, 20, 40, 2,
   array['mentor','reporting_manager','hr']::app_role[], '{}'),
 ('GATE_2','Day 21 Pricing & P&L Assessment', 3, 21, 75, 15, 45, 2,
   array['mentor','reporting_manager']::app_role[], '{}'),
 ('FINAL','Day 30 Certification Assessment', null, 30, 80, 15, 45, 2,
   array['mentor','reporting_manager','hr']::app_role[],
   array['mentor','reporting_manager','hr']::app_role[]);

-- ---------- Cohort & people -------------------------------------------
insert into cohorts(id, name, start_date, holidays) values
 ('00000000-0000-0000-0000-000000000001','Cohort 2026-10 (Wave 1)','2026-10-05',
  array['2026-10-20','2026-11-09','2026-11-10']::date[]);   -- sample bank holidays

-- 5 HR business partners
insert into profiles(employee_code, full_name, email, role, region)
select 'HR' || lpad(i::text,3,'0'),
       (array['Anita Rao','Farhan Qureshi','Meera Pillai','Sandeep Kohli','Lavanya Iyer'])[i],
       'hr' || i || '@bank.example', 'hr',
       (array['North','South','East','West','Central'])[i]
from generate_series(1,5) i;

-- 20 reporting managers (cluster heads) and 20 mentors (senior RMs)
insert into profiles(employee_code, full_name, email, role, region, branch, hr_id)
select 'RM-MGR' || lpad(i::text,3,'0'), 'Manager ' || i, 'manager' || i || '@bank.example',
       'reporting_manager', (array['North','South','East','West','Central'])[1 + (i-1) % 5],
       'Cluster ' || i,
       (select id from profiles where employee_code = 'HR' || lpad((1 + (i-1) % 5)::text,3,'0'))
from generate_series(1,20) i;

insert into profiles(employee_code, full_name, email, role, region, branch, hr_id, manager_id)
select 'MNT' || lpad(i::text,3,'0'), 'Mentor ' || i, 'mentor' || i || '@bank.example',
       'mentor', (array['North','South','East','West','Central'])[1 + (i-1) % 5],
       'Cluster ' || i,
       (select id from profiles where employee_code = 'HR' || lpad((1 + (i-1) % 5)::text,3,'0')),
       (select id from profiles where employee_code = 'RM-MGR' || lpad(i::text,3,'0'))
from generate_series(1,20) i;

-- 1,000 trainees: 50 per mentor/manager pair, 200 per HR partner
insert into profiles(employee_code, full_name, email, role, region, branch, cohort_id,
                     mentor_id, manager_id, hr_id, joined_on)
select 'TRN' || lpad(i::text,4,'0'),
       (array['Aarav','Diya','Kabir','Ishita','Rohan','Sneha','Vikram','Ananya','Arjun','Priya',
              'Nikhil','Tanvi','Rahul','Kavya','Siddharth','Pooja','Aditya','Neha','Varun','Riya'])[1 + i % 20]
       || ' ' ||
       (array['Sharma','Reddy','Iyer','Mehta','Nair','Gupta','Das','Kulkarni','Singh','Banerjee',
              'Patel','Menon','Joshi','Rao','Chawla'])[1 + (i * 7) % 15],
       'trainee' || i || '@bank.example', 'trainee',
       (array['North','South','East','West','Central'])[1 + ((i-1) / 50) % 5],
       'Cluster ' || (1 + (i-1) / 50),
       '00000000-0000-0000-0000-000000000001',
       (select id from profiles where employee_code = 'MNT'    || lpad((1 + (i-1)/50)::text,3,'0')),
       (select id from profiles where employee_code = 'RM-MGR' || lpad((1 + (i-1)/50)::text,3,'0')),
       (select id from profiles where employee_code = 'HR'     || lpad((1 + ((i-1)/50) % 5)::text,3,'0')),
       '2026-10-05'
from generate_series(1,1000) i;

-- Leadership viewer for the business case dashboard
insert into profiles(employee_code, full_name, email, role)
values ('LDR001','Head – Corporate Banking','cbhead@bank.example','leadership');
