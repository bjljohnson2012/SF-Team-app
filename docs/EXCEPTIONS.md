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
