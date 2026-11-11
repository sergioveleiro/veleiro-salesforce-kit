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
| Field mappings | `Veleiro_Field_Mapping__c` | Users with the integration permission set |
| Account link | `Account.Veleiro_Client_Id__c`, `Veleiro_Version__c`, `Veleiro_Slug__c`, `Veleiro_Additional_Fields__c` | Users with the integration permission set |
| Opportunity link | `Opportunity.Veleiro_Project_Id__c`, `Veleiro_Project_Version__c` | Users with the integration permission set |
| Any other object's link | `Veleiro_Link__c` | Users with the integration permission set |

`Veleiro_Additional_Fields__c` holds the JSON `additional_fields` object returned by Veleiro for that client (a pull copy). It is not the API token.

## Authentication

1. **Preferred.** `Veleiro_API_Secure` and `Veleiro_API_Beta_Secure` are Named Credentials bound to the External Credential `Veleiro_External`. The credential's custom header is `Authorization: Bearer {!$Credential.Veleiro_External.ApiToken}`. Apex does not set that header on this path. The principal is per subscriber org; the secret is not in the package.
2. **Upgrade path.** A post-install script cannot make callouts, so it cannot call `ConnectApi.NamedCredentials`. It copies `Api_Token__c` into the protected setting and clears the public field only after that copy succeeds. A queueable then tries the External Credential. The secure Named Credential is used only after a real `GET /clients` through it succeeds.
3. **Fallback.** Until that probe succeeds, Apex sends `Authorization: Bearer` from the protected setting (or from the public field if the copy failed). The endpoint is still only `callout:veleiro__Veleiro_API` or `callout:veleiro__Veleiro_API_Beta`. Those legacy Named Credentials stay `NoAuthentication` because a managed package cannot delete them or change their type. They are not an open URL.

`Base_Url__c` is a production/beta switch written by Veleiro Setup. Any other value, including `https://…`, is ignored.

Browser links ("Open in Veleiro") allow only `https://app.veleiro.ai` and `https://app.beta.veleiro.dev`.

## Who can change setup

`saveToken`, `saveEnvironment`, `saveSyncConfig`, and `saveMappings` require Customize Application (so the installing system administrator still can) or the custom permission `Veleiro_Manage_Setup` from the packaged permission set `Veleiro Admin`.

Sync, link, dashboards, meetings, and the pulse stay available to `Veleiro Integration Access`. Queries and DML enforce field access (`WITH USER_MODE` and `Security.stripInaccessible`). The permission set grants the packaged fields that are not required, plus `Account.Website` and `Opportunity.AccountId`. Required fields (`Account.Name`, `Opportunity.Name`, and the required `Veleiro_Link__c` fields) cannot have permission-set entries; anyone who can use the object can use them. Mapped fields that belong to the subscriber are included only when the running user can read them.

## Admin steps after upgrade

- No token re-entry when the post-install copy succeeds. Confirm Veleiro Setup still shows connected.
- Assign `Veleiro Admin` only to delegated admins who should change the token or mappings and who do not have Customize Application.
- Assign `Veleiro Integration Access` to every user who should sync from a button, a flow, or the scheduled pull. People who already have the permission set receive the new field permissions and the External Credential principal access when the package upgrades.
- Subscriber fields used in mappings still need field-level security for those users. The package cannot grant fields it does not own. An inaccessible mapped field is skipped; the rest of the sync still runs.
