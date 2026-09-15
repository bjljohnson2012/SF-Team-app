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
