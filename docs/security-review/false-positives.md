# Source Scanner (Checkmarx) findings — Veleiro Salesforce Kit 1.9.0.x

Responses to the Salesforce Source Scanner report for **Veleiro Salesforce Kit 1.9.0.2** (managed
2GP, namespace `veleiro`, scan `a0OKX000001JVl42AG`, CxEngine 9.7, preset PortalAll, run on
12 Nov 2026). File and line references are those of the scanned 1.9.0.2 source; the method name
next to each one is stable across versions. The code changes listed at the end ship in 1.9.0.3.

The report counted 54 security result paths and 22 quality paths. Note that the detailed sections
titled "Query: FLS Create" and "Query: FLS Update" contain exactly the paths the summary counts as
*Apex CRUD Create Violation* (21) and *Apex CRUD Update Violation* (16); they are the same
findings under the old query names, not additional ones.

| Query | Paths | Fixed in 1.9.0.3 | False positive (justified below) |
|---|---|---|---|
| Apex CRUD Create Violation | 21 | 1 | 20 |
| Apex CRUD Update Violation | 16 | 0 | 16 |
| Apex SOQL SOSL User Mode Missing | 13 | 6 | 7 |
| Apex CSRF In Aura LWC | 4 | 0 | 4 |
| DML Statements Inside Loops (quality) | 22 | 3 (plus the same pattern in two more places) | 19 |

## How the package controls access

Three facts explain most of the findings below.

1. **Every setup change is behind an explicit authorization check.** `VeleiroSecurity.assertCanManageSetup()`
   passes only for a user who holds the packaged custom permission `Veleiro_Manage_Setup` (granted
   by the `Veleiro Admin` permission set alone) or who has *Customize Application*, the permission
   Salesforce itself requires to manage custom settings in Setup. No `@AuraEnabled` method writes on
   component load; `VeleiroSecurityTest.pageLoadMethodsNeverWrite` is the regression guard.
2. **`Veleiro_Config__c` is the package's own org-default configuration row**, a public hierarchy
   custom setting. It holds the environment, sync direction, schedule, onboarding state and the
   last sanitized sync error. It never holds customer business data. Hierarchy custom settings have
   no object CRUD that a permission set could grant, so an `isCreateable()` / `isUpdateable()`
   check would not express a policy; it would only lock out the delegated `Veleiro Admin` role.
3. **`Veleiro_Secret__c` is a protected hierarchy custom setting.** Only Apex in the `veleiro`
   namespace can read or write it; subscribers cannot see it or be granted access to it. It exists
   so the API token is never readable by subscriber users.

All customer data (Account, Opportunity, any mapped object, `Veleiro_Field_Mapping__c`,
`Veleiro_Link__c`) is read with `WITH USER_MODE` / `AccessLevel.USER_MODE` and written through
`Security.stripInaccessible` plus `AccessLevel.USER_MODE` (`VeleiroSecurity.updateRecords`,
`insertRecords`, `updatePartial`, `upsertAccounts`, `upsertLinks`). The scanner reports none of
those.

## Apex CRUD Create / Update Violation

### 1. `VeleiroCredentialStore.writeProtected()` — lines 182–186 (Create #4, #9, #15; Update #3, #8)

Object: `Veleiro_Secret__c` (protected custom setting, fact 3). The write stores the Veleiro API
token while the encrypted External Credential is being set up. It is reachable only from the
post-install handler (`VeleiroPostInstall`) and from admin actions that first call
`assertCanManageSetup()` (`VeleiroMappingController.saveToken`, `secureLegacyToken`). A CRUD
check cannot be satisfied by any subscriber user, by design. In 1.9.0.3 the DML declares
`AccessLevel.SYSTEM_MODE` explicitly with this justification in a comment.

### 2. `VeleiroMappingController.saveEnvironment()` — lines 290–300 (Create #6, #10, #16; Update #5, #10)

Object: `Veleiro_Config__c` (fact 2). Line 287 calls `assertCanManageSetup()` before anything else.
The only values written are the two packaged Named Credentials (`Veleiro_API`, `Veleiro_API_Beta`)
and the two fixed Veleiro hosts (`https://app.veleiro.ai`, `https://app.beta.veleiro.dev`); no
free text reaches the row, and reads re-validate the host against the same allow-list
(`VeleiroApiClient.allowedAppBase`). In 1.9.0.3 the DML declares `AccessLevel.SYSTEM_MODE`
explicitly.

### 3. `VeleiroOnboardingController.skipStep()` — lines 209–211 (Create #5, #12; Update #4)

Object: `Veleiro_Config__c`. Line 204 calls `assertCanManageSetup()`. The only field written is
`Onboarding_Skipped__c`, a comma-separated list of the optional onboarding steps the administrator
chose to skip, truncated to 255 characters. Explicit `AccessLevel.SYSTEM_MODE` in 1.9.0.3.

### 4. `VeleiroSyncConfig.save()` — lines 137–149 (Create #3, #8, #11, #14, #17–#21; Update #2, #7, #11–#16)

Object: `Veleiro_Config__c`. The only caller is `VeleiroMappingController.saveSyncConfig()`, which
calls `assertCanManageSetup()` first (line 267). Every value is normalized to a fixed pick-list
before the write (`normalizeDir`, `normalizeFreq`, `normalizeTrigger`, `normalizeOppMode`;
booleans for the two switches). Explicit `AccessLevel.SYSTEM_MODE` in 1.9.0.3.

### 5. `VeleiroSyncConfig.recordError()` — lines 78–82 (Create #2, #7, #13; Update #1, #6)

Object: `Veleiro_Config__c`, fields `Last_Sync_Error__c` and `Last_Sync_Error_At__c` only. Flows,
queueables and the scheduled pull swallow exceptions; this is the one place a background failure
becomes visible to the administrator. The text always passes through `VeleiroSecurity.sanitize()`
(bearer tokens, `vlr_` token shapes, HTML and JSON bodies are replaced by a generic message;
255-character cap). The write runs as the integration user in background contexts, is wrapped in
try/catch and never blocks the sync. Requiring CRUD here would remove diagnostics without
protecting any data. Explicit `AccessLevel.SYSTEM_MODE` in 1.9.0.3.

### 6. `VeleiroCredentialStore.clearLegacyTokens()` — lines 190–195 (Update #9)

Object: `Veleiro_Config__c`, field `Api_Token__c`. Versions 1.5.0–1.8.0 stored the token in this
public field. After the token is copied into the protected setting, this method clears it. It is a
security remediation that removes a secret from a subscriber-readable location and must succeed
regardless of the running user's FLS. It runs only from post-install or from gated admin actions.
Explicit `AccessLevel.SYSTEM_MODE` in 1.9.0.3.

### 7. `VeleiroTestAccess.assign()` — line 56 (Create #1) — **fixed**

The class inserted `PermissionSetAssignment` for the running user so tests could run with the
package's permission set. It was guarded by `Test.isRunningTest()` but shipped as a normal class.
In 1.9.0.3 it is `@isTest`, so it is not executable in a subscriber org.

## Apex SOQL SOSL User Mode Missing

### 8. `VeleiroCredentialStore.readLegacyToken()` — line 168 (#6–#12)

The query reads the deprecated `Veleiro_Config__c.Api_Token__c` so callouts keep working for orgs
upgraded from 1.5.0–1.8.0 until the copy to the protected setting succeeds. It must run in system
context: the integration user is intentionally **not** granted FLS on the token field, and the
value never reaches the UI (only the booleans `hasToken()` / `hasLegacyToken()` do). The token is
used only in the `Authorization` header of a callout to a packaged Named Credential. In 1.9.0.3
the query declares `WITH SYSTEM_MODE` to make the exception explicit. The seven paths are the
seven callers of `VeleiroApiClient` that eventually reach this one method.

### 9. `VeleiroSecurity.canManageSetup()` — line 24 (#1, #2) — **fixed**

`WITH USER_MODE` added to the `PermissionSetAssignment` count. It fails closed: a user who cannot
read the object is treated as not an administrator.

### 10. `VeleiroLinkController.getSendProgress()` — line 530 (#5) — **fixed**

`WITH USER_MODE` added to the `AsyncApexJob` query, inside try/catch. A user who cannot read the
object sees "not running"; the progress itself still comes from the user-mode `Veleiro_Link__c`
query.

### 11. `VeleiroMappingController.getStatus()` — line 335 (#13) — **fixed**

`WITH USER_MODE` added to the `CronTrigger` query, inside try/catch; the next run shows blank for
a user without access.

### 12. `VeleiroSecurityTest` — line 430 (#3, #4) — **fixed**

`WITH USER_MODE` added to the `ObjectPermissions` query in the test. Test code only.

## Apex CSRF In Aura LWC

| # | Client reference | Apex method | Why it is not CSRF |
|---|---|---|---|
| 1 | `veleiroMappingHome.js:206` | `VeleiroMappingController.saveEnvironment` | Called only from `handleEnvironmentChange`, the change event of the environment combobox. `connectedCallback` calls only read methods (`getObjects`, `loadSummary`, `loadConfig`, `getStatus`). |
| 2 | `veleiroOnboarding.js:209` | `VeleiroMappingController.saveEnvironment` | Called only from `handleSaveToken`, the Save click. `connectedCallback` calls `load()`, which calls only `getState` and `getSyncConfig`. |
| 3 | `veleiroOnboarding.js:87` | `VeleiroOnboardingController.skipStep` | Not a call. It is an i18n label property that shares the method's name (`skipLabel: skipped ? T.unskipStep : T.skipStep`). |
| 4 | `veleiroOnboarding.js:144` | `VeleiroOnboardingController.skipStep` | Called only from `handleSkip`, the Skip click. |

None of these methods runs on component load (`connectedCallback`, `renderedCallback`, `@wire`),
which is the condition a crafted link could exploit. Both Apex methods also call
`assertCanManageSetup()` before writing, and every Lightning `@AuraEnabled` request carries the
platform's anti-CSRF token. `VeleiroSecurityTest.pageLoadMethodsNeverWrite` asserts that the
page-load methods (`getStatus`, `getState`) never write.

## DML Statements Inside Loops (quality)

- **Fixed (#15, #16, #22).** `VeleiroOppSyncQueueable.execute()` and
  `VeleiroSyncService.syncOpportunitiesInvocable()` called `syncOpportunity()` per record, and that
  method made its callouts and then saved. In 1.9.0.3 `VeleiroSyncService.syncOpportunities()` runs
  every callout first and performs one partial-success DML at the end; failures are recorded after
  the DML. The same pattern was applied to `VeleiroSyncAccountAction` and to the failure logging in
  `VeleiroBulkSendQueueable`, which the scanner had not reached.
- **Test loops (#1, #2, #3).** `VeleiroSyncConfigTest:253` and `VeleiroMappingControllerTest:97` loop
  over three modes on purpose, to prove that saving is idempotent. Test code only.
- **Collection building followed by one bulk DML (#4–#14, #17–#21).** `VeleiroBulkSendQueueable:50`,
  `VeleiroMappingController:211`, `VeleiroSync:13/49/62`, `VeleiroLinkController:417`,
  `VeleiroSecurity:116`, `VeleiroClientMatcher:62/68/69`, `VeleiroSyncService:70/76` and
  `VeleiroCredentialStore:168`. In each case the loop fills a list, builds a field list or sorts
  candidates, and the single DML sits after the loop. The `VeleiroCredentialStore:168` loop (a
  `for` over a `LIMIT 1` query) was rewritten as a list read in 1.9.0.3.

## Changes shipped in 1.9.0.3

- `VeleiroTestAccess` is `@isTest`.
- `WITH USER_MODE` on the `PermissionSetAssignment` (setup gate), `AsyncApexJob`, `CronTrigger` and
  test `ObjectPermissions` queries.
- Explicit `WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE`, each with a justification comment, on
  the package's own configuration rows: `Veleiro_Secret__c` (protected) and `Veleiro_Config__c`
  (gated setup writes, sanitized error bookkeeping, legacy token clean-up and read).
- Opportunity and Account auto-sync batches run all callouts first and save once; failures are
  recorded after the DML.
- Veleiro host names centralized in `VeleiroApiClient.APP_BASE_PROD` / `APP_BASE_BETA`.
