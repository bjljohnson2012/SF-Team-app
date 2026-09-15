# GTM — Team Johnson: Project Handoff & Status

Living reference for the in-platform GTM/Sales tooling built on the `euna` **production** org
(`00D1I000001VBDGUA4`, user `benjamin.johnson@eunasolutions.com`). Read this first to pick up
where the last session left off.

Last updated: 2026-09-14.

---

## 1. What this is

Two Lightning apps of AE/director sales tooling, all custom LWC + Apex, deployed directly to prod:

- **GTM - Team Johnson** app — the main workspace. Nav (in order): **Main → Sales Performance → Sales Tools → Admin**.
- **Sales Tools** app — a standalone app whose landing tab is the same **Sales Tools** grid hub.

### Tabs / areas
| Nav label | Tab API name | LWC | What it does |
|---|---|---|---|
| Main | `Team_Opportunity_Insights` | `teamOpportunityInsights` | Director-view opportunities with a "Tell me about this opportunity" Claude summary. |
| Sales Performance | `Forecasting_Hub` (label "Sales Performance") | `forecastHub` | Forecast Cockpit: Forecast (Call Summary/Current/Next/Pull-Ins/Hygiene), Pipeline (Created/Open/Closed-Won), Conversion (Win Rate Truth/AE-by-AE/Problems). Chart.js dashboards, manual call inputs, per-section Claude insight, pricing-review Done/Not-done column. |
| Sales Tools | `Sales_Tools_Home` (label "Sales Tools") | `salesTools` | Grid hub of tools; opens the Pricing Review Checklist inline. |
| Pricing Review Checklist | `Pricing_Review_Checklist` | `pricingReviewTool` | The pricing-review tool (see §4). Rendered inside the Sales Tools hub. |
| Admin | `Sales_Perf_Admin` (label "Admin") | `salesPerfAdmin` | Access admin: who can open the app, assign/remove users at Full or View-only role, per-tab/activity matrix. |

---

## 2. Components (source of truth = this branch)

- **Apex** (`team-app/main/default/classes/`):
  - `CockpitForecastController` — Sales Performance data + AI (`load`, `getForecastSummary`, `getCreatedPipeline`, `getConversion`, `getWinRateTruth`, `getAeConversion`, `getProblems`, `getClosedWon`, `setInCall`, `setOverride`, `applyDefaultPicks`, `analyzePerformance`, and the Admin methods `getAccessMatrix`/`assignAccess`/`revokeAccess`). Pulls the pricing-review Done flag via `PricingReviewController.reviewedOppIds`.
  - `CockpitConstants`, `CockpitRosterService`, `CockpitScoreService` — Euna canon (filters, stage weights, roster resolution, scoring).
  - `PricingReviewController` — the pricing-review tool controller (see §4).
  - `DocxZip` — pure-Apex ZIP writer (STORE method + CRC32) used to assemble the `.docx` package.
  - `AnthropicService` — thin wrapper over the Anthropic Messages API via the `anthropic_api` Named Credential; model `claude-sonnet-5`; `complete(prompt[, model, maxTokens])`.
  - `TeamOpportunityController` — Main tab data + LLM summary.
  - Each has a `*Test` class.
- **LWC** (`team-app/main/default/lwc/`): `teamOpportunityInsights`, `forecastHub`, `salesTools`, `pricingReviewTool`, `salesPerfAdmin`.
- **Tabs**: `Team_Opportunity_Insights`, `Forecasting_Hub`, `Sales_Tools_Home`, `Pricing_Review_Checklist`, `Sales_Perf_Admin`.
- **Apps**: `GTM_Team_Johnson`, `Sales_Tools`.
- **Opportunity custom fields**: `Cockpit_In_Call__c` (Checkbox), `Cockpit_Class_Override__c` (Picklist HI/MD/EX), `Cockpit_Override_Note__c` (Text), `Pricing_Review_Answers__c` (Long Text Area — JSON of the 24 answers), `Pricing_Review_Override__c` (Picklist Done/Not Done).
- **Static resource**: `chartjs` (Chart.js 4.5.0 UMD — CSP requires a static resource, not CDN).
- **Permission sets** — **NOT committed** (this is a public repo). They live only in the local `force-app/main/default/permissionsets/` (gitignored) and in the org:
  - `GTM_Team_Johnson_Access` — Full access: both apps, all tabs, all four Apex classes, edit FLS on the 3 Cockpit fields + both Pricing_Review fields.
  - `GTM_Team_Johnson_Viewer` — View-only: same apps/tabs/apex + **read-only** Cockpit fields (no forecast edit) + edit on the Pricing_Review fields (so viewers can run checklists on their own deals). No Manage Users, so viewers cannot assign users.

> If you re-clone, the permission sets must be re-created/retrieved from the org — they are not in git.

---

## 3. Integrations & data

- **Anthropic (Claude)** — via Named Credential `anthropic_api` (injects `x-api-key` + `anthropic-version`). Model `claude-sonnet-5`. Used by the Main summary, the Sales Performance insight buttons, and the Pricing Review pre-fill.
- **Gong** — `Gong__Gong_Call__c`. Pricing-review context includes non-private, non-Internal calls (Scope is often `Unknown` in this org — do **not** filter to `External` only), pulling `Gong__Call_Brief__c` + `Gong_Transcript__c`.
- **Reference intelligence** — the uploaded `euna-salesforce-guide.skill` (a zip of 18 `references/*.md` field-map docs: `account-intelligence.md`, `customer-data.md`, `opportunity-intelligence.md`, `rfp-data.md`, `soql-and-apex-gotchas.md`, …). Used for the comparables/quote queries. Key facts: customer = `Account.RecordType.DeveloperName = 'Customer_EUNA'`; active contract ARR = `Contract.ARR_Rollup__c`; solution = `Contract.EUNA_Solution_Name_Formula__c`/`EUNA_Solution_Lookup__c`.
- **Account budget fields** (K12 example, all real on `001I9000005awS3IAI` Rochester): `AnnualRevenue` = "Latest Operating Budget", `Total_Budget_bf__c`, `Student_Count__c`, `NumberOfEmployees`, `Industry` (Vertical), `Sub_Vertical__c`, `Fiscal_Year_Start_Month__c`, `Operating_Budget_Year__c` (Number), `Recent_Budget_Trends__c` (Long Text), `Current_Budgeting_system__c`.

---

## 4. Pricing Review Checklist tool (most-iterated feature)

`pricingReviewTool` LWC + `PricingReviewController` + `DocxZip`.

- Lists open **new-business** deals **≥ $30K ARR**, scoped by role: a **director** defaults to their team's deals (toggle "Just me"); an **AE** sees only their own. Search box (account/AE/stage), sortable columns (ARR/size, close date, review status, stage), a clickable link to each opportunity, and a per-row **Override** (Auto/Done/Not done → `Pricing_Review_Override__c`).
- **AI pre-fill** (`draftAnswers`): on selecting a deal, Claude drafts all **24** checklist questions from the opportunity's context — Account entity profile (Q1/Q7 budget/size), existing Euna relationships (Q3), recent activity, **Gong** brief+transcript (Q4/Q5/Q9/Q16/Q17), **comparable customers'** ARR (Q6), and **quote line items** (Q21/Q24). Answers it can't source directly are still filled but **prefixed `INFERRED:`** for the AE to verify; `[No data …]` is a last resort. Bulk call ~30s; resilient JSON parse recovers from truncation (max_tokens 8192).
- **Per-question controls**: **Try again** (regenerate one question, ~2s) and **Expand** (`draftOne`).
- **Complete** (`createReview`): persists the 24 answers as JSON on `Pricing_Review_Answers__c` and attaches a **real branded `.docx`** (WordprocessingML via `DocxZip`) to the opportunity's **Files**. Saved answers are re-viewable on the tool page ("View responses"); completion status flows to the Sales Performance dashboard.
- **UI gotchas that bit us** (avoid regressions): native `<textarea value={x}>` does NOT render in LWC — use `lightning-textarea` (or bind value as element text content and render fields only after answers load). Auto-scroll to the builder was hiding the top-of-page error banner; errors are now shown inside the form.

Spec references (uploaded skills): `pricing-review-checklist v2.skill` (24 questions, ≥$30K, branded doc) and `euna-salesforce-guide.skill` (field map).

---

## 5. Deploy history (prod, direct-CLI under the now-expired carve-out)

All recorded in `docs/EXCEPTIONS.md` on branch `cursor/record-deploy-exception-91f8` (PR #2). Most recent first:

| Date | What | Quick-deploy job |
|---|---|---|
| 2026-09-14 | Real `.docx` output + reference-intelligence context (Account budget, comparables, quotes) | `0AfOL000003SWEX0A4` |
| 2026-09-14 | Fill all 24 with INFERRED marking + truncation-recovery | `0AfOL000003SU7t0AG` |
| 2026-09-14 | Include Unknown-scope Gong calls (fix over-frequent "No data") | `0AfOL000003ST6z0AG` |
| 2026-09-12 | Prefill render fix (lightning-textarea) + per-question Try again/Expand | `0AfOL000003SEhR0AW` |
| 2026-09-12 | Sales Tools hub tab + "Pricing Review Checklist" rename + prefill UX | `0AfOL000003SEUX0A4` |
| 2026-09-12 | Sorting + view-only role (`GTM_Team_Johnson_Viewer`) | `0AfOL000003SEEP0A4` |
| 2026-09-12 | Admin tab assign/remove users | `0AfOL000003SC7l0AG` |
| 2026-09-11 | Pricing Review scope/search/override + GTM app tab | `0AfOL000003SBEv0AO` |
| 2026-09-11 | Pricing Review opportunity link | `0AfOL000003SBoP0AW` |
| 2026-09-11 | Pricing Review AI prefill + saved responses + dashboard column + Admin-tab crash fix | `0AfOL000003SAyn0AG` |
| ≤2026-09-11 | Forecast Cockpit build-out (Sales Performance area, charts, Problems/Hygiene, manual call input, Admin tab) | multiple — see EXCEPTIONS.md |

---

## 6. Governance & how to deploy (IMPORTANT)

- Read `AGENTS.md` first. Prod is **read-only by default**; real deploys go **Branch → PR → euna-salesforce CI/CD pipeline** with a human approval.
- The time-boxed **direct-CLI carve-out EXPIRED 2026-09-11**. Everything above shipped via `sf project deploy validate` → `sf project deploy quick` under that carve-out (org owner authorized each). **Going forward, route through the pipeline.**
- If a direct deploy is ever authorized again: `validate` (check-only) → confirm clean → `quick` on that job id (never `deploy start`), then record it in `docs/EXCEPTIONS.md`. Always do the pre-deploy retrieve/re-diff — the org is shared and other admins deploy concurrently (this session hit a ~1.5h queue block behind another admin's deploy).
- Deploys are validated with `RunSpecifiedTests` (e.g. `PricingReviewControllerTest`, `CockpitForecastControllerTest`).

---

## 7. Dev environment & workflow

- SFDX project: `sfdx-project.json` has package dirs `team-app` (default, committed) and `force-app` (permsets only, gitignored). Source API 67.0; classes at 62.0.
- Org is authenticated as alias **`euna`** (`sf org display -o euna`). **`euna` = production**, `euna-full`/`EUNA-FULL` = sandbox — always pass `-o` explicitly.
- Branches / PRs:
  - `cursor/team-opp-insights-91f8` → **PR #3** (all app code). ← main working branch.
  - `cursor/record-deploy-exception-91f8` → **PR #2** (`docs/EXCEPTIONS.md`).
- Testing pattern this project uses: verify via read-only SOQL + anonymous Apex (e.g. `draftAnswers(<oppId>)`) and standalone HTML/`.docx` previews screenshotted with headless Chrome. The live org UI is behind an SSO "change password" wall, so in-browser walkthroughs haven't been possible — validate via Apex + artifacts instead. `.docx` output is validated locally with `python-docx`.

Handy sample record: **Rochester City School District** — Opp `006OL00000g35fjYAA`, Account `001I9000005awS3IAI` (has Gong transcript, 306 activities, 2 Quotes, full budget fields → best end-to-end test deal).

---

## 8. Known limitations / candidate next steps

- **Pipeline migration**: move deploys off direct-CLI onto euna-salesforce CI/CD (carve-out expired; queue contention is real).
- **Pre-fill latency** (~30s bulk) is inherent to the Claude call over rich context; per-question Try again (~2s) is the fast path. Could move bulk pre-fill to async/queueable with progress if it becomes a problem.
- **In-org UI verification** blocked by the SSO password wall — no Selenium/computer-use walkthroughs yet.
- **Comparables (Q6)** currently match on vertical (`Account.Industry`) + active ARR; could be tightened to same-product via `EUNA_Solution_Lookup__c` if desired.
- **Reference intelligence** could be expanded (CSM/health/tier fields from the field map) for a fuller account picture.
- Consider committing a sanitized permission-set template (the real ones stay out of the public repo).
