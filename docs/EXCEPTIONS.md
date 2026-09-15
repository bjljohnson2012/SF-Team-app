# Deployment Exceptions Log

Prior direct-CLI prod deploys (2026-09-10 through 2026-09-14) are recorded on
`cursor/record-deploy-exception-91f8` (PR #2). This file continues that log for
owner-authorized deploys after the 2026-09-11 carve-out expired.

Each entry lists the components, the validated job id, the quick-deploy job id,
the test level, and the review verdict. Shape is always `sf project deploy
validate` → `sf project deploy quick` on that job id. Never `deploy start`.

## 2026-09-15 — Win Rate Truth (SQL-cohort page + shared filters)

Owner authorized a prod deploy (“Okay, let's get this going. Deploy it.”).
Carve-out expired; this is an explicit exception. Pipeline still unavailable
for this public repo.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Branch:** `cursor/win-rate-truth-4c8f` (PR #6)
- **Components:** `CockpitCohortService` / `CockpitCohortBatch` / `CockpitWinRateController` (+ tests), additive `CockpitConstants` / `CockpitRosterService` (+ test), `Cockpit_Cohort_Snapshot__c`, `Cockpit_Loss_Root__mdt` + seed, `Cockpit_Setting__mdt` + winrate keys, `LightningComponentBundle:winRateTruth`, `LightningComponentBundle:gtmScopeFilters`, `LightningComponentBundle:forecastHub` (Win Rate Truth pane only; prod Metrics tab `c-conversion-metrics` preserved).
- **Not in this package:** `CockpitForecastController`, Conversion Metrics Apex/LWC, AE-by-AE page files. Targeted manifest so a whole-tree deploy could not overwrite newer prod work.
- **Pre-deploy freshness retrieve:** `forecastHub` / `CockpitRosterService` / `CockpitConstants` pulled from prod. Hub already had a Metrics pane; WRT was merged into that copy. Roster/constants in prod were a subset — local adds only.
- **Validated job id:** `0AfOL000003Szej0AC` — `RunSpecifiedTests` (`CockpitCohortServiceTest`, `CockpitCohortBatchTest`, `CockpitWinRateControllerTest`, `CockpitRosterServiceTest`); 17 tests, 0 failures; 69/69 components, 0 errors. Check-only.
- **Quick-deploy job id:** `0AfOL000003Szq10AC` — Succeeded, `checkOnly: false`, 0 errors.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick` (never `deploy start`).
- **Review verdict:** Manual diligence against `AGENTS.md` — **PASS** (SQL cohort on `SQL_Datestamp_bf__c`; Ghosted via CMDT default exclude; no hardcoded Team Johnson; Account field cap untouched; hub merge kept sibling Metrics tab). Formal `/sf-review` NOT run — EUNA checklists are not in this public repo.
- **Approved by:** org owner (benjamin.johnson), “Okay, let's get this going. Deploy it.”
- **Permsets (gitignored `force-app/`):** Access + Viewer retrieved immediately before the permset package, then granted `CockpitWinRateController`, snapshot read, and CMDT read. Existing `CockpitAeController` / `CockpitConversionController` grants kept so a permset deploy does not revoke sibling tabs. First permset validate `0AfOL000003Szrd0AC` was canceled after a concurrent 2-component deploy finished mid-queue. Fresh retrieve → validate `0AfOL000003T04X0AS` (2/2, 3 tests) → quick `0AfOL000003T07l0AC`.
- **Nightly job:** `System.schedule('Cockpit cohort snapshot', '0 15 2 * * ?', new CockpitCohortBatch());` → CronTrigger `08eOL00000vj4zeYAA`, next fire 2026-09-16 02:15 America/New_York.
- **Post-deploy verification:** Tooling shows `winRateTruth`, `gtmScopeFilters`, `conversionMetrics`, `forecastHub`. Prod hub retrieve still hosts `<c-win-rate-truth>` and `<c-conversion-metrics>`. Anonymous Apex `getFilterOptions` / `getPage` (Ben Johnson / My team / All / All): 15 cohort rows, Ghosted excluded, contested 47.8%, closure-based 40.6%, distortion 7.2%, p75 311 days.
- **Rollback:** revert `forecastHub` to the pre-WRT pane; destructive-delete the new WRT Apex, LWCs, snapshot object, and two CMDT types; unschedule `08eOL00000vj4zeYAA`.

## 2026-09-15 — Win Rate Truth permission-set grants

Follow-up so assigned users can run `CockpitWinRateController`. Authored only in gitignored `force-app/`. Started from a fresh retrieve that already had `CockpitAeController`.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`)
- **Components (2, changed):** `PermissionSet:GTM_Team_Johnson_Access`, `PermissionSet:GTM_Team_Johnson_Viewer` — added `classAccesses` for `CockpitWinRateController`, CMDT read on `Cockpit_Loss_Root__mdt` / `Cockpit_Setting__mdt`, object read + view-all on `Cockpit_Cohort_Snapshot__c`. No existing grants removed.
- **Validated job id:** `0AfOL000003T04X0AS` — `RunSpecifiedTests` (`CockpitWinRateControllerTest`); 2/2, 3 tests, 0 failures. Check-only.
- **Quick-deploy job id:** `0AfOL000003T07l0AC` — Succeeded, `checkOnly: false`, 2/2 changed, 0 errors.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick` (never `deploy start`).
- **Review verdict:** Manual diligence — **PASS** (retrieve-before-deploy; sibling Apex grants preserved). Formal `/sf-review` NOT run.
- **Approved by:** org owner (benjamin.johnson), same deploy authorization as the WRT package.
- **Post-deploy verification:** retrieve of both permsets shows `CockpitWinRateController`, both CMDT types, and snapshot read, plus retained `CockpitAeController`.
- **Rollback:** remove the three WRT grant blocks from each permset.

## 2026-09-15 — Win Rate Truth `getFilterOptions` compile fix

Owner reported `apex://CockpitWinRateController: No apex action available for CockpitWinRateController.getFilterOptions` after a sibling Conversion Metrics deploy overwrote `CockpitRosterService` / `CockpitConstants` and dropped `listDirectors` / `resolveScope`. Same overwrite also invalidated AE by AE (`productTypes()`, band constants). Owner had already authorized the WRT prod path; this is the follow-up hotfix for that live error.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`), user `benjamin.johnson@eunasolutions.com`
- **Branch:** `cursor/win-rate-truth-4c8f` (PR #6)
- **Components:** `CockpitConstants`, `CockpitRosterService` (+ test). WRT controller/service/batch included so they recompile; body unchanged. Kept live `salesDirectors()` CSO picker. `listDirectors` / `resolveScope` / `directorIdsForBatch` wrap it. Restored AE `productTypes()`, `mine` mode, and band/concentration constants. AE-self only when title/role contains Account Executive so Conversion Metrics `emptyTeam_returnsEmpty` still holds.
- **Not in this package:** `forecastHub`, Conversion Metrics / AE page files, permsets.
- **Pre-deploy freshness retrieve:** `CockpitRosterService` / `CockpitConstants` still LastModified 20:44:07/08 (CSO picker only; no `listDirectors`). WRT controller/service/batch matched local except trailing newline.
- **Validated job id:** `0AfOL000003T0yz0AC` — `RunSpecifiedTests` (`CockpitRosterServiceTest`, `CockpitWinRateControllerTest`, `CockpitCohortServiceTest`, `CockpitCohortBatchTest`, `CockpitConversionServiceTest`, `CockpitConversionControllerTest`); 33 tests, 0 failures; 9/9 components. Check-only.
- **Quick-deploy job id:** `0AfOL000003T1Bt0AK` — Succeeded, `checkOnly: false`.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick` (never `deploy start`).
- **Review verdict:** Manual diligence — **PASS** (retrieve-before-deploy; CSO picker preserved; Conversion Metrics tests in the validate set). Formal `/sf-review` NOT run.
- **Approved by:** org owner (benjamin.johnson), live-error follow-up to the authorized WRT deploy.
- **Post-deploy verification:** Tooling `IsValid=true` on `CockpitWinRateController`, `CockpitCohortService`, `CockpitCohortBatch`, `CockpitAeController`, `CockpitAeCompositionService`, `CockpitConversionController`. Anonymous Apex `getFilterOptions` / `getPage` (Ben / My team / All / All): 12 director picks (My team + CSO leaders), 15 products, 15 cohort rows, contested 47.8%, closure-based 40.6%, caption `Team of Ben Johnson · All products · All sizes`. AE `getScopeOptions`: 11 directors, 14 products, 4 size bands.
- **Rollback:** redeploy the 20:44 Conversion Metrics copies of `CockpitRosterService` / `CockpitConstants` (that would re-break WRT and AE).

## 2026-09-15 — Win Rate Truth labels, Ghosted split, product families

Owner asked to clean up the live tab: created vs qualified, won/(won+lost) beside contested, Ghosted not never-real, product families, and a “Tell me what this data means” readout. Same authorized WRT prod path.

- **Org:** `euna` (production, `00D1I000001VBDGUA4`)
- **Branch:** `cursor/win-rate-truth-4c8f` (PR #6)
- **Components:** `CockpitCohortService` (+ test), `CockpitWinRateController` (+ test), `CockpitConstants`, `CockpitCohortBatchTest`, `winRateTruth`, `gtmScopeFilters` (`groupedProducts` opt-in so AE keeps raw SKUs), snapshot fields `Qualified_Count__c` / `Ghosted_Count__c`.
- **Validated job id:** `0AfOL000003T1v30AC` — `RunSpecifiedTests` (WRT + batch + controller); 14 tests, 0 failures. Check-only. Earlier `0AfOL000003T1tR0AS` failed one meaning-text assert; fixed and re-validated.
- **Quick-deploy job id:** `0AfOL000003T1wf0AC` — Succeeded.
- **Command shape:** `sf project deploy validate` → `sf project deploy quick` (never `deploy start`).
- **Review verdict:** Manual diligence — **PASS**. Formal `/sf-review` NOT run.
- **Approved by:** org owner (benjamin.johnson), live-tab cleanup follow-up.
- **Post-deploy smoke (Ben / My team / grouped All / All):** created 1,326, qualified 1,007, won 256, worked 296, never-real 31, ghosted 180, won/(won+lost) 32.5%, contested 47.8%, qualified/created 77.0%, p50 171 / p75 311, meaning includes Ghosted. Budget 14 rows, Sourcing 15 rows.
- **Rollback:** prior WRT LWC/Apex from `0AfOL000003T1Bt0AK`.
