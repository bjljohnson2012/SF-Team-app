# Deployment Exceptions Log

Records of direct-CLI production deploys made under the time-boxed carve-out in `AGENTS.md`
(added 2026-09-08, expires 2026-09-11). Each entry lists the components, the validated job id,
the quick-deploy job id, the test level, and the review verdict.

## 2026-09-10 — GTM - Team Johnson app (initial deploy)

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (net-new, 2):**
  - `CustomApplication:GTM_Team_Johnson`
  - `FlexiPage:GTM_Team_Johnson_Home`
- **Pre-deploy freshness retrieve:** both reported "cannot be found" in prod → clean net-new deploy, no drift to overwrite.
- **Validated job id:** `0AfOL000003Rlif0AC` — `RunSpecifiedTests` (`AccountGradeOverrideHandlerTest`, 10 tests, 0 failures); 2/2 components, 0 errors. A specified passing test was used because the package contains no Apex (so `RunRelevantTests` runs 0 tests and is not quick-deployable) and a full `RunLocalTests` validation fails on pre-existing, unrelated org test failures.
- **Quick-deploy job id:** `0AfOL000003RlkH0AS` — Succeeded, `checkOnly: false`, 2/2 components created, 0 errors.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick` (never `deploy start`).
- **Review verdict:** Manual diligence review against `AGENTS.md` — **PASS** (reuses existing `Quick_Task_Kanban`/`Quick_Task_Create`/`Quick_Task__c` tabs and the `quickTaskKanban` LWC; no new object/field, Account field cap untouched; no hardcoded IDs/URLs; both components carry populated `<description>`; only the Team Johnson app touched). **Formal `/sf-review` NOT run** — the EUNA `.claude/sf-review-references/` checklists are not present in this public repo.
- **Approved by:** org owner (benjamin.johnson), explicit instruction to deploy.
- **Post-deploy verification:** retrieve of both components from prod succeeded (they were absent immediately before deploy).
- **Rollback:** net-new components with no dependents created; rollback = destructive delete of `CustomApplication:GTM_Team_Johnson` and `FlexiPage:GTM_Team_Johnson_Home`.

## 2026-09-10 — GTM - Team Johnson app access (permission set)

Follow-up: the initial deploy created the app but included no profile/permission-set assignment, so it was "invalid or inaccessible" even to the System Administrator. This grants access.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Component (net-new, 1):** `PermissionSet:GTM_Team_Johnson_Access` — `applicationVisibilities` for `GTM_Team_Johnson` + `tabSettings` (Visible) for `Quick_Task_Kanban`, `Quick_Task_Create`, `Quick_Task__c`. No object/field permissions. Authored in the gitignored `force-app/` (permission sets are not committed to this public repo).
- **Pre-deploy check:** no existing `PermissionSet` named `GTM_Team_Johnson_Access` (net-new; no grants revoked).
- **Validated job id:** `0AfOL000003Rnir0AC` — `RunSpecifiedTests` (`AccountGradeOverrideHandlerTest`, 10 tests, 0 failures); 1/1, 0 errors.
- **Quick-deploy job id:** `0AfOL000003RnkT0AS` — Succeeded, `checkOnly: false`, 1/1 created, 0 errors.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick` (never `deploy start`).
- **Review verdict:** Manual diligence review against `AGENTS.md` — **PASS** (net-new permission set; reuses existing app/tabs; no object/field grants; smallest change to grant access). **Formal `/sf-review` NOT run** — EUNA checklists not present in this public repo.
- **Approved by:** org owner (benjamin.johnson), explicit instruction ("go with option two").
- **Assignment:** `GTM_Team_Johnson_Access` assigned to `benjamin.johnson@eunasolutions.com` (`PermissionSetAssignment 0PaOL00000npP3S0AU`).
- **Post-deploy verification:** `AppDefinition` for `GTM_Team_Johnson` now returns to the user (`DurableId 06mOL000001scEDYAY`; was hidden before); `SetupEntityAccess` now grants the app TabSet via this permission set.
- **Rollback:** remove the assignment and/or destructive-delete `PermissionSet:GTM_Team_Johnson_Access` (no other metadata depends on it).

## 2026-09-10 — Team Opportunity Insights (Apex + LWC + LLM)

First "inference dashboard" slice on the GTM - Team Johnson home page: director-view opportunity list with a "Tell me about this opportunity" Claude summary.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (7):** `ApexClass:AnthropicService`, `ApexClass:TeamOpportunityController`, `ApexClass:AnthropicServiceTest`, `ApexClass:TeamOpportunityControllerTest`, `LightningComponentBundle:teamOpportunityInsights`, `FlexiPage:GTM_Team_Johnson_Home` (updated to host the new LWC instead of `quickTaskKanban`), `CustomApplication:GTM_Team_Johnson` (unchanged). Source committed on branch `cursor/team-opp-insights-91f8` (PR #3).
- **Integration:** callout to `callout:anthropic_api/v1/messages` via the existing `anthropic_api` Named Credential (endpoint + `x-api-key` secret + `anthropic-version` supplied by the credential; no secret in code). Model `claude-sonnet-5`.
- **Validated job id:** `0AfOL000003RpBB0A0` — `RunSpecifiedTests` (`AnthropicServiceTest`, `TeamOpportunityControllerTest`); 7/7, 10 tests, 0 failures; coverage `AnthropicService` 100%, `TeamOpportunityController` 89%.
- **Quick-deploy job id:** `0AfOL000003RpHd0AK` — Succeeded, `checkOnly: false`, 7/7, 0 errors.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick` (never `deploy start`).
- **Review verdict:** Manual diligence review against `AGENTS.md` — **PASS** (`with sharing` + `WITH SECURITY_ENFORCED`; role hierarchy computed dynamically, no hardcoded ids; secret via Named Credential; reuses existing opportunity data; tests with `HttpCalloutMock` ≥85% per class). Known follow-up: move the model id / `max_tokens` from an Apex constant into Custom Metadata (no-hardcoded-config guidance). **Formal `/sf-review` NOT run** — EUNA checklists not present in this public repo.
- **Approved by:** org owner (benjamin.johnson), "start with something basic that can be production ready".
- **Pre-deploy live check:** `claude-3-5-sonnet-latest` returned 404 (not available); listed account models and confirmed `claude-sonnet-5` returns 200 before deploying.
- **Post-deploy verification:** anonymous Apex ran `getDirectorOpportunities()` (200 opps) and `summarizeOpportunity()` (real Claude summary) against prod; prod `GTM_Team_Johnson_Home` flexipage confirmed hosting `teamOpportunityInsights`.
- **Rollback:** revert the flexipage to `quickTaskKanban` and destructive-delete the four Apex classes + the LWC (no other metadata depends on them).

## 2026-09-10 — GTM - Team Johnson app cleanup + Apex access

Removes the Quick Task tabs from the app (so it lands on the Team Opportunity Insights home) and grants Apex access so the home LWC runs for assigned users.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (2, changed):** `CustomApplication:GTM_Team_Johnson` (removed tabs `Quick_Task_Kanban`, `Quick_Task_Create`, `Quick_Task__c`; home override to `GTM_Team_Johnson_Home` retained), `PermissionSet:GTM_Team_Johnson_Access` (dropped the three tab settings; added `classAccesses` for `TeamOpportunityController` and `AnthropicService`; app visibility retained).
- **Validated job id:** `0AfOL000003Rpnt0AC` — `RunSpecifiedTests` (`AccountGradeOverrideHandlerTest`); 2/2, 0 errors.
- **Quick-deploy job id (from validate above):** Succeeded, `checkOnly: false`, 2/2 changed, 0 errors.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick` (never `deploy start`).
- **Review verdict:** Manual diligence review against `AGENTS.md` — **PASS** (app now navigation-free, lands on home; permission set adds only Apex execute access for the two feature classes). **Formal `/sf-review` NOT run** — EUNA checklists not present in this public repo.
- **Approved by:** org owner (benjamin.johnson), "make all new tabs visible... I don't need the Task Kanban / New Task / Quick Tasks tabs".
- **Post-deploy verification:** retrieve of `CustomApplication:GTM_Team_Johnson` shows 0 `<tabs>` (home override intact); `SetupEntityAccess` shows 2 ApexClass grants under `GTM_Team_Johnson_Access`.
- **Rollback:** re-add the three `<tabs>` to the app; remove the two `classAccesses` from the permission set.

## 2026-09-10 — GTM - Team Johnson "Main" nav tab

Fixes the "This app doesn't have any navigation items" error: a Lightning app requires at least one nav tab, so the Home-override-only app failed to load. Adds a Lightning component tab (label "Main") hosting the Team Opportunity Insights LWC.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (4):** `CustomTab:Team_Opportunity_Insights` (new; label "Main"; `lwcComponent` teamOpportunityInsights), `LightningComponentBundle:teamOpportunityInsights` (added `lightning__Tab` target), `CustomApplication:GTM_Team_Johnson` (added `<tabs>Team_Opportunity_Insights</tabs>`; home override retained), `PermissionSet:GTM_Team_Johnson_Access` (added tab visibility).
- **Validated job id:** `0AfOL000003Rqf70AC` — `RunSpecifiedTests` (`AccountGradeOverrideHandlerTest`); 4/4, 0 errors.
- **Quick-deploy:** Succeeded, `checkOnly: false`, 4/4 changed, 0 errors.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick`.
- **Review verdict:** Manual diligence review — **PASS** (component tab reuses the existing LWC; permission set adds only that tab's visibility). Formal `/sf-review` NOT run (checklists absent from public repo).
- **Approved by:** org owner (benjamin.johnson), "There needs to be a tab just called Main / or home".
- **Post-deploy verification:** app retrieve shows `<tabs>Team_Opportunity_Insights</tabs>`; `TabDefinition` returns the tab (label "Main") as visible to the user; UI screenshot not captured (CLI frontdoor blocked by the org's SSO password-change wall).
- **Rollback:** remove the tab from the app + destructive-delete `CustomTab:Team_Opportunity_Insights` (would reintroduce the no-nav-items error unless another tab is added).

## 2026-09-10 — Forecasting Hub tab (Cockpit Phase B, read-only)

Adds a "Forecasting Hub" tab to the GTM - Team Johnson app: the director's team pipeline with deterministic evidence scoring and a modeled-call number (guide Phase B; the stateful MEDDPICC/batch/override/cohort layers are deferred to the sandbox build).

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (11):** ApexClasses `CockpitConstants`, `CockpitScoreService`, `CockpitRosterService`, `CockpitForecastController` (+ 3 test classes); `LightningComponentBundle:forecastHub`; `CustomTab:Forecasting_Hub` (label "Forecasting Hub"); `CustomApplication:GTM_Team_Johnson` (added the tab); `PermissionSet:GTM_Team_Johnson_Access` (tab + Apex access). No schema changes, no custom objects, no batch.
- **Validated job id:** `0AfOL000003Rr890AC` — `RunSpecifiedTests` (`CockpitScoreServiceTest`, `CockpitRosterServiceTest`, `CockpitForecastControllerTest`); 11/11, 9 tests, 0 failures; coverage `CockpitConstants` 100%, `CockpitForecastController` 94%, `CockpitRosterService` 100%, `CockpitScoreService` 91%.
- **Quick-deploy:** Succeeded, `checkOnly: false`, 11/11, 0 errors.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick`.
- **Review verdict:** Manual diligence review — **PASS** (`with sharing` + `WITH USER_MODE`; canon filters (`Euna_Sale`, new-business types, ARR `_Num__c`) sourced from `CockpitConstants`; 2-level roster with non-AE exclusion; heap-safe (no synchronous MEDDPICC read per guide P3); read-only formula/system fields handled). Dropped `Roll_Up_Forecast_bf__c` from the query (FLS-restricted, unused in UI). Formal `/sf-review` NOT run — EUNA checklists absent from this public repo.
- **Approved by:** org owner (benjamin.johnson), chose option B (safe prod subset).
- **Post-deploy verification:** anonymous Apex ran `load()` as the director — team 6, 189 scored deals, mix HI:0/MD:47/EX:142, modeled call $518,514.60; app shows both `Team_Opportunity_Insights` and `Forecasting_Hub` tabs; `TabDefinition` returns "Forecasting Hub" as visible.
- **Rollback:** remove `Forecasting_Hub` from the app tabs and destructive-delete the tab, LWC, and the four Cockpit classes (+ tests).

## 2026-09-10 — Forecasting Hub redesign to match the cockpit UI

Rebuilds the Forecasting Hub LWC to match the Forecast Cockpit's visuals and process: indigo/tricolor branding, tabbed nav (Summary, Current Qtr, Next Qtr, Pull-Ins), class pills (HI/MD/EX), forecast-band pills (Commit/Most Likely/Best Case/Pipeline/Omitted), a strike-rate weights bar, a "call builder" (tick deals into the call), seeded judgment overrides and pull-in cases ported from the cockpit.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (3, changed):** `ApexClass:CockpitForecastController` (added `ForecastCategoryName` band + quarter bucket A/B/C; returns raw scored deals + quarter labels for client-side weighting), `ApexClass:CockpitForecastControllerTest`, `LightningComponentBundle:forecastHub` (full multi-tab cockpit UI: js/html/css).
- **Validated job id:** `0AfOL000003RtEn0AK` — `RunSpecifiedTests` (`CockpitForecastControllerTest`); 3/3, 2 tests, 0 failures; `CockpitForecastController` coverage 95%.
- **Quick-deploy:** Succeeded, `checkOnly: false`, 3/3 changed, 0 errors.
- **Review verdict:** Manual diligence review — **PASS** (UI-only + controller field additions; still `with sharing` + `WITH USER_MODE`; scoring unchanged; SEED/PULL are display constants in the LWC). In-session weights/picks/class overrides are not persisted (persistence = Phase A records). Formal `/sf-review` NOT run — checklists absent from public repo.
- **Approved by:** org owner (benjamin.johnson), "it didn't match the visuals and process".
- **Post-deploy verification:** anonymous Apex `load()` — Q3 2026 | Q4 2026; buckets Current 36 / Next 97 / +1 57; bands Commit 6, Most Likely 16, Best Case 21, Pipeline 131; a rendered visual preview of the LWC markup+CSS confirmed the cockpit look (header, tricolor bar, weights bar, tabs, builder, class/band pills).
- **Rollback:** revert `forecastHub` and `CockpitForecastController` to the prior commit on `cursor/team-opp-insights-91f8`.

## 2026-09-10 — Forecasting Hub: persistence + filters + 2 analytics tabs (increment 1)

Toward a 100%-faithful cockpit. Adds persisted fill-in fields, AE/class filters, and the Created Pipeline + Conversion Metrics tabs. (Win Rate Truth + AE-by-AE = increment 2.)

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (7):** 3 Opportunity fields — `Cockpit_In_Call__c` (Checkbox), `Cockpit_Class_Override__c` (Picklist HI/MD/EX), `Cockpit_Override_Note__c` (Text 255); `ApexClass:CockpitForecastController` (+ `setInCall`, `setOverride`, `applyDefaultPicks`, `getCreatedPipeline`, `getConversion`; reads persisted fields); `ApexClass:CockpitForecastControllerTest`; `LightningComponentBundle:forecastHub` (persisted checkbox/override wiring, AE dropdown + class chips, 2 analytics tabs); `PermissionSet:GTM_Team_Johnson_Access` (FLS on the 3 fields).
- **Validated job id:** `0AfOL000003RvoT0AS` — `RunSpecifiedTests` (`CockpitForecastControllerTest`); 7/7, 5 tests, 0 failures; controller coverage 94%.
- **Quick-deploy:** Succeeded, `checkOnly: false`, 7/7, 0 errors.
- **Review verdict:** Manual diligence — **PASS** (`with sharing`; writes via `AccessLevel.USER_MODE`; new fields non-tracked; analytics are aggregate/read-only). Formal `/sf-review` NOT run (checklists absent from public repo).
- **Approved by:** org owner (benjamin.johnson), "build it all in prod".
- **Post-deploy verification:** anon Apex — setInCall/setOverride persisted (`true | HI | note`) then cleared; getCreatedPipeline 9 quarters; getConversion real band win-rates (Commit 96.5%, Best Case 23.3%, Pipeline 7.3%).
- **Rollback:** revert `forecastHub`/`CockpitForecastController` to prior commit; the 3 fields can remain (harmless) or be destructive-deleted.

## 2026-09-10 — Forecasting Hub: Win Rate Truth + AE-by-AE (increment 2)

Completes the four analytics tabs. Adds the creation-cohort win-rate model and per-AE conversion with loss-root diagnosis.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (3, changed):** `ApexClass:CockpitForecastController` (+ loss-reason->root map, `getWinRateTruth` cohort model with 4 denominators, `getAeConversion`), `ApexClass:CockpitForecastControllerTest`, `LightningComponentBundle:forecastHub` (Win Rate Truth + AE-by-AE tabs).
- **Validated job id:** `0AfOL000003RvwX0AS` — 3/3, 5 tests, 0 failures; controller coverage 94%.
- **Quick-deploy:** Succeeded, `checkOnly: false`, 3/3, 0 errors.
- **Review verdict:** Manual diligence — **PASS** (read-only aggregate analytics; `with sharing`). Formal `/sf-review` NOT run.
- **Approved by:** org owner (benjamin.johnson), "build it all in prod".
- **Post-deploy verification:** anon Apex — getWinRateTruth team row created 646 / won 121 / cohortWR 18.7% / contestedWR 31.0% / qualYield 60.4%; getAeConversion 6 reps with win rates 8.6%-44.4% and dominant loss root ENGAGE.
- **Rollback:** revert `forecastHub`/`CockpitForecastController` to prior commit.

## 2026-09-11 — Sales Performance restructure: sub-tabs, charts, Problems/Hygiene, AI

Reorganizes the Forecasting Hub into a "Sales Performance" area with Forecast / Pipeline / Conversion sections and sub-tabs, adds Chart.js dashboards, Problems + Hygiene, and Claude-powered insight buttons.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (5):** `StaticResource:chartjs` (Chart.js 4.5.0 UMD); `ApexClass:CockpitForecastController` (+ `getProblems`, `getClosedWon`, `analyzePerformance` calling `AnthropicService`); `ApexClass:CockpitForecastControllerTest` (+ HttpCalloutMock AI test); `LightningComponentBundle:forecastHub` (2-level nav: Forecast[Summary/Current/Next/Pull-Ins/Hygiene], Pipeline[Created/Open/Closed-Won + charts], Conversion[Win Rate Truth/AE-by-AE/Problems + charts], AI insight button per section); `CustomTab:Forecasting_Hub` (label -> "Sales Performance").
- **Validated job id:** `0AfOL000003S60j0AC` — 5/5, 6 tests, 0 failures; controller coverage 91%.
- **Quick-deploy:** Succeeded, `checkOnly: false`, 5/5, 0 errors.
- **Review verdict:** Manual diligence — **PASS** (Chart.js as static resource per guide CSP note; AI via existing `anthropic_api` Named Credential; analytics read-only). Formal `/sf-review` NOT run.
- **Approved by:** org owner (benjamin.johnson), "problems + hygiene and chart.js are more important... more AI... sub-tabs".
- **Post-deploy verification:** anon Apex — `analyzePerformance('conversion')` returned a real Claude insight ("Best Case ARR win rate 6.9% identical to raw Pipeline..."); getProblems 14 loss reasons (Ghosted 267); getClosedWon 83 deals; rendered LWC preview confirmed the section/sub-tab nav + a live Created-vs-Booked bar chart.
- **Note:** MEDDPICC batch intentionally skipped per owner. Carve-out expired 2026-09-11; further changes go via the euna-salesforce pipeline.
- **Rollback:** revert `forecastHub`/`CockpitForecastController` to prior commit; static resource + tab label can remain.

## 2026-09-11 — Forecast Summary: manual call input + evidence build

Adds the manual Q3/Q4 Call inputs and the Summary that scores the typed call against live data (booked-to-date, still-to-find, gap-to-call, hand-built, and the how-the-number-builds table).

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (3, changed):** `ApexClass:CockpitForecastController` (+ `getForecastSummary`: booked-to-date by quarter, quarter clock, trailing in-quarter new-pipeline estimate, median cycle), `ApexClass:CockpitForecastControllerTest`, `LightningComponentBundle:forecastHub` (Q3/Q4 Call inputs; Summary cards + build table).
- **Validated job id:** `0AfOL000003S9Mn0AK` — 3/3, 6 tests, 0 failures; coverage 91%.
- **Quick-deploy:** Succeeded, `checkOnly: false`, 3/3, 0 errors.
- **Post-deploy verification:** getForecastSummary live — Q3 2026, booked 17/$286,805 (matches reference exactly), days-left 19, 79% elapsed, new-pipeline $126K, median cycle 116d; LWC preview confirmed the call inputs + build table.
- **Carve-out note:** This is on/at the 2026-09-11 expiry of the AGENTS.md direct-CLI carve-out. Further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert `forecastHub`/`CockpitForecastController` to prior commit.

## 2026-09-11 — Admin (access) tab

Adds a small Admin tab to the GTM - Team Johnson app: who can access the app and what activities they can perform, derived live from the permission set.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (6):** `ApexClass:CockpitForecastController` (+ `getAccessMatrix`: PermissionSetAssignment + FieldPermissions + SetupEntityAccess), `ApexClass:CockpitForecastControllerTest`, `LightningComponentBundle:salesPerfAdmin` (new), `CustomTab:Sales_Perf_Admin` (label "Admin"), `CustomApplication:GTM_Team_Johnson` (3rd tab), `PermissionSet:GTM_Team_Johnson_Access` (tab visibility).
- **Validated job id:** `0AfOL000003S9Y50AK` — 6/6, 7 tests, 0 failures; coverage 91%.
- **Quick-deploy:** Succeeded, `checkOnly: false`, 6/6, 0 errors.
- **Post-deploy verification:** getAccessMatrix live — 1 user (Ben Johnson, System Administrator, active), editInCall/override/apex all true, activities enumerated; app now shows Main, Sales Performance, Admin tabs.
- **Carve-out note:** at/after the 2026-09-11 expiry; further changes should route through the euna-salesforce pipeline.
- **Rollback:** remove Sales_Perf_Admin from the app + destructive-delete the tab and salesPerfAdmin LWC.

## 2026-09-11 — Pricing Review View Checklist Tool (Sales Tools app) + Admin-tab crash fix

Two changes in one deploy, both authorized by the org owner ("let's deploy both"):
1. New **Sales Tools** app with the **Pricing Review View Checklist Tool** — for open new-business deals ≥ $30K ARR, Claude pre-fills the 24-question pricing checklist from the opportunity's fields, existing Euna relationships, activity and Gong calls; the AE reviews/edits and clicks Complete, which persists the answers and attaches a branded Euna Word doc to the opportunity's Files. Saved responses are viewable on the tool page, and Done/Not-done shows on the Sales Performance dashboard.
2. Fix for the **Admin (salesPerfAdmin)** tab runtime crash (`Cannot read properties of undefined (reading 'permSet')`) — the header referenced `{info.permSet}` outside the `lwc:if={info}` guard; replaced with a null-safe `permSetName` getter.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (10):** `CustomField:Opportunity.Pricing_Review_Answers__c` (LongTextArea, persists the 24 answers as JSON; presence = review complete); `ApexClass:PricingReviewController` (new — `getReviewDeals`, `draftAnswers` [Gong/activity/relationship context → Claude], `createReview` [persist + attach doc], `getReview`, `reviewedOppIds`); `ApexClass:PricingReviewControllerTest` (new — HttpCalloutMock draft, persist+attach+read-back, null/empty paths); `ApexClass:CockpitForecastController` (+ `reviewDone` on the dashboard deal tables via `reviewedOppIds`); `LightningComponentBundle:pricingReviewTool` (new — prefill flow, Complete, View responses); `LightningComponentBundle:forecastHub` (Pricing-review Done/Not-done column on Current/Next tables); `LightningComponentBundle:salesPerfAdmin` (null-safe header fix); `CustomApplication:Sales_Tools` (new); `CustomTab:Pricing_Review_Checklist` (new, label "Pricing Review View Checklist Tool"); `PermissionSet:GTM_Team_Johnson_Access` (Sales_Tools app, Pricing_Review_Checklist tab, PricingReviewController class, FLS on Pricing_Review_Answers__c).
- **Validated job id:** `0AfOL000003S8li0AC` — `RunSpecifiedTests` (`PricingReviewControllerTest`, `CockpitForecastControllerTest`); 11/11, 0 failures.
- **Quick-deploy:** `0AfOL000003SAyn0AG` — Succeeded, `checkOnly: false`, 0 errors.
- **Review verdict:** Manual diligence — **PASS** (`with sharing`; only verified prod fields queried — the skill's `ARR__c`/`Contract_*_Date__c` on `Account_Solution_Relationship__c` don't exist here and were omitted; long-text field tested in Apex not SOQL WHERE; AI via existing `anthropic_api` Named Credential; doc write via ContentVersion/ContentDocumentLink; new field non-tracked, documented, FLS-gated). Formal `/sf-review` NOT run (checklists absent from public repo).
- **Approved by:** org owner (benjamin.johnson), "let's deploy both".
- **Pre-deploy drift check:** retrieve/re-diff of CockpitForecastController, forecastHub, salesPerfAdmin, GTM_Team_Johnson_Access — only trailing-newline differences, no concurrent prod edits.
- **Post-deploy verification:** anon Apex — `getReviewDeals()` returned 104 open deals ≥ $30K (top Rochester City School District, $161,788, director Ben Johnson, reviewDone=false); `Opportunity.Pricing_Review_Answers__c` describe = true. Real AI prefill (pre-deploy, live `AnthropicService`) on State of Minnesota returned grounded answers (Q2 partner referral, Q3 no existing relationship, Q16 grant-regulation driver, Q19 close date) with all unsupported questions flagged "[No data in Salesforce — AE to complete]". Admin tab fix confirmed via rendered preview with live access-matrix data.
- **Carve-out note:** at/after the 2026-09-11 expiry of the AGENTS.md direct-CLI carve-out; further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert `pricingReviewTool`/`PricingReviewController`/`forecastHub`/`salesPerfAdmin`/`CockpitForecastController` to prior commit; destructive-delete `Sales_Tools` app, `Pricing_Review_Checklist` tab, and the `Pricing_Review_Answers__c` field (or leave the field — harmless).

## 2026-09-11 — Pricing Review tool: role scope, search, status override + GTM app tab

Follow-ups to the Pricing Review View Checklist Tool, authorized by the org owner ("I authorize"):
1. Role-based default scope — directors see their team's ≥$30K open deals (toggle to "Just me"); AEs see their own (`getReviewData(scope)`).
2. Search bar (account / AE / stage) on the tool.
3. Manual status override — new `Pricing_Review_Override__c` picklist (Done/Not Done; blank = auto-derive); `setReviewStatus()`; `reviewedOppIds()` (dashboard) is override-aware.
4. Surfaced the "Pricing Review View Checklist Tool" tab inside the GTM - Team Johnson app nav (it remains its own Sales Tools app too).

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (6):** `CustomField:Opportunity.Pricing_Review_Override__c` (Picklist Done/Not Done, restricted); `ApexClass:PricingReviewController` (+ `getReviewData(scope)` [role-aware], `setReviewStatus`, override-aware `isDone`/`reviewedOppIds`; replaces `getReviewDeals`); `ApexClass:PricingReviewControllerTest` (+ override + setStatus validation); `LightningComponentBundle:pricingReviewTool` (search bar, My team / Just me toggle, per-row Override select); `CustomApplication:GTM_Team_Johnson` (+ `Pricing_Review_Checklist` tab); `PermissionSet:GTM_Team_Johnson_Access` (FLS on `Pricing_Review_Override__c`).
- **Validated job id:** `0AfOL000003SBDJ0A4` — `RunSpecifiedTests` (`PricingReviewControllerTest`); 5/5, 0 failures.
- **Quick-deploy:** `0AfOL000003SBEv0AO` — Succeeded, `checkOnly: false`, 0 errors.
- **Review verdict:** Manual diligence — **PASS** (`with sharing`; `override` reserved-word fix; restricted picklist; override write via id-only DML; test covers override forcing status both ways + null validation). Formal `/sf-review` NOT run (checklists absent from public repo).
- **Approved by:** org owner (benjamin.johnson), "I authorize".
- **Post-deploy verification:** anon Apex — `getReviewData('team')` isDirector=true, scope=team, 104 deals; `getReviewData('mine')` scope=mine, 0 deals (Ben owns no ≥$30K new-business deals); `Pricing_Review_Override__c` describe=true; GTM - Team Johnson app nav now Main → Sales Performance → Pricing Review → Admin.
- **Carve-out note:** past the 2026-09-11 expiry of the AGENTS.md direct-CLI carve-out; further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert `pricingReviewTool`/`PricingReviewController` and remove the `Pricing_Review_Checklist` tab from `GTM_Team_Johnson`; the `Pricing_Review_Override__c` field can remain (harmless) or be destructive-deleted.

## 2026-09-11 — Pricing Review tool: clickable opportunity link

Adds a clickable link to the opportunity record on the Pricing Review View Checklist Tool (deals-table account name plus the review/view panel headers), via a relative `/lightning/r/Opportunity/<id>/view` URL (no hardcoded org domain).

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (1):** `LightningComponentBundle:pricingReviewTool`.
- **Validated job id:** `0AfOL000003SBmn0AG` — `RunSpecifiedTests` (`CockpitRosterServiceTest`, LWC-only change); 2/2, 0 failures.
- **Quick-deploy:** `0AfOL000003SBoP0AW` — Succeeded, `checkOnly: false`, 0 errors.
- **Approved by:** org owner (benjamin.johnson), "Ship it".
- **Note:** republishing the bundle also resolved a stale-cached-component error some users saw ("No apex action available for PricingReviewController.getReviewDeals") after the earlier getReviewDeals->getReviewData rename; the deployed code was already correct, the error was a client cache.
- **Carve-out note:** past the 2026-09-11 expiry; further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert `pricingReviewTool` to the prior commit.

## 2026-09-11 — Admin tab: assign / remove users

Adds user management to the Sales Performance Admin tab: assign or remove the `GTM_Team_Johnson_Access` permission set directly from the tab, gated on the viewer's Manage Users / Assign Permission Sets permission.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (3, changed):** `ApexClass:CockpitForecastController` (+ `getAccessMatrix` returns `canManage` + assignable active Standard users; `assignAccess`/`revokeAccess` gated on `PermissionsManageUsers`/`PermissionsAssignPermissionSets`, duplicate-safe, DML-error handled); `ApexClass:CockpitForecastControllerTest` (+ assign→verify→idempotent→revoke→verify + null guard); `LightningComponentBundle:salesPerfAdmin` (assign-user picker + per-user Remove, shown only to managers; success/error notices).
- **Validated job id:** `0AfOL000003SBy50AG` — `RunSpecifiedTests` (`CockpitForecastControllerTest`); 8/8, 0 failures.
- **Quick-deploy:** `0AfOL000003SC7l0AG` — Succeeded, `checkOnly: false`, 0 errors.
- **Review verdict:** Manual diligence — **PASS** (privileged action gated by platform permission both in UI and server-side; assignment is a setup-object DML so no mixed-DML with the tool's data; picker limited to 200 active Standard users). Formal `/sf-review` NOT run (checklists absent from public repo).
- **Approved by:** org owner (benjamin.johnson), "go ahead".
- **Post-deploy verification:** anon Apex — `getAccessMatrix()` canManage=true, assigned=1, assignable=200 (sample: Aaron Digruccio, Customer Success); tabs list now includes Pricing Review View Checklist Tool.
- **Carve-out note:** past the 2026-09-11 expiry; further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert `CockpitForecastController`/`salesPerfAdmin` to the prior commit (removes the assign/revoke methods and UI); no schema to unwind.

## 2026-09-12 — Pricing Review sorting + Admin view-only role

Two changes, authorized by the org owner ("do it!"):
1. Sortable columns on the Pricing Review View Checklist Tool — size (ARR), close date, review status, and stage, click-to-sort with direction toggle.
2. A view-only access role. New `GTM_Team_Johnson_Viewer` permission set: app/tab/apex visibility + read-only Cockpit fields (no forecast edit) + pricing-tool field edit (create checklists on own deals). The Admin tab assign action now offers Full access vs View only; view-only users can open the app and run pricing reviews for their deals but cannot edit the forecast or assign users (no Manage Users).

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (5):** `PermissionSet:GTM_Team_Johnson_Viewer` (new, view-only); `ApexClass:CockpitForecastController` (`getAccessMatrix` reports per-user role; `assignAccess(userId, role)` enforces one role per user by dropping the other permset; `revokeAccess` removes both); `ApexClass:CockpitForecastControllerTest` (full -> switch to viewer -> revoke); `LightningComponentBundle:pricingReviewTool` (sortable headers); `LightningComponentBundle:salesPerfAdmin` (role selector on assign + Role column).
- **Validated job id:** `0AfOL000003SCMH0A4` — `RunSpecifiedTests` (`CockpitForecastControllerTest`); 8/8, 0 failures.
- **Quick-deploy:** `0AfOL000003SEEP0A4` — Succeeded, `checkOnly: false`, 0 errors.
- **Review verdict:** Manual diligence — **PASS** (view-only permset omits Cockpit field edit; assign gated on Manage Users both in UI and Apex; role switch is setup-object DML only; sorting is client-side). Formal `/sf-review` NOT run (checklists absent from public repo).
- **Approved by:** org owner (benjamin.johnson), "do it!".
- **Post-deploy verification:** anon Apex — both permission sets present (`GTM_Team_Johnson_Access`, `GTM_Team_Johnson_Viewer`); `getAccessMatrix()` users=1 (Ben, role "Full access"), canManage=true, assignable=200.
- **Carve-out note:** past the 2026-09-11 expiry; further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert `CockpitForecastController`/`salesPerfAdmin`/`pricingReviewTool` to the prior commit; the `GTM_Team_Johnson_Viewer` permission set can be left in place (harmless if unassigned) or destructive-deleted.

## 2026-09-12 — Sales Tools hub tab + Pricing Review Checklist rename + prefill UX

Authorized by the org owner ("deploy"):
1. Restructured the GTM - Team Johnson app nav to Main / Sales Performance / Sales Tools / Admin. New "Sales Tools" hub tab shows a grid of tool cards; selecting "Pricing Review Checklist" opens the tool inline. Standalone Sales Tools app lands on the same hub.
2. Renamed "Pricing Review View Checklist Tool" -> "Pricing Review Checklist" (card, header, tab label, component label).
3. Fixed the perceived "create checklist did nothing" issue: draftAnswers works but takes ~6-27s and the builder opened off-screen at page top; it now scrolls into view on select, and the AI call was sped up (max_tokens 4096->2048, Gong transcript 1800->1200, calls 3->2, tasks 10->8, context clip 24000->16000).

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (12):** `LightningComponentBundle:salesTools` (new hub); `CustomTab:Sales_Tools_Home` (new, label "Sales Tools", motif Custom57: Toolbox); `CustomApplication:GTM_Team_Johnson` + `CustomApplication:Sales_Tools` (nav -> Sales_Tools_Home); `CustomTab:Pricing_Review_Checklist` (label rename); `LightningComponentBundle:pricingReviewTool` (H1 rename, scroll-into-view); `ApexClass:PricingReviewController` (draftAnswers speedup); `ApexClass:CockpitForecastController` (tabs label string); `PermissionSet:GTM_Team_Johnson_Access` + `PermissionSet:GTM_Team_Johnson_Viewer` (Sales_Tools_Home tab visibility); test classes unchanged (recompiled).
- **Validated job id:** `0AfOL000003SERJ0A4` — `RunSpecifiedTests` (`PricingReviewControllerTest`, `CockpitForecastControllerTest`); 13/13, 0 failures.
- **Quick-deploy:** `0AfOL000003SEUX0A4` — Succeeded, `checkOnly: false`, 0 errors.
- **Review verdict:** Manual diligence — **PASS** (hub composes the existing exposed LWC; nav/label metadata only; AI call trimmed, still grounded). Formal `/sf-review` NOT run (checklists absent from public repo).
- **Approved by:** org owner (benjamin.johnson), "deploy".
- **Post-deploy verification:** anon Apex — GTM - Team Johnson nav = Team_Opportunity_Insights, Forecasting_Hub, Sales_Tools_Home, Sales_Perf_Admin; draftAnswers still returns 24 answers (~14s).
- **Carve-out note:** past the 2026-09-11 expiry; further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert the two apps' nav to the Pricing_Review_Checklist tab and revert `pricingReviewTool`/`PricingReviewController`; destructive-delete `salesTools` + `Sales_Tools_Home` if desired.

## 2026-09-12 — Fix: Pricing Review prefilled answers not showing in the form

Hotfix to the prior deploy: after AI pre-fill, the 24 answer boxes rendered empty even though the answers loaded. Root cause: a native `<textarea value={x}>` in LWC does not display the bound value (a textarea's value comes from its text content, not a `value` attribute). Fix: bind the value as the textarea's text content and render the question fields only after drafting completes so each textarea is created already holding its value.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (1):** `LightningComponentBundle:pricingReviewTool`.
- **Validated job id:** `0AfOL000003SEXl0AO` — `RunSpecifiedTests` (`CockpitRosterServiceTest`, LWC-only); 2/2, 0 failures.
- **Quick-deploy:** `0AfOL000003SEZN0A4` — Succeeded, `checkOnly: false`, 0 errors.
- **Approved by:** org owner (benjamin.johnson) — hotfix to the just-deployed feature reported broken.
- **Note:** server-side `draftAnswers` was already confirmed returning 24 answers; this was purely a client-side rendering bug. Not visually verified in-org (SSO password wall); pending user confirmation.
- **Carve-out note:** past the 2026-09-11 expiry; further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert `pricingReviewTool` to the prior commit.

## 2026-09-12 — Pricing Review prefill: reliable binding + per-question Try again/Expand

Fixes the empty-answer-boxes issue and adds per-question regeneration.
- Switched the answer fields to the base `lightning-textarea` (a native `<textarea value={x}>` does not render a bound value in LWC). Added a "{n} of 24 answered" indicator and surfaced any pre-fill error inside the form (the auto-scroll-to-builder had been hiding the top-of-page error banner).
- New `PricingReviewController.draftOne(opportunityId, questionNum, mode, current)` — regenerate ('try') or 'expand' a single question via Claude (~2s), giving a fast, robust per-question path independent of the bulk pre-fill.
- Per-question "Try again" and "Expand" buttons.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Components (3):** `ApexClass:PricingReviewController` (+ `draftOne`, extracted `loadContextOpp`), `ApexClass:PricingReviewControllerTest` (+ draftOne try/expand/guard), `LightningComponentBundle:pricingReviewTool` (lightning-textarea, in-form error, filled count, Try again/Expand).
- **Validated job id:** `0AfOL000003SEfp0AG` — `RunSpecifiedTests` (`PricingReviewControllerTest`); 6/6, 0 failures.
- **Quick-deploy:** `0AfOL000003SEhR0AW` — Succeeded, `checkOnly: false`, 0 errors.
- **Approved by:** org owner (benjamin.johnson) — continuation of the reported-broken prefill.
- **Post-deploy verification:** anon Apex — `draftOne(Rochester, Q2, 'try')` returned a grounded answer in ~1.8s. Bulk `draftAnswers` already confirmed 24 answers server-side. In-form diagnostics added so the empty-box cause is visible if it persists.
- **Carve-out note:** past the 2026-09-11 expiry; further prod changes should route through the euna-salesforce pipeline.
- **Rollback:** revert `pricingReviewTool`/`PricingReviewController` to the prior commit.
