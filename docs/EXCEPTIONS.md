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
