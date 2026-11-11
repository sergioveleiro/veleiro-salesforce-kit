# Upgrade test plan — 1.9.0 beta

Run this before promoting 1.9.0. The ancestor of 1.9.0 is the released 1.8.0 line (`1.8.0.RELEASED`, subscriber package `04tPe0000011UTJIA2`). Subscribers on 1.5.0, 1.6.0, and 1.8.0 must all reach 1.9.0 as an upgrade, not as a second install.

Do not promote the beta. Do not point the public install links at it.

## Orgs

Use three scratch orgs (or other empty sandboxes), one per starting version. Developer edition is enough. Keep the Veleiro token out of git and out of debug logs.

| Starting version | Subscriber package id | What it proves |
|---|---|---|
| 1.5.0.1 | `04tPe0000010wBVIAY` | Oldest production subscriber. Token lives only in public `Api_Token__c`. No meetings or pulse metadata. |
| 1.6.0.1 | `04tPe0000010yrdIAA` | Middle production subscriber. Same token storage. |
| 1.8.0.1 | `04tPe0000011UTJIA2` | Current production subscribers, including meetings and the delivery pulse. |

Create the 1.9.0 beta first:

```bash
sf package version create \
  --package "Veleiro Salesforce Kit" \
  --installation-key-bypass \
  --code-coverage \
  --target-dev-hub veleiro-ro \
  --wait 45
```

`sfdx-project.json` already sets `versionNumber` to `1.9.0.NEXT`, `ancestorVersion` to `1.8.0.RELEASED`, and `postInstallScript` to `VeleiroPostInstall`. Copy the new `04t` from the command output. If the CLI rejects `1.8.0.RELEASED`, set `ancestorVersion` to `04tPe0000011UTJIA2` and run the command again. Do not promote.

## Data to load on each org before the upgrade

1. Install the starting package (`sf package install --package <04t> --wait 20 --no-prompt`).
2. Assign `Veleiro Integration Access` to the admin running the test.
3. Paste a real token with `client`, `project`, and (on 1.8.0) `task` and `meeting` scopes. On these old versions that write lands in `Veleiro_Config__c.Api_Token__c`.
4. Set the environment the org actually uses (production or beta) from Veleiro Mappings / the version's setup screen.
5. Seed or save the default Account → client and Opportunity → project mappings.
6. Create two Accounts (one with a website) and one Opportunity on the first Account. Sync both so `Veleiro_Client_Id__c`, `Veleiro_Version__c`, and `Veleiro_Project_Id__c` are filled.
7. On the 1.8.0 org only, open the Account and confirm the meetings list and the delivery pulse render (or show the "scope not enabled" line, not an error toast).
8. Note the client id, project id, and stored version. Export is unnecessary; write them down.

Also create one Account that is not synced, so link and send still have something to do after the upgrade.

## Upgrade

```bash
sf package install --package <1.9.0-beta-04t> --wait 30 --publish-wait 20 --no-prompt -o <org>
```

The install must report an upgrade. A second package in the org is a failure.

Immediately after install, before anyone re-saves the token:

- `Veleiro_Config__c.Api_Token__c` on the org default is blank when the post-install copy succeeded.
- A callout still works (the protected setting holds the token). Opening Veleiro Setup and clicking the connection check is the UI version of this.
- If the public field is still filled, the protected copy failed. Sync must still work. That is the supported fallback. Do not clear the field by hand.

## Checks on every upgraded org

1. **Connection.** Veleiro Setup shows connected, on the same environment as before (production stays production, beta stays beta).
2. **Sync the already linked Account.** The same client id comes back. Version may increase by one. No second client is created in Veleiro.
3. **Sync the Opportunity.** The same project id comes back. `client_id` is still the Account's client.
4. **Link.** Open Veleiro Link for Account → client. The unlinked Account is listed. Linking it does not throw and does not duplicate a client that was matched.
5. **Mappings.** The saved rows are still there. An administrator can save them again. A user who only has `Veleiro Integration Access` (no Customize Application and no `Veleiro Admin`) cannot save the token, the environment, sync settings, or mappings.
6. **Scheduled pull.** If the org had pull frequency hourly or daily, the `Veleiro Pull Job` is still scheduled. Run it once (or wait) and confirm it does not rename Accounts unless `Pull_Writes_Name__c` was already on.
7. **1.8.0 org only.** Meetings and the delivery pulse still load for the linked Account and Opportunity.

## Failure that must not happen

- Install treated as a new package.
- Sync creates a second Veleiro client or project for a record that already had an id.
- Callout error "the named credential might not exist".
- The token sent to any host other than `app.veleiro.ai` or `app.beta.veleiro.dev`.
- A forced "paste the token again" before sync works.

Record the beta `04t`, the three org aliases, and the pass/fail of each check in the security-review submission.
