# AGENTS.md — guide for coding agents

This file is written for an AI coding agent (Claude Code or similar) that a **Veleiro partner** points at this repo to install and extend the Veleiro ↔ Salesforce integration in their own org. Read this end-to-end before acting. Everything here is confirmed against the live Veleiro API.

## Step 0 — get these from the human before you touch anything

This repo ships with **no token** (it's public). You cannot connect to Veleiro without one, and you must never invent or hardcode it. Before installing, ask the human for:

1. **Their Veleiro API token** — scopes: **read + write** on clients and projects. If they don't have one, tell them to generate it in the Veleiro app (API / developer settings) or request API access from Veleiro. It's the only secret; it goes **only** into `Veleiro_Config__c.Api_Token__c` as data (install Step 2), never into a file you commit, a test, or a log.
2. **The target Salesforce org** — a `sf` CLI alias (or have them authenticate one). Confirm whether it's production (deploy runs tests) or a sandbox/scratch.

With just those two, you can do the entire install below. If either is missing, stop and ask — do not guess.

## What this repo is

A deployable Salesforce (SFDX) package that connects a partner's **Salesforce** (sales) to **Veleiro** (delivery). It is metadata-only: Apex, LWC, custom objects/fields, a flow, a permission set. There is **no build step**. The public package directory is `force-app/`.

Two businesses, one link:
- **Account** (Salesforce) ⇄ **client** (`org_…`, Veleiro)
- **Opportunity** (Salesforce) ⇄ **project** (`prjct_…`, Veleiro)

## Golden rules (safety rails)

1. **This repo is PUBLIC. Never commit secrets.** The Veleiro API token is stored as **data** in `Veleiro_Config__c.Api_Token__c`, never in source. Do not write tokens into `.apex` scripts that get committed, into tests, or into logs.
2. **All Veleiro calls are server-to-server from Apex.** Never expose the token to a browser/LWC. LWCs call Apex `@AuraEnabled` methods; only Apex holds the token.
3. **`additional_fields` is replace-on-write.** A PATCH replaces the whole `additional_fields` object. Always **read-modify-write**: GET current, merge your keys, PATCH. See `VeleiroSyncService.patchClientWithMerge`.
4. **Branch on error `code`, never on `message`.** Messages change; codes are an enum (below).
5. **Deploy to production requires ≥75% Apex coverage.** Every source class here ships with a `*Test`. If you add Apex, add tests.
6. **Propose-and-confirm for anything outward-facing** (deploys to a partner's production org, creating public repos). Read freely; confirm writes.

## Component map

| File | Responsibility |
|---|---|
| `classes/VeleiroApiClient.cls` | HTTP client. `doGet`, `listAll` (cursor pagination), `doPost`, `doPatch(ifMatchVersion)`, error routing by `code`, `appBaseUrl()`. The one place that talks HTTP. |
| `classes/VeleiroSyncService.cls` | **Write** path. `syncAccount` (Account→client), `syncOpportunity` (Opp→project, creates the client first if needed), `getClientSummary`/`getProjectSummary` (cacheable, no callout), `getProjectLive` (callout), `@InvocableMethod` for the flow. |
| `classes/VeleiroSync.cls` | **Pull** path. `syncClients()` upserts Veleiro clients into Accounts by external id. |
| `classes/VeleiroInsightService.cls` | **Velly** — health scoring + next-best-action. `getBriefing()` (dashboard), `getInsightForAccount()` (Account page). Rules in `score()`. |
| `classes/VeleiroDashboardController.cls` | `getOverview()` — clients + projects + completion, aggregated per client. |
| `classes/VeleiroMappingController.cls` | `getMappings()` — active field mappings for the console. |
| `classes/VeleiroSeed.cls` | `seed()` — inserts the 6 default field mappings (idempotent). |
| `classes/VeleiroApiMock.cls` | `@isTest` HttpCalloutMock + `seedConfig()`. Use it in new tests. |
| `lwc/veleiroPanel` / `veleiroOppPanel` | Branded panel on Account / Opportunity record pages (sync + status + "Open in Veleiro"; the Opp one shows live progress). |
| `lwc/veleiroDashboard` / `veleiroBriefing` / `veleiroInsight` | Home dashboard, Velly briefing + queues, Account insight strip. |
| `lwc/veleiroMappingHome` | Field-mapping console (grouped by object). |
| `lwc/veleiroSyncAction` / `veleiroSyncOppAction` | Headless `lightning__RecordAction` LWCs — add them as record-page actions (no QuickAction wrapper needed). |
| `flows/Create_Veleiro_Project_On_Closed_Won` | Record-triggered on Opportunity → Closed Won → async callout to the invocable. |
| `objects/Veleiro_Config__c` | Hierarchy custom setting: `Api_Token__c`, `Base_Url__c`, `App_Base_Url__c`. |
| `objects/Veleiro_Field_Mapping__c` | The mapping model (see `docs/field-mapping.md`). |

## The Veleiro API contract (authoritative)

Base: `Base_Url__c` (e.g. `https://app.beta.veleiro.dev/api/v1`). Auth: `Authorization: Bearer <token>`.

- **Envelope.** Responses wrap payload in `{"data": …}`. Lists add `has_more` and `next_cursor`.
- **Pagination is cursor-based** (no offset). Follow `next_cursor` while `has_more` is true. Cursors expire (~24h). `VeleiroApiClient.listAll` does this.
- **No trailing slash** on paths (a trailing slash 301-redirects and drops the body). Paths look like `/clients`, `/projects/prjct_x`.
- **Concurrency via version / If-Match.** Writes send `If-Match: <version>`. A `409 version_conflict` returns `detail.current_version`; re-read or retry with it. Implemented in `patchClientWithMerge` / `patchProjectWithMerge`.
- **`additional_fields` is replaced wholesale on PATCH** → read-modify-write (rule #3).
- **Errors:** `{"error":{"code": …, "message": …, "detail": …}}`. Branch on `code`. Known codes: `invalid_token`, `insufficient_scope`, `not_found`, `validation_failed`, `version_conflict`, `invalid_cursor`, `rate_limited`, `method_not_allowed`, `internal_error`.
- **Rate limit:** ~600 req/min → `429` with `Retry-After`.
- **CORS excludes `/api`** — server-to-server only (that's why the token lives in Apex, never the browser).
- **Resources:** `/clients` (`org_…`), `/projects` (`prjct_…`, has `progress` 0–100, `status`, `client_id`, `additional_fields`), `/tasks` (has `status_id`, `client_id`, `project_id`), `/tasks/states` (catalog; `state_type` ∈ `initial|in_progress|blocked|review|done`), `/members` (`prtr_mem_…`).
- **There is no workflow/automation API.** Veleiro exposes CRUD only — no outbound webhooks or triggers. Reactive automation must live on the Salesforce side (flows, scheduled Apex polling).

## Linkage model

Stored on both sides so either can find the other:

| Salesforce | Veleiro |
|---|---|
| `Account.Veleiro_Client_Id__c` (external id) | `client.id` |
| — | `client.additional_fields.sf_account_id` |
| `Opportunity.Veleiro_Project_Id__c` (external id) | `project.id` |
| `project.client_id` | the Account's client |
| — | `project.additional_fields.sf_opportunity_id` |

## Velly insight rules (`VeleiroInsightService.score()`)

Deterministic rules over **real** signals: `progress`, `status`, days since `updated_at` (stall), and count of tasks whose state `state_type = 'blocked'`. Evaluated top-down; first match wins:

1. blocked task(s) → **Choppy waters** · motion `unblock`
2. `progress==0` & stalled ≥14d → **Off course** · `protect`
3. `progress==0` & stalled ≤7d → **Just set sail** · `onboard`
4. stalled >21d → **Off course** · `protect`
5. `progress≥95` → **Smooth sailing** · `reference`
6. `progress≥30` → **Smooth sailing** · `expand`
7. else → **Steady** · `nurture`

Queues: `expand`+`reference` → Expand; `protect`+`unblock` → At-risk; `onboard`+`nurture` → Needs-attention.

## How to install in a partner org

1. `sf project deploy start -o <org> -d force-app -l RunLocalTests` (production needs the tests to pass).
2. Configure `Veleiro_Config__c` **as data** (never in git): set `Api_Token__c`, `Base_Url__c`, `App_Base_Url__c`. Use `scripts/apex/configure.apex` (edit in a local copy, don't commit the token) or the Setup UI.
3. `sf apex run -o <org> -f scripts/apex/seedMappings.apex` to seed default mappings.
4. `sf org assign permset -o <org> -n Veleiro_Integration_Access`.
5. In App Builder: add `veleiroPanel` to the Account record page, `veleiroOppPanel` to Opportunity, and add the `Veleiro_Home` / `Veleiro_Mappings` tabs to the app. Add the `veleiroSyncAction` / `veleiroSyncOppAction` LWCs as record-page actions.
6. Verify: `sf apex run` calling `VeleiroSync.syncClients();` (pull) and `VeleiroSyncService.syncAccount('<accountId>');` (push).

Full manual: `docs/setup.md`.

## How to extend (common tasks)

- **Map another field** → add a `Veleiro_Field_Mapping__c` row (or extend `VeleiroSeed`), then read it where you build the payload. Model: `docs/field-mapping.md`.
- **Sync a new object** → mirror `VeleiroSyncService.syncAccount`: read the record, read-modify-write `additional_fields`, store the returned id/version back on an external-id field. Add a `*Test` with `VeleiroApiMock`.
- **Add an insight rule** → edit `VeleiroInsightService.score()`; keep it deterministic and grounded in a real signal; add a coverage test in `VeleiroInsightServiceTest` (see the `oneProject(...)` helper).
- **React to a Veleiro change** → there are no Veleiro webhooks; use scheduled Apex that calls `listAll` and diffs, then acts in Salesforce.

## Conventions

- Labels / user-facing messages may be in Spanish; API names and code are English. Follow the file you're editing.
- One HTTP touchpoint: `VeleiroApiClient`. Don't scatter `HttpRequest`s.
- Cacheable Apex (`@AuraEnabled(cacheable=true)`) **cannot** do callouts — those methods read local state only; anything that hits Veleiro is non-cacheable and called imperatively from the LWC.
