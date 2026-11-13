# Code Analyzer

Run on 11 Nov 2026 from this workspace, against `force-app`, with Salesforce CLI 2.157.8 and Code Analyzer plugin 5.16.0 (PMD, ESLint, CPD, regex). No org was connected, so graph-engine rules that need a target org were not run.

```bash
sf code-analyzer run \
  --workspace . \
  --target force-app \
  --rule-selector Recommended \
  --view table
```

## Result

2,161 violations in 68 files.

| Severity | Count |
|---|---|
| Critical (1) | 0 |
| High (2) | 38 on the first pass; 20 CRUD findings remain after business-object DML was moved to `AccessLevel.USER_MODE` |
| Moderate (3) | 700 |
| Low (4) | 1,414 |
| Info (5) | 9 |

Engines: PMD 1,367, ESLint 785, CPD 7, regex 2.

Most of the moderate and low noise is pre-existing and not a security defect: `IfStmtsMustUseBraces` / `IfElseStmtsMustUseBraces` (about 530), cyclomatic complexity, and ESLint `@salesforce-ux/slds/no-hardcoded-values-slds2` on the LWC stylesheets. The stylesheets set their own background and text color on purpose, so a subscriber theme with a dark page does not make the panels unreadable. Those rules were not changed in this branch.

## High findings that remain, and why

Re-scanned with `pmd:ApexCRUDViolation`, `pmd:ApexSuggestUsingNamedCred`, `pmd:EmptyCatchBlock`, and `pmd:AvoidGlobalModifier` after the DML change.

| Rule | Where | Verdict |
|---|---|---|
| `ApexSuggestUsingNamedCred` | `VeleiroApiClient` sets `Authorization` only when `Platform_Auth__c` is false | Accepted residual. The legacy Named Credentials cannot be retyped. The header is not used once the secure Named Credential probe has succeeded, and the call still goes only to `Veleiro_API` or `Veleiro_API_Beta`. |
| `ApexCRUDViolation` | `Veleiro_Config__c` and `Veleiro_Secret__c` reads and writes (`VeleiroApiClient`, `VeleiroCredentialStore`, `VeleiroSyncConfig`, `VeleiroMappingController.saveEnvironment`, `VeleiroOnboardingController.skipStep`) | False positive for enforcement. Hierarchy custom settings do not support `WITH USER_MODE`. `Veleiro_Secret__c` is protected. Writes that change the token, environment, sync settings, or skipped onboarding steps are behind `VeleiroSecurity.assertCanManageSetup`. None of them runs on page load: `getStatus` and `getState` are read only (`VeleiroSecurityTest.pageLoadMethodsNeverWrite`). |
| `ApexCRUDViolation` | `CronTrigger` in `VeleiroSyncConfig` and `VeleiroMappingController` | False positive. The query only reads the next fire time of the kit's own scheduled job. It is not customer business data. |
| `ApexCRUDViolation` | `FlowDefinitionView` and `PermissionSetAssignment` in `VeleiroOnboardingController`, and the Customize Application check in `VeleiroSecurity` | False positive. These are setup objects used to tell the admin whether flows are active and whether the running user may manage setup. The onboarding already catches a permissions failure and shows "unknown" instead of data. |
| `AvoidGlobalModifier` / `AvoidGlobalInstallUninstallHandlers` | `VeleiroPostInstall` | Fixed. The class is `public with sharing` and `onInstall` is `public`. It was never released as `global`. |
| `EmptyCatchBlock` | Cleared on the paths this branch added (post-install, token migration, task states, meeting-target discovery, bad ids in send progress). | Fixed. |

`ApexCRUDViolation` is no longer reported on Account, Opportunity, `Veleiro_Field_Mapping__c`, or `Veleiro_Link__c` queries and DML. Those use `WITH USER_MODE` or `AccessLevel.USER_MODE` after `Security.stripInaccessible`.

## Other notes

- PMD reports `linkedRecordIds`, `pattern`, `linked`, and `recId` as unused. They are bind variables inside dynamic SOQL strings (`:linkedRecordIds`, `:pattern`, `:linked`, `:recId`). Removing them would break the queries. False positive.
- ESLint `no-unused-vars` on `catch (e)` in `veleiroMeetings`, `veleiroOppPanel`, `veleiroPanel`, `veleiroPulse`, and `veleiroSetupBanner` is pre-existing. The catch only stops a failed panel from taking down the record page.
- CPD duplicate-code info findings are pre-existing test and service helpers.
- `ConnectApi.NamedCredentials` is intentionally not executed in tests. Code Analyzer does not flag it. Coverage of that block depends on a real org; the tests cover the branch that decides whether the secure Named Credential is used.

## Accepted residuals (not analyzer rules)

1. Legacy Named Credentials stay `NoAuthentication` because a managed package cannot delete them or change their type. They are the fallback endpoint only.
2. The protected custom setting is hidden from subscribers and is not platform-encrypted. The External Credential is the encrypted store, and it cannot be filled from the post-install script because that context cannot call out.
3. A mapped subscriber field the running user cannot read is omitted instead of failing the whole sync. The package cannot grant field access to fields it does not own.
4. System administrators pass the setup gate through Customize Application, so an upgrade does not require a new permission-set assignment before they can save the token. Users with only `Veleiro Integration Access` cannot.

## Run of 13 Nov 2026 (Checkmarx fixes for 1.9.0.2, branch `fix/checkmarx-1.9.0.2`)

Salesforce CLI 2.146.3, Code Analyzer plugin 5.14.0, PMD 7.25.0, with a temporary JRE 17 passed
through `engines.*.java_command` (the machine has no system Java). Baseline is commit `1020025`,
the exact source the Source Scanner analyzed. The Graph Engine (`sfge`) ran as well. Counts exclude
the `UninstantiableEngineError` row that an engine without Java produces.

| Rule selector | Baseline (1020025) | After | Notes |
|---|---|---|---|
| `Security` | 29 (24 High, 5 Moderate) | 11 (6 High, 5 Moderate) | 18 `ApexCRUDViolation` cleared |
| `AppExchange` | 5 Moderate | 5 Moderate | unchanged, see below |
| `sfge` (Graph Engine) | 4 (1 High, 3 Moderate) | 4 (1 High, 3 Moderate) | no `ApexFlsViolation` before or after |
| `Recommended` | 2,031 (31 High) | 2,056 (13 High) | the increase is style noise on new code (`IfStmtsMustUseBraces`, `ApexDoc`, naming of new test methods) |

What cleared the 18 security findings: the package's own configuration rows are now written with an
explicit `AccessLevel.SYSTEM_MODE` and a justification comment (`VeleiroCredentialStore`,
`VeleiroSyncConfig.save`/`recordError`, `VeleiroMappingController.saveEnvironment`,
`VeleiroOnboardingController.skipStep`), the setup gate query in `VeleiroSecurity` is
`WITH USER_MODE`, and `VeleiroTestAccess` is `@isTest`.

Remaining `Security` findings, all accepted:

| Rule | Where | Verdict |
|---|---|---|
| `ApexCRUDViolation` | `VeleiroApiClient.resolveConfig` (`Veleiro_Config__c` read of the two URL fields) | False positive: hierarchy custom setting, non-sensitive, the value is re-validated against the packaged Named Credentials and two fixed hosts. Not reported by the Source Scanner. |
| `ApexCRUDViolation` | `VeleiroOnboardingController` (`PermissionSetAssignment`, `FlowDefinitionView`) | False positive: setup objects read to tell the admin whether the permission set is assigned and the flows are active. A permissions failure is caught and shown as "unknown". |
| `ApexCRUDViolation` | `VeleiroSyncConfig.reschedule` (`CronTrigger`) | False positive: finds the kit's own scheduled job to abort it before rescheduling; gated by `assertCanManageSetup` in its caller. |
| `ApexSuggestUsingNamedCred` | `VeleiroApiClient` | Accepted residual, as before: the header is only sent while platform auth is not ready, and only to the packaged Named Credentials. |
| `AvoidHardcodedCredentialsIn*Decls`, `ProtectSensitiveData` | Constants named `CREDENTIAL` / `TOKEN_PARAMETER`, the deprecated `Api_Token__c` field, `Link_Key__c` | Name-based matches. The constants are metadata names, not secrets; `Api_Token__c` is the released legacy field that cannot be deleted and is cleared after migration; `Link_Key__c` is a record-to-resource correlation key. |

The Graph Engine's four findings are pre-existing (`ApexNullPointerException` on `VeleiroApiClient`
query helpers and `AvoidMultipleMassSchemaLookups` through `VeleiroSecurity.resolveType`) and were
not part of the Source Scanner report. The scanner's own findings and responses are in
[`false-positives.md`](false-positives.md).
