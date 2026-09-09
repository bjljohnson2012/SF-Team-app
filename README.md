# SF Team

Interim Salesforce DX home for a GTM Command Center-style **item manager**. Formal pipeline still lives in euna-salesforce when that cutover completes.

## What it is

Lightning app **SF Team** (`SF_Team`). It does not add a new object. Items are existing `Quick_Task__c` records, using the org’s Kanban / create / list tabs.

| Tab | Existing metadata |
|---|---|
| Home | `quickTaskKanban` on `SF_Team_Home` |
| Task Kanban | `Quick_Task_Kanban` |
| Create | `Quick_Task_Create` |
| All items | `Quick_Task__c` |

`force-app/` on a local machine may hold a prod retrieve for context. It is gitignored. Do not push it — this repo is public, and prod metadata is not the source of truth.

## Org aliases

- `euna` = production
- `euna-full` = sandbox
- `EUNA-FULL` = production (do not use)

Prod is read-only by default. See `AGENTS.md`.

## Retrieve / validate (no direct prod deploy)

```bash
sf org display -o euna
sf project retrieve start -o euna \
  --metadata CustomApplication:SF_Team FlexiPage:SF_Team_Home
sf project deploy validate -o euna --source-dir team-app
```
