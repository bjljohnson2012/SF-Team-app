# GTM - Team Johnson

Interim Salesforce DX home for **GTM - Team Johnson**, a GTM-style item manager. Formal pipeline still lives in euna-salesforce when that cutover completes.

This repo only owns the Team Johnson app. Do not change other Salesforce apps (GTM CC, Task Management, etc.).

## What it is

Lightning app **GTM - Team Johnson** (`GTM_Team_Johnson`). It does not add a new object. Items are existing `Quick_Task__c` records, using the org’s Kanban / create / list tabs.

| Tab | Existing metadata |
|---|---|
| Home | `quickTaskKanban` on `GTM_Team_Johnson_Home` |
| Task Kanban | `Quick_Task_Kanban` |
| Create | `Quick_Task_Create` |
| All items | `Quick_Task__c` |

`force-app/` on a local machine may hold a prod retrieve for context. It is gitignored. Do not push it — this repo is public.

## Org aliases

- `euna` = production
- `euna-full` = sandbox
- `EUNA-FULL` = production (do not use)

Prod is read-only by default. See `AGENTS.md`.

## Retrieve / validate (no direct prod deploy)

```bash
sf org display -o euna
sf project retrieve start -o euna \
  --metadata CustomApplication:GTM_Team_Johnson FlexiPage:GTM_Team_Johnson_Home
sf project deploy validate -o euna --source-dir team-app
```
