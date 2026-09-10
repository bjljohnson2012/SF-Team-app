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
