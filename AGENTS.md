# AGENTS.md — EUNA Salesforce Engineering Rules

For any AI coding agent working in this repo — Claude Code, Cursor, Aider, or otherwise. This is
the canonical, complete set of engineering and governance rules; nothing here is duplicated
elsewhere. Claude Code sessions also read `CLAUDE.md`, which adds only what's specific to Claude
Code itself (skill invocation, subagent dispatch mechanics, hooks) — this file is everything else,
and is the one to keep current.

## Context Loading — MANDATORY, read this first

Never explore `force-app` blind. If you have a skill/subagent-routing system of your own, use it to
find the right domain reference before reading source (Claude Code sessions: see `CLAUDE.md` for
how). Regardless of tooling, before touching any code in this repo, know: which domain you're in,
what the org's known gotchas are for it, and what naming/hardcoding rules below apply.

**Also mandatory, same step:** if the task creates, renames, or names ANY metadata (field, object,
flow, class, trigger, LWC, permission set, validation rule, custom metadata) — read
[`docs/Salesforce_Best_Practices_Naming_Standard.md`](docs/Salesforce_Best_Practices_Naming_Standard.md)
before naming it. It is the org's naming-convention and best-practices standard (adopted
2026-08-20); it covers the suffix contract, API name style, flow naming
(`<Triggering Object> - <Flow Name> - <AS/BS>`), the lowercase-`x` deprecation prefix, and which
solution/customer-state field is canonical for a given question (Section 2.3/3.2) — exactly the
"plausibly-named-field" mistakes that are this org's most expensive class of error. Skip this read
only when the task touches zero new or renamed metadata (pure logic changes, bug fixes to existing
identifiers, read-only queries).

This applies to every session and every subagent, including one-line "quick" tasks. "This task is
too small to need it" is the most common way stale-context bugs ship here.

---

## Metadata Freshness — RETRIEVE BEFORE YOU BUILD, RETRIEVE BEFORE YOU DEPLOY

The local `force-app` tree is **not** the source of truth — the org is. Other admins edit prod
metadata live, and several bundles here run behind prod. Two mandatory retrieve points:

1. **Before writing any code** — retrieve the exact components you are about to touch from the org
   you will deploy to, then diff. If the retrieve changed a file, your plan was built on stale
   source: re-read the file before editing.
2. **Immediately before deploying** — retrieve the same component list again and re-diff. A
   pre-deploy diff that is a few hours old has already let a concurrent prod edit through once.

```bash
sf org display -o euna-full                       # confirm which org you're pointed at, first
sf project retrieve start -o euna \
  --metadata ApexClass:WeeklyForecastController LightningComponentBundle:dealMgmtList
git status --short && git diff --stat             # empty = local was current; non-empty = you were about to overwrite the org
```

- **Never** `sf project retrieve start --source-dir force-app`. A full-tree pull deletes local-only
  LWC modules and half-reverts in-flight refactors. Retrieve by `--metadata` component list only.
- Commit a WIP baseline **before** any retrieve — most of `force-app` is untracked, so an
  overwrite is unrecoverable.
- Aliases are case-sensitive: `euna` = production, `euna-full` = sandbox, and **`EUNA-FULL` =
  PRODUCTION**. Always pass `-o` explicitly.
- Retrieving a permission set before deploying one is mandatory — a perm-set deploy **revokes**
  every grant your local file omits.
- A field that looks missing after a retrieve may just be FLS-masked. Verify via Tooling
  `FieldDefinition` before concluding schema drift.
- Claude Code sessions in this repo have this enforced automatically by a `PreToolUse` hook
  (`.claude/hooks/retrieve-before-edit.sh`) — any edit under `force-app/**` triggers a retrieve of
  that specific component first. Other tools: do this by hand, every time.

---

## Production access discipline (mandatory — human or AI agent, no exceptions)

Anyone with prod Salesforce credentials — including an AI agent working on your behalf — treats
that access as **read-only** by default:

- `sf data query`, `sf sobject describe`, `sf project retrieve start`,
  `sf project deploy validate` (check-only) — always fine. Diagnostic and retrieval, not a deploy.
- **Never run `sf project deploy start` or `sf project deploy quick` against prod directly**, for
  anything meant to ship — hotfixes included. Branch → PR → the CI/CD pipeline's own gated release
  deploys it, with a required human approval distinct from whoever wrote the change. The pipeline
  supports several releases a day; there is no legitimate speed reason to hand-deploy.
- **TIME-BOXED CARVE-OUT — added 2026-09-08, EXPIRES Thursday 2026-09-11.** Until the CI/CD switch
  on **2026-09-11**, the direct-CLI path **is permitted for exceptions**, by the org owner's
  explicit decision (2026-09-08), because the compliant path is currently unavailable:
  `deploy-prod.yml` dies at `pull-from-prod-registry` (no registry credentials) and the downstream
  quick step *skips* rather than fails, so a release reports one red X and ships nothing. It is
  permitted only in this exact shape:
  1. `sf project deploy validate` first — check-only, writes nothing, and both local gates allow it;
  2. `/sf-review` clean on the **exact** artifact (verify by checksum, not by memory);
  3. `sf project deploy quick` on that validated job id.
  **Never `sf project deploy start` against prod, even inside the carve-out.** Record every such
  deploy in `docs/EXCEPTIONS.md` with the job id and the review verdict.
  **On 2026-09-11, once the pipeline completes one end-to-end release, DELETE this bullet** rather
  than amending it; the rule above then applies absolutely again with no exceptions.
- Never hand-edit anything in Salesforce Setup either, for the same reason: it isn't in git, so the
  next merge overwrites it.
- **UI-first is a judgment call, not an absolute rule, and it isn't Flows-only.** Flows and
  Approval Processes are the two named cases: their XML is complex, GUID/step-reference heavy, and
  genuinely hard to hand-verify — building visually in the org first and retrieving after is the
  safer *default* for anything new or non-trivial in either type. It is not a hard technical
  requirement: an agent (or a person) CAN write Flow or Approval Process XML directly, and doing so
  is reasonable for a small, well-understood change (a formula tweak, one added condition) where
  the diff is easy to reason about by reading it. What's never acceptable either way is skipping
  verification — a hand-authored Flow/Approval Process change still needs to actually run
  correctly before it ships, the same bar a UI-first build would have to clear. Other metadata
  types worth the same "consider UI-first for anything complex" judgment, case-by-case rather than
  a blanket rule: Reports/Dashboards and Duplicate/Matching Rules — their wizards enforce validity
  the raw XML doesn't.
- **This is currently a discipline rule, not a technical wall.** As of 2026-08, the System
  Administrator profile (held by every admin account, 39 active users org-wide) carries full
  metadata-deploy rights at the profile level — nothing in Salesforce itself blocks a direct
  deploy today. The euna-salesforce CI/CD pipeline's branch/tag protections govern what merges
  through git; they have zero visibility into direct Salesforce API calls made outside it.
- Claude Code sessions get a partial technical guard from the installed `salesforce-development`
  plugin (`forcedotcom/sf-skills`): a `PreToolUse` hook on `sf project deploy start`/`quick` that
  checks which org is targeted before letting the command through. Confirm it's actually loaded
  (`/plugin` → `salesforce-development` trusted, not just declared in settings) — it only covers
  Claude Code sessions using this repo's config, not a raw terminal, VS Code's own Salesforce
  extension, or Workbench.

---

## Reuse Existing Metadata — SEARCH THE ORG BEFORE CREATING ANYTHING

Reuse is the default. New metadata — field, object, picklist value, record type, permission set,
custom metadata type, LWC, Apex class, flow — is the exception and needs a stated reason.

Before proposing anything new:

1. Search the **org**, not just the repo (`sf sobject describe`, Tooling `FieldDefinition`,
   `sf data query`). The repo does not contain everything the org has.
2. Search local source for the *concept*, not the name you would have picked — grep synonyms.
3. If an existing member covers ~80% of the need, extend it (new picklist value, formula change,
   extra column, new method on the existing service) rather than adding a parallel one.
4. If nothing fits, say so explicitly — name what you searched and why each near-miss fails — and
   **ask before creating**. Data-model changes spanning objects always need approval.

Hard constraints:

- The **Account custom-field cap is FULL** in both orgs. A new `Account.*__c` field cannot be
  created until an admin deletes *and erases* one. Design around existing fields.
- Duplicate fields for one concept are this org's main source of drift
  (`Outreach_Ownership__c` vs `_old__c`, Next Step Short vs Long). A second field for the same
  concept goes stale within a quarter.

---

## No Hardcoding — ANYTHING

Never hardcode: record or org Ids, user names / emails / Ids, profile / role / permission-set names
or Ids, RecordType Ids, picklist API values, org URLs, endpoints, credentials, quotas and targets,
fiscal dates, or magic thresholds — in Apex, LWC, tests, or scripts.

Use instead:

- **Custom Metadata** for configuration, labels, thresholds and mappings, so business changes need
  no deploy.
- **Named Credentials** for endpoints and secrets; **Protected Custom Metadata** for keys.
- `Schema.describe` / `getRecordTypeInfosByDeveloperName()` for RecordTypes; queries for data.
- **Custom permissions** for gating behaviour — never a profile-name or user-name check.
- Named constants (`{Domain}Constants`) for anything left over.
- In LWC: values arrive via `@api`, wire adapters, or Apex-served config — never literals in JS.
- In tests: build data with a factory; never depend on a specific org record or Id.

Config keys are code-coupled in places (e.g. `Forecast_Director__mdt.Segment_Label__c` drives
roll-up, ordering and picker groups) — grep every consumer before renaming one.

---

## Simplicity — WRITE THE SMALLEST CORRECT SOLUTION

Default to the simplest design that satisfies the actual, stated requirement — not the one that
also covers hypothetical future requirements. A fix stays a fix; it does not grow a framework
around itself.

- No speculative abstraction: don't introduce an interface, config layer, or generic helper for a
  single caller "in case" a second one shows up later. Three similar lines beat a premature
  abstraction.
- No unrequested scope: a bug fix doesn't need surrounding refactors; a one-off script doesn't need
  a reusable module.
- Prefer extending an existing, well-understood pattern in this codebase over inventing a new one —
  see "Reuse Existing Metadata" above; the same bias applies to code shape, not just metadata.
- Keep functions and classes focused and short enough to review in one pass; split only when a
  piece is independently reused or independently tested, not on line-count instinct alone.
- Don't add error handling, fallbacks, feature flags, or config knobs for scenarios that can't
  occur given this org's actual data and callers — validate at real boundaries (user input, callouts,
  DML) and trust internal invariants elsewhere.
- If a task genuinely needs to scale (multi-domain reuse, an anticipated second consumer that is
  already committed, not hypothetical), say so explicitly and design for that — this rule is against
  *unearned* complexity, not against real scale requirements.

---

## Project Overview

Full-stack Salesforce development covering Apex, LWC, integrations, APIs, and data migrations.
Deployed via SFDX / Salesforce CLI, through the euna-salesforce CI/CD pipeline once cutover
completes (see Production access discipline above).

## Project Structure

```
force-app/
  main/
    default/
      classes/          # Apex classes and test classes
      triggers/         # Apex triggers (one trigger per object)
      lwc/              # Lightning Web Components
      aura/             # Aura components (legacy only)
      objects/          # Custom objects, fields, validation rules
      permissionsets/   # Permission sets
      flows/            # Flows and process builders
      staticresources/  # Static assets
      namedCredentials/ # Named credentials for integrations
      customMetadata/   # Custom metadata types
```

---

## Apex Development

### Naming Conventions
- Classes: `PascalCase` — e.g. `AccountService`, `OpportunityHandler`
- Test classes: suffix with `Test` — e.g. `AccountServiceTest`
- Triggers: `{ObjectName}Trigger` — e.g. `AccountTrigger`
- Interfaces: prefix with `I` — e.g. `IAccountService`
- Constants class: `{Domain}Constants` — e.g. `AccountConstants`

### Trigger Pattern
Always use a single trigger per object delegating to a handler class. Never put logic directly in triggers.

```apex
trigger AccountTrigger on Account (before insert, before update, after insert, after update) {
    AccountTriggerHandler handler = new AccountTriggerHandler();
    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.onBeforeInsert(Trigger.new);
        if (Trigger.isUpdate) handler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.onAfterInsert(Trigger.new);
        if (Trigger.isUpdate) handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
```

### Bulkification — NO SOQL IN LOOPS (enforced)
Never place SOQL queries or DML statements inside loops. Always collect IDs first, query outside, then process.

```apex
// ✅ CORRECT
Map<Id, Account> accountMap = new Map<Id, Account>(
    [SELECT Id, Name FROM Account WHERE Id IN :accountIds]
);
for (Id accId : accountIds) {
    Account acc = accountMap.get(accId);
}

// ❌ WRONG — never do this
for (Id accId : accountIds) {
    Account acc = [SELECT Id FROM Account WHERE Id = :accId];
}
```

### DML Best Practices
- Use `Database.insert(records, false)` with error handling for partial success where appropriate
- Always use `with sharing` unless there is an explicit documented reason not to
- Avoid hardcoded IDs — use custom metadata, custom settings, or queries

### Error Handling
- Use custom exceptions: `public class AccountException extends Exception {}`
- Log errors via a shared logging utility class, never swallow exceptions silently
- Surface user-facing errors through `AuraHandledException` in controller methods

### Governor Limits Awareness
- Keep SOQL queries per transaction under 100
- Keep DML statements per transaction under 150
- Use `@future`, `Queueable`, or `Batch` for large data operations
- Use `Limits.getQueries()` / `Limits.getDmlStatements()` in complex flows if needed

### Header Comments
New or modified classes and triggers get a 1–3 line header comment stating the business purpose
(the WHY), not what the code does. No `Author:`/date line — git history is the attribution record.

---

## Apex Testing — REQUIRED FOR ALL CLASSES

Every Apex class and trigger must have a corresponding test class with **minimum 85% coverage**. Always generate tests alongside production code.

### Test Structure
```apex
@isTest
private class AccountServiceTest {

    @TestSetup
    static void makeData() {
        // Create all test data here once for the class
        Account acc = new Account(Name = 'Test Account');
        insert acc;
    }

    @isTest
    static void testMethodName_scenario_expectedResult() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // call the method under test
        Test.stopTest();

        // assertions
        System.assertNotEquals(null, acc.Id, 'Account should have been created');
    }
}
```

### Test Rules
- Always use `@TestSetup` for shared data
- Always wrap the method under test in `Test.startTest()` / `Test.stopTest()`
- Use `System.assertEquals(expected, actual, message)` — always include a message
- Never use `seeAllData=true` unless absolutely unavoidable (and document why)
- Test both positive paths and negative/error paths
- For integrations, always use `HttpCalloutMock`
- Test class header comment must contain a line `Covers: <ClassOrTriggerName>`

---

## LWC Development

### Naming Conventions
- Component folders: `camelCase` — e.g. `accountSummaryCard`
- Event names: `kebab-case` — e.g. `record-selected`
- CSS classes: `kebab-case`

### Component Rules
- Keep components small and single-purpose
- Use `@wire` for data fetching wherever possible; avoid imperative Apex calls unless you need reactive control
- Always handle loading and error states explicitly in templates
- Never hardcode record IDs or org-specific values in JS
- Use `lightning-record-form` / `lightning-record-view-form` for standard CRUD before building custom

### Wire vs Imperative
```js
// ✅ Prefer wire for read operations
@wire(getAccountDetails, { accountId: '$recordId' })
wiredAccount({ error, data }) {
    if (data) this.account = data;
    if (error) this.error = error;
}

// Use imperative only when you need to call on user action
handleSave() {
    saveAccount({ account: this.account })
        .then(() => { ... })
        .catch(error => { ... });
}
```

---

## Integrations & APIs

### Authentication
- Always use Named Credentials for endpoint URLs and auth — never hardcode credentials
- Store API keys and secrets in Protected Custom Metadata or Named Credentials only

### HTTP Callouts
- Always implement `HttpCalloutMock` for tests
- Set explicit timeouts on all `HttpRequest` objects
- Log request/response payloads at debug level for troubleshooting
- Wrap callouts in try/catch and handle non-2xx responses explicitly

```apex
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:MyNamedCredential/api/v1/resource');
req.setMethod('POST');
req.setTimeout(30000);
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(payload));

HttpResponse res = new Http().send(req);
if (res.getStatusCode() != 200) {
    throw new IntegrationException('API error: ' + res.getStatusCode() + ' ' + res.getBody());
}
```

---

## Data Migrations

- Always run migrations in a **sandbox first**, never directly in production
- Use `Database.insert(records, false)` to capture partial failures without aborting
- Collect and log all failed records with their errors before retrying
- Batch size default: 200 records; reduce to 50-100 for complex triggers
- Disable triggers/validation rules via Custom Metadata flags when appropriate, re-enable immediately after
- Always export a backup of affected records before running any migration

---

## SFDX / Deployment

### Common Commands
```bash
# Authorise an org
sf org login web --alias my-sandbox

# Push source to scratch org (interactive/manual use only — see Production access discipline above)
sf project deploy start --target-org my-sandbox

# Run all tests
sf apex run test --target-org my-sandbox --test-level RunLocalTests --wait 10

# Retrieve metadata
sf project retrieve start --metadata ApexClass:AccountService --target-org my-sandbox

# Create scratch org
sf org create scratch --definition-file config/project-scratch-def.json --alias my-scratch --duration-days 7
```

### Deployment Rules

- **Re-retrieve and re-diff the component list immediately before every deploy** — see
  Metadata Freshness above.
- **Real deploys to prod go through the pipeline, never directly** — see Production access
  discipline above for the full rule and its current limits.
- Always run `RunLocalTests` (or the pipeline's derived test set) before any production deployment
- Use `.forceignore` to exclude files that should never be deployed (e.g. scratch org configs)
- Validate destructive changes carefully — confirm with the team before deleting metadata
- Every deploy plan names its rollback before deploying — redeploy of the pre-deploy retrieve
  baseline, a Custom Metadata kill-switch, or an explicit "cannot be rolled back, because …"

---

## Blast Radius, Repair Loops, Verification

- **Blast radius first.** Before changing any field, Apex class, or shared service, write down its
  consumer list — Apex references, Flows, validation rules, formulas, layouts, reports, perm sets —
  and check Flow↔Apex automation coexistence (ordering, recursion) for the affected object. Change
  nothing until the list exists; it defines the minimum safe change set and the regression tests.
  `node scripts/context/query.mjs --blast-radius <name>` (see `euna-context`'s "Context layer"
  section) gives a fast first pass over the `references`/`grants` edges already in
  `.context/graph.json` — use it to seed the list, then confirm by hand; only ~7% of components
  are domain-routed so far and the graph doesn't see report/formula consumers at all.
- **Anti-thrashing.** If the same class of failure occurs twice, stop editing: re-inspect the
  dependency list, challenge the current hypothesis against logs/schema/runtime evidence, and form
  a new root-cause hypothesis before the next change. After ~5 repair loops, report the blocker
  with evidence instead of claiming completion.
- **Verification honesty.** Done means each acceptance criterion was verified by actually running
  the check. Report each as PASS / FAIL / NOT VERIFIED (with reason) — never claim something was
  tested unless it was run, and never hide a failed verification.
- **Naming and metadata-documentation gate (mandatory, checked at completion, not just at start).**
  Before marking any task done or starting a deploy, verify every new or renamed metadata component
  (field, object, flow, class, trigger, LWC, permission set, validation rule, custom metadata) both
  (a) follows [`docs/Salesforce_Best_Practices_Naming_Standard.md`](docs/Salesforce_Best_Practices_Naming_Standard.md)
  and (b) has a populated, non-trivial description (`inlineHelpText` too, for user-facing fields).
  Report this as its own PASS / FAIL / NOT VERIFIED line alongside the other acceptance criteria — a
  task is not complete with an undocumented or non-conforming new component, even if the org accepts
  the deploy. In `euna-salesforce`, `scripts/ci/metadata-lint.mjs` checks this automatically in CI;
  in this repo (no CI), do it manually.

---

## Security

- Always use `with sharing` on Apex classes by default
- Never expose sensitive fields in SOQL unless required — query only the fields you need
- Sanitize all user inputs before using in dynamic SOQL; prefer bind variables
- Review FLS (field-level security) and CRUD permissions before exposing data via LWC or APIs
- Never log sensitive PII or credentials

---

## Agentic Development Governance

Binding for every developer and every AI agent session in this repo.

- **Grounded statements only — no premature claims.** Any factual claim about current system state —
  a file exists, a workflow is wired up, a secret/variable is set, a PR is merged, a plugin is
  installed, a skill name resolves, "this already handles X" — must be based on a check actually run
  in this session (read the file, query the API, run the command), never on memory, inference, a
  routing table's say-so, or a prior document's claim. If you have not verified it, say so explicitly
  ("not verified," "assuming X, please confirm," "need to check") instead of stating it as settled.
  This is not a style preference: unverified claims compounding across sessions is exactly how a
  routing table ends up asserting plugin skill names that don't exist and "no equivalent available"
  claims that are stale (found and corrected 2026-09-01 in `euna-context`'s routing table) — and how
  agents have contradicted an already-agreed plan mid-conversation, reading as reversal rather than
  new information. Applies to skills/docs/routing tables as much as to chat responses: don't write
  down a component name, API, or "this doesn't exist yet" claim without having just checked it. The
  concrete failure mode this exists to prevent: stating something confidently, having it challenged,
  and only then admitting it wasn't checked — verify before the first answer, not after a correction
  becomes necessary.
- **Answers stay short and pointed.** Responses to the user — summaries, status updates, decision
  asks — are TL;DR-style, plain language: no multi-paragraph prose when a few verified lines answer
  the question.
- **Model tiering (token/cost discipline).** Not every AI call needs the strongest model. Reserve
  the full reasoning model for code review, tier-2 judgment, and architecture/debugging. Route
  mechanical transforms — drafting a missing metadata description, docs-sync prose updates, simple
  classification — to a cheaper/faster model tier. Don't reach for the heaviest model for a
  one-line rename.
- **Don't narrate routine steps.** Spend output tokens on findings, decisions, and risks — not on
  announcing each mechanical step as it happens. Report results, not a play-by-play.
- **Token discipline — spend where it changes the outcome, not by default.**
  - Read only what the task needs: search/grep for the target first, then read the specific range —
    not a whole file on the chance something in it is relevant. Don't re-read a file an edit tool
    just confirmed changed.
  - Batch mechanical, repeated edits into one script pass over every target, not one agent turn per
    file. A 37-file frontmatter change is one script run, never 37 separate edits.
  - Give every open-ended task (an audit, a sweep, a "find all X") an explicit stop condition
    *before* starting — a scope boundary, a target count, a specific file set — not "look around and
    see what's there." Unscoped exploration is where token spend balloons quietest.
  - Check whether something already answers the question before re-deriving it — a committed
    artifact, a prior audit's findings, memory — when the existing answer is still current.
  - A subagent dispatch isn't free — reserve it for work that's independently scoped, genuinely
    long-running, or benefits from a fresh, unshared context (see reviewer independence below). A
    lookup answerable in one or two direct tool calls doesn't need one.
  - This cuts the other way too: don't shorten real verification to save tokens — a mutation left
    unchecked or a finding left unverified to save a few thousand tokens costs far more later.
    Efficiency comes from skipping *narration and redundant work*, never from skipping *checking*.
- **Test-quality independence.** Never let the same session write an implementation, write the only
  tests for it, and declare success uncontested — coverage % is not test quality. When you write
  both code and tests in one session, call out explicitly (in the PR or to the user) that the tests
  need an independent look, especially for negative cases, bulk behavior, and permission checks.
- **Reviewer independence.** An adversarial or verification review must never share a session,
  conversation, or context with whoever authored the change it's reviewing — it sees the diff and
  the acceptance criteria, not the implementer's reasoning trail. The same identity that wrote code,
  or the only tests for it, may never also produce that change's review verdict. Default every
  independent review to skepticism: look for a reason the change is wrong, incomplete, or insecure
  before concluding it's fine. An unquestioning PASS on a non-trivial change is a signal to re-run
  the review, not evidence of quality.
- **Agent-Ready Work Items.** For non-trivial asks, prefer a work item that states: business
  objective, acceptance criteria, explicit in/out of scope, relevant components, edge cases, and
  testing expectations — before starting implementation. This cuts exploratory token spend and
  hallucination risk. The euna-salesforce repo carries an issue template for this
  (`.github/ISSUE_TEMPLATE/agent-ready-work-item.md`); use its shape even when filing informally.
- **MCP / tool scope discipline.** An interactive session doing Salesforce or pipeline work should
  not casually reach for unrelated connected tools (ticketing, email, chat, unrelated SaaS
  connectors) that happen to be available.
- **No AI step decides whether a mandatory gate can be bypassed.** Waiver labels (`no-docs-needed`,
  `test-exempt`, `destructive-change`) are applied by a human, never self-granted by an agent to
  unblock its own PR or task.
- **Attribution stays with the human.** Commits are not tagged with AI co-authorship — the
  developer who ran the session owns the output. Bot-authored pipeline PRs (`generated-context`,
  Dependabot) are separately identifiable by their bot account, which is sufficient audit trail
  without duplicating it in commit trailers.
