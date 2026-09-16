# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Read [`AGENTS.md`](AGENTS.md) first.** It is the full guide: the component map, the Veleiro API contract, the linkage model, the Velly insight rules, install steps and the safety rails. This file covers the essentials plus the things AGENTS.md doesn't mention yet.

## What this is
A public Salesforce (SFDX) package that you can deploy as-is. It links a partner's **Salesforce** (sales) to **Veleiro** (delivery): Account ⇄ client (`org_…`), Opportunity ⇄ project (`prjct_…`). It also adds a delivery dashboard and "Velly" insights (rule-based, in `VeleiroInsightService.score()`). The package is metadata only and lives in `force-app/` (API 62.0, no namespace). There is no build step, no npm/Jest setup and no linter. The only toolchain is the `sf` CLI.

## Non-negotiables
- **PUBLIC repo: never commit secrets.** The Veleiro token is *data* in `Veleiro_Config__c.Api_Token__c`. Keep it out of source, tests (use `VeleiroApiMock.seedConfig()`), logs and the committed `scripts/apex/configure.apex`.
- **All Veleiro calls are server-to-server from Apex, through `VeleiroApiClient` only.** The token never reaches an LWC.
- **`additional_fields` is replaced whole on write**, so always read-modify-write (`VeleiroSyncService.patchClientWithMerge` / `patchProjectWithMerge`).
- **Branch on the error `code`, never on `message`.** No trailing slash on API paths (it causes a 301 and the body is dropped).
- **Every source class needs ≥75% coverage on its own** (we deploy with `RunSpecifiedTests`). Every source class has a `*Test` that uses `VeleiroApiMock`. Add tests when you add Apex.
- **Confirm before outward-facing actions**, such as a deploy to a partner's production org or creating/pushing public repos.

## Commands
```bash
# Deploy / validate (RunSpecifiedTests with every *Test class in force-app/)
scripts/deploy.sh <org>
scripts/deploy.sh <org> --validate

# Kit tests with coverage / one class / one method
sf apex run test -o <org> -n $(ls force-app/main/default/classes/*Test.cls | xargs -n1 basename | sed 's/\.cls$//' | paste -sd, -) -w 30 -c -r human
sf apex run test -o <org> -t VeleiroSyncServiceTest -w 10 -r human
sf apex run test -o <org> -t VeleiroSyncServiceTest.<methodName> -w 10 -r human

# Configure (token as data: edit a local copy, don't commit the token)
sf apex run -o <org> -f scripts/apex/configure.apex
sf apex run -o <org> -f scripts/apex/seedMappings.apex
sf org assign permset -o <org> -n Veleiro_Integration_Access
```
Org aliases live in the untracked `.sf/`.

**Never deploy with `RunLocalTests`.** Partner orgs contain other teams' tests that we don't control (e.g. a failing `VeleiroEmailInsightsControllerTest` from another project blocked a production install). `RunSpecifiedTests` requires ≥75% coverage on **each** class in the deploy, not just overall. A new Apex class therefore needs a `*Test` that covers it directly or through a caller (e.g. `VeleiroPullQueueable` is covered through `VeleiroSyncConfigTest.scheduledJobRuns`).

## Architecture notes (not in AGENTS.md yet)
- **Behavior is driven by `Veleiro_Config__c`**, a hierarchy custom setting that `VeleiroSyncConfig` reads and the Mappings panel writes:
  - `Sync_Direction__c` gates push/pull through `pushEnabled()` / `pullEnabled()`.
  - `Conflict_Winner__c` decides how a `409 version_conflict` is handled.
  - `Pull_Frequency__c`: saving it (re)schedules `VeleiroPullJob`. That job enqueues `VeleiroPullQueueable`, which calls `VeleiroSync.pullUpdates()`, because scheduled Apex can't make callouts directly.
  - `Sync_Trigger__c` is `auto` or `manual`, and **defaults to `manual`**.
- **All three record-triggered flows are gated on `Sync_Trigger__c = "auto"`** in their entry `filterFormula`, and are skipped when the direction is `veleiro_to_sf` or the record is already linked. The flows are `Auto_Sync_Account_On_Create`, `Auto_Sync_Opportunity_On_Create` and `Create_Veleiro_Project_On_Closed_Won`. In manual mode nothing syncs automatically and nothing is backfilled. Keep new automation behind the same gate.
- **Every flow needs a `flowDefinitions/<Flow>.flowDefinition-meta.xml` with `activeVersionNumber`.** Production deploys ignore `<status>Active</status>` and leave the flow inactive (this is why the auto-sync flows never ran in a production org). The definition pins a version *number*: if a flow is already active in an org and its content changes, the deploy creates a new version and the pinned number keeps the old one active, so bump it when you change a flow that is already installed.
- **Lead conversion creates Account + Opportunity in one transaction**, so both auto-sync flows fire together. `syncOpportunitiesInvocable` defers (via `VeleiroOppSyncQueueable`, 1-min retries, max 3) when the Account is <5 min old and has no client yet, so only the Account flow creates the client.
- **Client creates go through `VeleiroSyncService.newClientPayload`**, which adds `website_url` from `Account.Website` so Veleiro starts its client analysis. Only create triggers it; updates never send `website_url`. An invalid `website_url` fails the whole create, so always pass it through `researchWebsite`.
- **Apex allows one `@InvocableMethod` per class.** The Opportunity invocable is in `VeleiroSyncService`. The Account one is in its own class, `VeleiroSyncAccountAction`. A new flow action needs a new class.
- **`VeleiroTargets`** is the canonical catalog of `additional_fields` keys (`sf_*`) and normalizes them. Veleiro creates a custom field for any unknown key it receives, so mapping targets must go through this normalization to avoid near-duplicate keys. Only `name` is pushed as a top-level field. `status`/`progress` belong to Veleiro.
- **Environment switch:** production (`Veleiro_API` Named Credential, `https://app.veleiro.ai`) is the default. `VeleiroMappingController` switches to beta by writing `Base_Url__c = callout:Veleiro_API_Beta/api/v1` plus `App_Base_Url__c`. There are two Named Credentials, so README's "edit the Named Credential endpoint" instructions are out of date.
- **Mapping saves replace the full set for an object→entity pair** (`VeleiroMappingController.saveMappings`). Don't append, or you get duplicates. Data sent from the LWC to Apex arrives as loosely typed maps, so marshal it explicitly.
- `@AuraEnabled(cacheable=true)` methods can't make callouts. Anything that calls Veleiro is non-cacheable and is called imperatively from the LWC.
- Branding (logo and mascot) is base64 in the `c/veleiroBrand` LWC module. The repo has **no static resources or binaries**, so keep it that way.
- `Veleiro_Config__c` must stay `<visibility>Public</visibility>`. `Protected` deploys to sandboxes but fails in production ("You can't set the visibility for a Custom Setting to Protected…"), and every class that uses the setting then fails with it. Always validate against production with `sf project deploy validate`.
- Access is granted only through the `Veleiro_Integration_Access` permission set (profiles are in `.forceignore`). Add new fields, classes and tabs to that permission set.

## Conventions
- Code comments and user-facing labels/messages are often in **Spanish**. API names and identifiers are English. Follow the file you're editing.
- When you change behavior, update `AGENTS.md` / `docs/` (`setup.md`, `field-mapping.md`, `veleiro-api.md`, `velly-insights.md`) too. Partners' coding agents rely on them.
