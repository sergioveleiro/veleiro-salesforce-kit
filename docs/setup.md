# Setup

Step-by-step install of the Veleiro Salesforce Kit into your org.

## 0. Prerequisites
- Salesforce CLI (`sf`) authenticated to your target org.
- A **Veleiro API token** with read/write scopes for clients and projects (from the Veleiro app).

## 1. Deploy the metadata
```bash
sf project deploy start -o <your-org> -d force-app -l RunLocalTests
```
Production orgs run the tests during deploy (the package ships ≥75% coverage). Sandboxes/scratch orgs deploy the same way.

## 2. Paste your Veleiro API token (the ONLY thing you configure — it's a secret)
The custom setting **structure** deploys with the package. The **only mandatory value is your token**; the base URLs default in code (`Base_Url__c → callout:Veleiro_API/api/v1`, `App_Base_Url__c → https://app.beta.veleiro.dev`), so you don't have to set them.

**Recommended (UI, most secure):** Setup → **Custom Settings** → **Veleiro Config** → **Manage** → **New** (org default) → paste your token into **Api_Token__c** → Save.

> The token is **per-partner** and **never** ships in the repo or gets set by anyone but you. Do not commit it, and don't let anyone hand it to you in a script.

**Optional (CLI):** if you prefer, edit a **local** copy of `scripts/apex/configure.apex` (paste your token, run `sf apex run -f ...`), then discard the change. Only do this in your own org.

To point at Veleiro production later, set `Base_Url__c` / `App_Base_Url__c` to the prod URLs (otherwise they default to beta).

## 2b. Beta vs Production
The kit defaults to Veleiro **beta**. For a **production** partner, change the Named Credential `Veleiro_API` endpoint and `App_Base_Url__c` from `https://app.beta.veleiro.dev` to `https://app.veleiro.ai`. Nothing else changes. See the README "Beta vs Production" table.

## 3. Seed the default field mappings
```bash
sf apex run -o <your-org> -f scripts/apex/seedMappings.apex
```
Creates the 6 default Account/Opportunity → Veleiro mappings shown in the console.

## 4. Grant access
```bash
sf org assign permset -o <your-org> -n Veleiro_Integration_Access
```
Assign the same permission set to any user who should sync/see Veleiro data. It grants FLS on the Veleiro fields, the mapping object, and the two tabs.

## 5. Put the components on pages (App Builder)
- **Account record page** → add the **Veleiro** component (`veleiroPanel`) and **Velly Insight** (`veleiroInsight`).
- **Opportunity record page** → add **Veleiro Project** (`veleiroOppPanel`).
- **Record-page actions** → add `veleiroSyncAction` (Account) and `veleiroSyncOppAction` (Opportunity) via "Mobile & Lightning Actions" / the page's action list. (They're headless `lightning__RecordAction` LWCs — no QuickAction needed.)
- **App navigation** → add the **Veleiro Home** and **Veleiro Mappings** tabs to your Lightning app.

## 6. Verify end-to-end
```bash
# pull: reflect Veleiro clients into Accounts
sf apex run -o <your-org> --file /dev/stdin <<< 'System.debug(VeleiroSync.syncClients());'
# push: sync one Account to Veleiro (replace the Id)
sf apex run -o <your-org> --file /dev/stdin <<< 'System.debug(VeleiroSyncService.syncAccount(\'001...\'));'
```
Then open an Account: the Veleiro panel should show "Synced", and Velly should show a health score.

## 7. Automatic project on Closed Won
The flow **Create Veleiro Project On Closed Won** is included. Activate it (Setup → Flows) if it isn't active in your org — when an Opportunity reaches **Closed Won**, it creates the linked Veleiro project asynchronously.

## Hardening notes
- The token is a protected custom setting value; keep the number of users with "Customize Application" / "View Setup" tight.
- All calls are server-to-server; the token is never sent to the browser.
- If you fork this repo, keep it free of tokens — see `.gitignore`.
