# Next steps — GTM - Team Johnson

**Read this file first.** Then read `AGENTS.md`. Then look at `team-app/` only.

This repo is the interim home for one Salesforce Lightning app until euna-salesforce CI/CD is formal. A prior local Cursor session retrieved production metadata for context; **that retrieve is not in this repo** (public GitHub). The org is the source of truth.

---

## Start (cloud / CLI agent)

```bash
git clone https://github.com/bjljohnson2012/SF-Team-app.git
cd SF-Team-app
git checkout feature/sf-team-app
sf org display -o euna
```

Confirmed org aliases (case-sensitive):

| Alias | Meaning |
|---|---|
| `euna` | Production |
| `euna-full` | Sandbox (login was **skipped**; not authenticated in the prior session) |
| `EUNA-FULL` | **Production** — do not use |

Prior session user on `euna`: `benjamin.johnson@eunasolutions.com` (System Administrator, role MM NE Director). Re-auth if this machine has no `sf` alias.

---

## Hard rules (do not skip)

1. **Only touch the Team Johnson app.** Do not edit GTM CC (`Sales_Command_Center`), Task Management, or any other existing CustomApplication.
2. **Prod is read-only** except the time-boxed carve-out in `AGENTS.md` (expires **2026-09-11**). Never `sf project deploy start` against prod. Prefer `sf project deploy validate` (check-only).
3. **Retrieve by `--metadata` list only.** Never `sf project retrieve start --source-dir force-app`.
4. **This repo is public.** Do not commit a prod retrieve, permission sets, or Apex dump.
5. **Reuse `Quick_Task__c`.** Do not create a new item object. Account custom-field cap is FULL — no new `Account.*__c` fields.
6. **Ask before creating** any new metadata beyond what is already in `team-app/`.
7. Read `docs/Salesforce_Best_Practices_Naming_Standard.md` before naming anything new. **That file is not in this repo yet** — get it from euna-salesforce if you need to name metadata.

---

## What already exists

Owned by this project (`team-app/`):

| Salesforce name | API name | File |
|---|---|---|
| GTM - Team Johnson | `GTM_Team_Johnson` | `team-app/main/default/applications/GTM_Team_Johnson.app-meta.xml` |
| GTM - Team Johnson Home | `GTM_Team_Johnson_Home` | `team-app/main/default/flexipages/GTM_Team_Johnson_Home.flexipage-meta.xml` |

The app **reuses** (do not modify these apps; tabs/LWCs already live in prod):

- Tab `Quick_Task_Kanban` → LWC `quickTaskKanban`
- Tab `Quick_Task_Create` → LWC `quickTaskCreate`
- Tab `Quick_Task__c` → the Quick Task object

`sfdx-project.json` default package directory is `team-app`. `force-app` is a second directory for a **local-only** retrieve (gitignored).

---

## What is not done

| Item | Status |
|---|---|
| App in Salesforce (deployed) | **No.** Metadata is in git only. |
| Check-only validate | **Not run.** |
| PR into `main` | **No.** Work is on `feature/sf-team-app`. |
| `AGENTS.md` on this branch | Must be present (see repo root). |
| sf-review checklists | **Missing.** They live in euna-salesforce at `.claude/sf-review-references/`. A prior review did **not** clear a deploy. |
| Naming-standard doc | **Missing** from this repo. |
| Sandbox `euna-full` auth | **Skipped.** |

---

## Do next (in order)

1. Confirm `sf org display -o euna` (or log in: `sf org login web -o euna -r https://euna.my.salesforce.com`).
2. Check-only validate **only** `team-app` (writes nothing):

   ```bash
   sf project deploy validate -o euna --source-dir team-app
   ```

3. If validate fails because `quickTaskKanban` / Quick Task tabs are missing in the target, stop — those already exist in prod; do not recreate them and do not retrieve the whole org into this public repo.
4. Ask the human before any deploy. If they approve the 2026-09-11 carve-out: validate → `/sf-review` clean on the exact artifact → `sf project deploy quick` on that job id → record in `docs/EXCEPTIONS.md`. **Never `deploy start` against prod.**
5. After a successful deploy, the user finds the app in App Launcher as **GTM - Team Johnson**.
6. Open a PR `feature/sf-team-app` → `main` only if the human asks.

---

## Do not

- Edit or retrieve-overwrite other Lightning apps.
- Push `force-app/` or a `manifest/package.xml` wildcard retrieve.
- Invent a new “items” object or parallel Kanban.
- Declare sf-review clean without the EUNA checklists and a freshness retrieve of the exact components.

---

## Repo map

```
AGENTS.md                 Binding engineering rules — read after this file
README.md                 Short project summary
next steps.md             This handoff
sfdx-project.json         DX project (default: team-app)
team-app/                 Only metadata this project owns
force-app/                Local retrieve only; gitignored; not on GitHub
```

Branch to work on: **`feature/sf-team-app`**  
Repo: https://github.com/bjljohnson2012/SF-Team-app
