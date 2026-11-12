# Solution architecture and usage

Veleiro Salesforce Kit is a second-generation managed package (`Veleiro Salesforce Kit`, `0HoPe00000003SXKAY`, namespace `veleiro`). It connects a subscriber's Salesforce org to that subscriber's Veleiro workspace.

This document is the draft for the AppExchange "Solution Architecture and Usage" section. It describes 1.9.0.

## What the subscriber does

An administrator installs the package, assigns `Veleiro Integration Access` to people who sync or link records, and pastes a Veleiro API token in the **Veleiro Setup** tab. They choose production (`https://app.veleiro.ai`) or beta (`https://app.beta.veleiro.dev`), map Salesforce fields to Veleiro clients and projects, and either link records that already exist on both sides or send Salesforce records to Veleiro.

Day to day, sales users open an Account or an Opportunity and see delivery status, or they click Sync. Optional record-triggered flows create the Veleiro client or project when a record is created or an Opportunity is won. A scheduled job can pull newer Veleiro clients back into Accounts. There is no Veleiro webhook; Salesforce always initiates the call.

## Data flow

```
Salesforce record (Account, Opportunity, or any mapped object)
        │  Apex reads the fields the admin mapped
        ▼
VeleiroApiClient  ── callout ──►  Named Credential
        │                              │
        │                     https://app.veleiro.ai/api/v1
        │                     or https://app.beta.veleiro.dev/api/v1
        ▼
Veleiro API  (clients, projects, tasks, meetings)
        │
        ▼
Ids and versions written back to Salesforce
```

All Veleiro traffic is server-to-server from Apex. The browser never receives the API token. Lightning web components call `@AuraEnabled` methods only.

### What is sent

- **Client create:** `name`, optional `website_url` (from `Account.Website`, normalized to an absolute `https` URL), and `additional_fields`. `additional_fields` always includes `sf_account_id`. Other keys come from active `Veleiro_Field_Mapping__c` rows.
- **Client update:** the same mapped fields. `additional_fields` is read, merged, and written back whole, because Veleiro replaces that object on PATCH. `website_url` is not sent on update.
- **Project create:** `name`, `client_id`, and `additional_fields` (including `sf_opportunity_id` or, for any other object, `sf_record_id` and `sf_object`).
- **Project update:** mapped fields plus merged `additional_fields`. `client_id` is not changed on update.
- **Reads:** client, project, task, task-state, and meeting records, used to render the panels and to decide what to pull or link. Meeting `url` values are shown as Veleiro sent them. The kit does not build those URLs.

`name` is the only mapped value sent as a top-level Veleiro field besides the system ids above. `status` and `progress` stay in Veleiro; Salesforce displays them and does not own them.

### What is stored in Salesforce

| Data | Where | Who can read it |
|---|---|---|
| API token | `Veleiro_Secret__c` (protected hierarchy custom setting) | Apex in this package only |
| API token, after a successful platform write | External Credential principal `Veleiro_External` / `VeleiroPrincipal` | The platform. Apex cannot read it back |
| Legacy API token | `Veleiro_Config__c.Api_Token__c` | Public custom setting. Cleared after the protected copy succeeds. If that copy fails, the value stays so the org keeps working |
| Environment, sync direction, pull schedule, last error | `Veleiro_Config__c` (public) | Users with the integration permission set. The error text is sanitized |
| Field mappings | `Veleiro_Field_Mapping__c` | Read: users with the integration permission set. Create, edit, delete: `Veleiro Admin` only |
| Account link | `Account.Veleiro_Client_Id__c`, `Veleiro_Version__c`, `Veleiro_Slug__c`, `Veleiro_Additional_Fields__c` | Users with the integration permission set |
| Opportunity link | `Opportunity.Veleiro_Project_Id__c`, `Veleiro_Project_Version__c` | Users with the integration permission set |
| Any other object's link | `Veleiro_Link__c` | Users with the integration permission set |

`Veleiro_Additional_Fields__c` holds the JSON `additional_fields` object returned by Veleiro for that client (a pull copy). It is not the API token.

## Authentication

1. **Preferred.** `Veleiro_API_Secure` and `Veleiro_API_Beta_Secure` are Named Credentials bound to the External Credential `Veleiro_External`. The credential's custom header is `Authorization: Bearer {!$Credential.Veleiro_External.ApiToken}`. The permission sets grant that principal as `veleiro__Veleiro_External-VeleiroPrincipal` (namespace, two underscores, credential name, dash, NamedPrincipal `parameterName`). Apex does not set that header on this path. The principal is per subscriber org; the secret is not in the package.
2. **Upgrade path.** A post-install script cannot make callouts, so it cannot call `ConnectApi.NamedCredentials`. It copies `Api_Token__c` into the protected setting and clears the public field only after that copy succeeds. A queueable then tries the External Credential. The secure Named Credential is used only after a real `GET /clients` through it succeeds.
3. **Fallback.** Until that probe succeeds, Apex sends `Authorization: Bearer` from the protected setting (or from the public field if the copy failed). The endpoint is still only `callout:veleiro__Veleiro_API` or `callout:veleiro__Veleiro_API_Beta`. Those legacy Named Credentials stay `NoAuthentication` because a managed package cannot delete them or change their type. They are not an open URL.

`Base_Url__c` is a production/beta switch written by Veleiro Setup. Any other value, including `https://…`, is ignored.

Browser links ("Open in Veleiro") allow only `https://app.veleiro.ai` and `https://app.beta.veleiro.dev`.

## Who can change setup

`saveToken`, `saveEnvironment`, `saveSyncConfig`, `saveMappings`, `secureLegacyToken`, `skipStep`, and `VeleiroSeed.seed()` require Customize Application (so the installing system administrator still can) or the custom permission `Veleiro_Manage_Setup` from the packaged permission set `Veleiro Admin`.

Least privilege is in the permission sets, not only in Apex. `Veleiro Integration Access` reads `Veleiro_Field_Mapping__c` and nothing more: no create, edit, or delete, no View All, no Modify All, and no Veleiro Setup or Veleiro Mappings tab. A sales user cannot change what the sync sends, through the UI, the API, or Data Loader. `Veleiro Admin` carries create, edit, and delete on mappings (still no View All or Modify All), the edit access on the mapping fields, and the two setup tabs.

Nothing writes when a page loads. `getStatus` and `getState` are read only. A token left in the public field by 1.5.0, 1.6.0, or 1.8.0 is moved by the post-install script; if that copy did not happen, the setup screens show an administrator a "Secure the token" button (`secureLegacyToken`), and any administrator Save of the token, environment, or sync settings finishes the move.

Links that come from the API are checked before they reach an `href`. A meeting `url` is kept only when it is `https://` on `app.veleiro.ai` or `app.beta.veleiro.dev` (`VeleiroApiClient.safeAppUrl`, with a second check in the `veleiroMeetings` component). Any other value lists the meeting without a link.

Sync, link, dashboards, meetings, and the pulse stay available to `Veleiro Integration Access`. Queries and DML enforce field access (`WITH USER_MODE` and `Security.stripInaccessible`). The permission set grants the packaged fields that are not required, plus `Account.Website` and `Opportunity.AccountId`. Required fields (`Account.Name`, `Opportunity.Name`, and the required `Veleiro_Link__c` fields) cannot have permission-set entries; anyone who can use the object can use them. Mapped fields that belong to the subscriber are included only when the running user can read them.

## Admin steps after upgrade

- No token re-entry when the post-install copy succeeds. Confirm Veleiro Setup still shows connected.
- Assign `Veleiro Admin`, together with `Veleiro Integration Access`, to whoever changes the token, sync settings, or mappings. After the upgrade, `Veleiro Integration Access` alone no longer edits mappings or shows the Veleiro Setup and Veleiro Mappings tabs.
- If the public token field was not cleared by the upgrade, an administrator opens Veleiro Setup and presses **Secure the token**.
- Assign `Veleiro Integration Access` to every user who should sync from a button, a flow, or the scheduled pull. People who already have the permission set receive the new field permissions and the External Credential principal access when the package upgrades.
- Subscriber fields used in mappings still need field-level security for those users. The package cannot grant fields it does not own. An inaccessible mapped field is skipped; the rest of the sync still runs.
