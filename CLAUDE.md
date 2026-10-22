# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Read [`AGENTS.md`](AGENTS.md) first.** It is the full guide: the component map, the Veleiro API contract, the linkage model, the Velly insight rules, install steps and the safety rails. This file covers the essentials plus the things AGENTS.md doesn't mention yet.

## What this is
A public Salesforce (SFDX) package that you can deploy as-is. It links a partner's **Salesforce** (sales) to **Veleiro** (delivery): Account ⇄ client (`org_…`), Opportunity ⇄ project (`prjct_…`). It also adds a delivery dashboard and "Velly" insights (rule-based, in `VeleiroInsightService.score()`). The package is metadata only and lives in `force-app/` (API 62.0; no namespace on `main`, namespace `veleiro` on `packaging` — see below). There is no build step, no npm/Jest setup and no linter. The only toolchain is the `sf` CLI.

## Two branches, one codebase
- **`main`** is the no-namespace build partners deploy from source (`scripts/deploy.sh`, Download ZIP). **`packaging`** is the same code plus what 2GP managed packaging needs: `"namespace": "veleiro"` and the package definition in `sfdx-project.json`, flexipages referencing `veleiro:veleiroDashboard` instead of `c:veleiroDashboard`, and tests that resolve our own object names at runtime (`String.valueOf(Veleiro_Field_Mapping__c.SObjectType)`) instead of hardcoding `'Veleiro_Field_Mapping__c'`.
- **Functional changes land in `main`, then `git checkout packaging && git merge main`** — never the other way. Which branch you are on decides whether the namespace bugs (Named Credential, object names in data, sObjects crossing to the UI) are even reachable, which is why they shipped twice before being caught.
- **Never switch branches while `sf package version create` is running.** It writes the new `packageAliases` entry into whatever `sfdx-project.json` is in the working tree *when it finishes*, so the alias can land on the wrong branch. Check `git status` before committing after a build.
- **Promoting a version is irreversible** and is what allows production installs; `"ancestorVersion": "HIGHEST"` is what makes a customer's install an *Upgrade* instead of a second, unrelated package. An upgrade replaces metadata and never touches subscriber data — except flows, which keep the pinned `activeVersionNumber`. Process, risks, verified upgrade tests and the version history: [`docs/empaquetado.md`](docs/empaquetado.md).
- **One customer-facing URL.** Each release has its own `04t` id and there is no "latest" link, so the install link lives behind [`docs/descargas/`](docs/descargas/) (static site; strings are `data-t` keys in `assets/veleiro.js`). Publishing a version means updating the `04t` in `docs/descargas/index.html` (production *and* sandbox links) and the table in `docs/empaquetado.md`.

## Non-negotiables
- **PUBLIC repo: never commit secrets.** The Veleiro token is *data* in `Veleiro_Config__c.Api_Token__c`. Keep it out of source, tests (use `VeleiroApiMock.seedConfig()`), logs and the committed `scripts/apex/configure.apex`.
- **All Veleiro calls are server-to-server from Apex, through `VeleiroApiClient` only.** The token never reaches an LWC.
- **`additional_fields` is replaced whole on write**, so always read-modify-write (`VeleiroSyncService.patchClientWithMerge` / `patchProjectWithMerge`).
- **Branch on the error `code`, never on `message`.** No trailing slash on API paths (it causes a 301 and the body is dropped).
- **Tests must not create records on the customer's standard objects beyond Account and Opportunity.** A partner org rejected `Contact` inserts with its own validation rule and the whole deploy rolled back — Apex tests cannot bypass validation rules, required fields or record types. Exercise the "any mapped object" paths with `Veleiro_Field_Mapping__c` (ours) and the Account hierarchy (`ParentId`), which the integration already requires.
- **Every source class needs ≥75% coverage on its own** (we deploy with `RunSpecifiedTests`). Every source class is covered by a `*Test` that uses `VeleiroApiMock` — directly, or through a caller for the thin ones (`VeleiroPullQueueable` via `VeleiroSyncConfigTest`, `VeleiroSyncRecordAction` via `VeleiroRecordSyncTest`). 23 source classes, 18 test classes. Add tests when you add Apex.
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

# Managed package — only on the `packaging` branch (Dev Hub alias veleiro-ro). See docs/empaquetado.md.
sf package version create --package "Veleiro Salesforce Kit" --installation-key-bypass --code-coverage --target-dev-hub veleiro-ro --wait 45
sf package version report --package <04t...> -v veleiro-ro   # must say Code Coverage Met: true
sf org create scratch -f config/project-scratch-def.json --alias Pkg_Install_Test --duration-days 3 --target-dev-hub veleiro-ro --no-namespace --wait 20
sf package install --package <04t...> -o Pkg_Install_Test --wait 20 --publish-wait 20 --no-prompt
sf package version promote --package <04t...> -v veleiro-ro  # IRREVERSIBLE, enables production installs
```
Org aliases live in the untracked `.sf/`.

**Never deploy with `RunLocalTests`.** Partner orgs contain other teams' tests that we don't control (e.g. a failing `VeleiroEmailInsightsControllerTest` from another project blocked a production install). `RunSpecifiedTests` requires ≥75% coverage on **each** class in the deploy, not just overall. A new Apex class therefore needs a `*Test` that covers it directly or through a caller (e.g. `VeleiroPullQueueable` is covered through `VeleiroSyncConfigTest.scheduledJobRuns`).

## Architecture notes (not in AGENTS.md yet)
- **Behavior is driven by `Veleiro_Config__c`**, a hierarchy custom setting that `VeleiroSyncConfig` reads and the Mappings panel writes:
  - `Sync_Direction__c` gates push/pull through `pushEnabled()` / `pullEnabled()`.
  - `Conflict_Winner__c` decides how a `409 version_conflict` is handled.
  - `Pull_Frequency__c`: saving it (re)schedules `VeleiroPullJob`. That job enqueues `VeleiroPullQueueable`, which calls `VeleiroSync.pullUpdates()`, because scheduled Apex can't make callouts directly.
  - `Opportunity_Sync_Mode__c` decides **when** a project is born: `create` (with the Opportunity), `won` (only once it is won) or `manual`. The filter lives in `syncOpportunitiesInvocable`, not in the flows, because both Opportunity flows call that same invocable and touching a flow forces an `activeVersionNumber` bump in every org already running it. It filters on `IsWon`, not on the stage name, since a customer can rename "Closed Won". The field is new because `Auto_Sync_Opportunity__c` is a Checkbox and **a released managed package cannot change a field's type** — blank falls back to that checkbox, so an org configured before the change keeps behaving the same, and `save()` keeps the checkbox in sync for orgs still on the older version.
  - `Sync_Trigger__c` is `auto` or `manual`, and **defaults to `manual`**. It is the master switch; `Auto_Sync_Account__c` and `Auto_Sync_Opportunity__c` then turn each pair on or off (both default on), so a partner can have Account automatic and Opportunity manual. The shipped flows still gate on the master switch only — the per-pair check lives in the invocables (`VeleiroSyncAccountAction`, `VeleiroSyncService.syncOpportunitiesInvocable`), deliberately, so the flows never change and their pinned `flowDefinition` version stays valid.
- **All three record-triggered flows are gated on `Sync_Trigger__c = "auto"`** in their entry `filterFormula`, and are skipped when the direction is `veleiro_to_sf` or the record is already linked. The flows are `Auto_Sync_Account_On_Create`, `Auto_Sync_Opportunity_On_Create` and `Create_Veleiro_Project_On_Closed_Won`. In manual mode nothing syncs automatically and nothing is backfilled. Keep new automation behind the same gate.
- **Every flow needs a `flowDefinitions/<Flow>.flowDefinition-meta.xml` with `activeVersionNumber`.** Production deploys ignore `<status>Active</status>` and leave the flow inactive (this is why the auto-sync flows never ran in a production org). The definition pins a version *number*: if a flow is already active in an org and its content changes, the deploy creates a new version and the pinned number keeps the old one active, so bump it when you change a flow that is already installed.
- **Lead conversion creates Account + Opportunity in one transaction**, so both auto-sync flows fire together. `syncOpportunitiesInvocable` defers (via `VeleiroOppSyncQueueable`, 1-min retries, max 3) when the Account is <5 min old and has no client yet, so only the Account flow creates the client.
- **Protect the customer's org before the integration.** Three guards exist on purpose and must not be removed: the pull never writes `Account.Name` unless `Pull_Writes_Name__c` is on; the pull is capped (`maxPerRun`, `LIMIT 5000`) and uses partial-success DML so one of the customer's validation rules can't kill the run; and `VeleiroAutoSyncGuard` skips auto-sync for batches over 50 records, because a data load would otherwise flood async limits the customer's own jobs share. Failures land in `Veleiro_Config__c.Last_Sync_Error__c` and show in the Mappings panel.
- **The onboarding checks the org, it never trusts a flag.** `VeleiroOnboardingController.getState()` derives every step from real state: a live `GET /clients` for the connection, `Sync_Trigger__c` being non-blank for the config (the field ships blank, so only an explicit Save fills it), one active `Veleiro_Field_Mapping__c` for the mapping, a Veleiro id for "linked" and a **version** for "synced" (the version can only come from the API, which is what tells linking and syncing apart). Keep it that way: the only thing stored is which *optional* steps the customer skipped (`Onboarding_Skipped__c`). The Home banner calls it with `verifyConnection = false` so opening the Home never spends a callout.
- **Veleiro Link empareja con indices, nunca recorriendo todo.** Un cliente abrio la pestana y
  recibio *"Apex CPU time limit exceeded"*: el escaneo recorria **todos** los registros de
  Salesforce por **cada** recurso de Veleiro (dos veces: una por `sf_record_id` y otra buscando
  nombres parecidos) y en ese recorrido volvia a normalizar cada nombre. Medido en `VeleiroLinkScaleTest`:
  1.500 cuentas x 150 clientes = **5.647 ms**; con los indices, **278 ms**. `getSuggestions` arma
  en UNA pasada `byId15`, `byDomain`, `byName`, `byFirstWord`, `byToken` y `normByRecord`, y el
  bucle por recurso solo consulta indices. Una palabra compartida por mas de `MAX_BUCKET`
  registros se ignora (no distingue nada y reintroduce el recorrido). Si aun asi el CPU pasa de
  `CPU_BUDGET_MS`, se dejan de buscar parecidos pero **se sigue listando todo**: degradar vale,
  un toast rojo no. `VeleiroLinkScaleTest` es el guardian; si vuelve a rojo, alguien metio un
  recorrido completo adentro del bucle.
- **`VeleiroClientMatcher.normalizeName` cuesta.** Aplicaba 19 `replaceAll` de sufijos societarios
  a cada nombre; ahora salta el regex cuando el sufijo ni siquiera aparece como texto (mismo
  resultado, 2 regex en vez de 21 para un nombre normal). Se llama una vez por registro: nunca
  dentro de un bucle por recurso.
- **Never hand an sObject to an LWC.** `@AuraEnabled` methods return DTOs with their own property names (`VeleiroMappingController.SavedMapping`), because a raw `Veleiro_Field_Mapping__c` serializes its fields as `veleiro__SObject__c` inside the managed package, and a component reading `m.SObject__c` gets `undefined`. A customer saw this as a mapping list where every name was blank. `VeleiroMappingControllerTest` asserts the serialized payload contains no `__c`, which is the guard that catches a regression.
- **Each component paints its own surface.** Orgs can carry a custom Lightning theme — one did, with a dark background — and a component that inherits the page background and text color ends up unreadable. Every root sets `background: var(--veleiro-canvas)` and `color: var(--veleiro-ink)`; never rely on the host page being light.
- **Never write `callout:Veleiro_API` as a literal.** Inside the managed package that credential is `veleiro__Veleiro_API`, and the bare name fails with *"the named credential might not exist"* — which is how a customer ended up with a package that could never reach Veleiro at all. Build it with `VeleiroApiClient.calloutTo(name)`, which adds `VeleiroSyncConfig.namespacePrefix()` at runtime and is empty for the source-deployed build. `baseUrl()` also heals a stored `Base_Url__c` that predates the fix. The prefix has a `namespaceOverride` seam precisely because without a namespace this class of bug is invisible in tests — simulate the prefix when you touch anything that names our own metadata.
- **User-facing text follows the user's language (es / pt / en).** `VeleiroI18n` (Apex, from `UserInfo.getLanguage()`) and `c/veleiroI18n` (LWC, from `@salesforce/i18n/lang`) hold one dictionary per language with English as the per-key fallback, so a missing translation degrades instead of leaving a hole. A new string goes into **all three** dictionaries — the keys are kept identical on purpose. Custom Labels were the other option and were rejected because they carry the namespace prefix inside the managed package, which would make the `packaging` branch rewrite every reference; revisit that only when a customer needs to edit the wording from their own org. **Never assert on translated text in a test** without pinning `VeleiroI18n.languageOverride`: the running user's language would otherwise decide whether a customer's deploy passes.
- **Veleiro Link runs in both directions, and the scan pays for both.** A fresh customer's Veleiro is *empty*, so the original "start from the unlinked Veleiro resources" screen showed them nothing. `getSuggestions` now also returns `candidates` (Salesforce records with no link) built from the same single `listAll` call, and the matches found along the way are attached to those candidates so the UI can warn "this may already exist in Veleiro" before creating a duplicate. Sending is async (`VeleiroBulkSendQueueable`) and the UI polls `getSendProgress`, which counts **saved links**, not a counter of its own — if the job dies, the number stops instead of lying. Keep the batch cap (`maxPerBatch`) and the per-transaction callout check: they protect limits the customer's own jobs share.
- **The permission set is the only thing that grants access, including to the admin who installed.** Profiles are `.forceignore`d, so a deploy leaves even a System Administrator unable to see `Veleiro_Field_Mapping__c` fields — SOQL answers "No such column". That is why the onboarding's access step is **required** when the current user lacks the permission set and merely advisory when only their team does. Tests must never depend on the org's real `PermissionSetAssignment` rows; use the `assignedToMe` / `assignedToOthers` seams.
- **Any mapped object syncs, not just Account/Opportunity.** `VeleiroSyncService.syncRecord(recordId, entity)` reads the mappings for that object, and `VeleiroLinkStore` keeps the link (native fields for Account/Opportunity, `Veleiro_Link__c` for the rest). The Veleiro Link tab only offers the pairs configured in Veleiro Mappings — no mapping, nothing to link.
- **Never create a client without checking for an existing one.** `VeleiroSyncService.syncAccount` runs `VeleiroClientMatcher` first and links on a strong match (`sf_account_id` or same website domain); a name-only match is offered to the user in `veleiroPanel` instead (link / create anyway). Partners usually have clients in Veleiro and accounts in Salesforce from before the kit.
- **Never DML before a callout.** `linkAccountToClient` passes the chosen client id through `syncAccount(accountId, autoLink, linkClientId)` and saves at the end; writing the field first threw "uncommitted work pending" in the real UI, not just in tests.
- **Client creates go through `VeleiroSyncService.newClientPayload`**, which adds `website_url` from `Account.Website` so Veleiro starts its client analysis. Only create triggers it; updates never send `website_url`. An invalid `website_url` fails the whole create, so always pass it through `researchWebsite`.
- **Apex allows one `@InvocableMethod` per class.** The Opportunity invocable is in `VeleiroSyncService`. The Account one is in its own class, `VeleiroSyncAccountAction`. A new flow action needs a new class.
- **`VeleiroTargets`** is the canonical catalog of `additional_fields` keys (`sf_*`) and normalizes them. Veleiro creates a custom field for any unknown key it receives, so mapping targets must go through this normalization to avoid near-duplicate keys. Only `name` is pushed as a top-level field. `status`/`progress` belong to Veleiro.
- **Environment switch:** production (`Veleiro_API` Named Credential, `https://app.veleiro.ai`) is the default. `VeleiroMappingController` switches to beta by writing `Base_Url__c = callout:Veleiro_API_Beta/api/v1` plus `App_Base_Url__c`. There are two Named Credentials, so README's "edit the Named Credential endpoint" instructions are out of date.
- **Mapping saves replace the full set for an object→entity pair** (`VeleiroMappingController.saveMappings`). Don't append, or you get duplicates. Data sent from the LWC to Apex arrives as loosely typed maps, so marshal it explicitly.
- `@AuraEnabled(cacheable=true)` methods can't make callouts. Anything that calls Veleiro is non-cacheable and is called imperatively from the LWC.
- Branding (logo and mascot) is base64 in the `c/veleiroBrand` LWC module. `force-app/` has **no static resources or binaries**, so keep it that way (the images under `docs/descargas/assets/` belong to the public download page, not the package).
- `Veleiro_Config__c` must stay `<visibility>Public</visibility>`. `Protected` deploys to sandboxes but fails in production ("You can't set the visibility for a Custom Setting to Protected…"), and every class that uses the setting then fails with it. Always validate against production with `sf project deploy validate`.
- Access is granted only through the `Veleiro_Integration_Access` permission set (profiles are in `.forceignore`). Add new fields, classes and tabs to that permission set.

## Conventions
- Code comments and user-facing labels/messages are often in **Spanish**. API names and identifiers are English. Follow the file you're editing.
- When you change behavior, update `AGENTS.md` / `docs/` (`setup.md`, `field-mapping.md`, `veleiro-api.md`, `velly-insights.md`, `instalacion-prd.md`, `empaquetado.md`) too. Partners' coding agents rely on them.
- **A new `*Test` class has to be copied into `docs/instalacion-prd.md` by hand.** `scripts/deploy.sh` discovers the list from `force-app/`, but a production install done through the Veleiro deploy modal pastes a literal list, and under `RunSpecifiedTests` a class whose test is missing from it fails the 75% check. That list is stale today — it is missing `VeleiroAutoSyncGuardTest`, `VeleiroBulkSendQueueableTest`, `VeleiroI18nTest`, `VeleiroOnboardingControllerTest` and `VeleiroRecordSyncTest`.
