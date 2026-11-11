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
| `ApexCRUDViolation` | `Veleiro_Config__c` and `Veleiro_Secret__c` reads and writes (`VeleiroApiClient`, `VeleiroCredentialStore`, `VeleiroSyncConfig`, `VeleiroMappingController.saveEnvironment`, `VeleiroOnboardingController.skipStep`) | False positive for enforcement. Hierarchy custom settings do not support `WITH USER_MODE`. `Veleiro_Secret__c` is protected. Writes that change the token, environment, or sync settings are behind `VeleiroSecurity.assertCanManageSetup`. |
| `ApexCRUDViolation` | `CronTrigger` in `VeleiroSyncConfig` and `VeleiroMappingController` | False positive. The query only reads the next fire time of the kit's own scheduled job. It is not customer business data. |
| `ApexCRUDViolation` | `FlowDefinitionView` and `PermissionSetAssignment` in `VeleiroOnboardingController`, and the Customize Application check in `VeleiroSecurity` | False positive. These are setup objects used to tell the admin whether flows are active and whether the running user may manage setup. The onboarding already catches a permissions failure and shows "unknown" instead of data. |
| `AvoidGlobalModifier` | `VeleiroPostInstall` | False positive. An `InstallHandler` in a managed package must be `global`. |
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
