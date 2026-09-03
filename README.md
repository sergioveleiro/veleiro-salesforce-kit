# Veleiro Salesforce Kit

> Bring your Veleiro delivery data into Salesforce — so your sellers act on it.

An open, self-serve Salesforce package for **Veleiro partners** who run their **sales** in Salesforce and their **delivery** in [Veleiro](https://www.veleiro.ai). It links Accounts ↔ Veleiro clients and Opportunities ↔ Veleiro projects, and surfaces delivery health as sales actions — right inside the CRM your sellers already live in.

Everything here is metadata you can read, deploy, and extend. Point a coding agent (Claude Code, etc.) at this repo and it can install and adapt it for your org — see [`AGENTS.md`](AGENTS.md).

---

## Why this exists

Your CRM knows the **deal**. Veleiro knows whether the deal is actually **going well**. That delivery signal (progress, tasks, momentum) is the one thing a seller can't see in Salesforce — and it's a direct predictor of renewals, expansions, and references. This kit closes that gap.

## What you get

| Capability | What it does |
|---|---|
| **Account ↔ Client sync** | One-click "Sync with Veleiro" on an Account creates/updates the Veleiro client. |
| **Opportunity → Project** | Sync an Opportunity to a Veleiro project — manually, or **automatically when it hits Closed Won**. |
| **Pull sync** | Reflect Veleiro clients back into Salesforce as Accounts (upsert by external id). |
| **Velly insights** 🧭 | An AI-style health score + next-best-action per client, on the Account page and a home briefing (Expand / At-risk / Needs-attention queues). |
| **Delivery dashboard** | Home tab: clients, open projects, and **completion rate** per project — live from Veleiro. |
| **Field-mapping console** | A tab that shows exactly how Salesforce fields map to Veleiro (Account & Opportunity), grouped by object. |

## Architecture (at a glance)

```
Salesforce (partner CRM)                         Veleiro (delivery platform)
┌───────────────────────────┐                    ┌────────────────────────────┐
│ LWC panels / dashboard     │                    │  /api/v1                    │
│   veleiroPanel (Account)   │                    │   /clients   (org_…)        │
│   veleiroOppPanel (Opp)    │   Named Credential │   /projects  (prjct_…)      │
│   veleiroDashboard, Velly  │──────────────────▶ │   /tasks, /tasks/states     │
│                            │   Bearer token     │   /members                  │
│ Apex                       │  (server-to-server)│                             │
│   VeleiroApiClient  ───────┼───────────────────▶│                             │
│   VeleiroSyncService (write)                    │                             │
│   VeleiroInsightService                         │                             │
│   VeleiroDashboardController                    └────────────────────────────┘
│   VeleiroSync (pull)       │
│ Config: Veleiro_Config__c  │  ← your API token lives here as DATA, never in git
└───────────────────────────┘
```

Linkage is by external id, stored on both sides:
- Salesforce `Account.Veleiro_Client_Id__c` ⇄ Veleiro `client.additional_fields.sf_account_id`
- Salesforce `Opportunity.Veleiro_Project_Id__c` ⇄ Veleiro `project.additional_fields.sf_opportunity_id`

## What you bring (the only things NOT in this repo)

This repo is **public**, so it contains **no credentials** — by design. To connect, you provide exactly **two** things from outside the repo:

1. **Your Veleiro API token.** Generate it in your Veleiro account (API / developer settings) with **read + write** scopes on **clients** and **projects**. This is the only secret. It is stored as **data** in your Salesforce org (`Veleiro_Config__c`), never in git. *Don't have one? Ask Veleiro for API access.*
2. **Your Salesforce org** (production, sandbox, or scratch, API 62.0+) where you deploy.

Everything else — all code, the config structure, and the exact step-by-step — is in this repo. A person **or a coding agent** can complete the entire install with just those two inputs. If you're a coding agent, see **[`AGENTS.md`](AGENTS.md) → Step 0** for how to ask the human for the token and org before you begin.

## Install (quick)

```bash
# 1) Deploy the metadata
sf project deploy start -o <your-org> -d force-app \
  -l RunLocalTests

# 2) Configure your token + URLs (as data, not in git) — see docs/setup.md
sf apex run -o <your-org> -f scripts/apex/configure.apex   # after editing it with your token

# 3) Seed the default field mappings
sf apex run -o <your-org> -f scripts/apex/seedMappings.apex

# 4) Assign access
sf org assign permset -o <your-org> -n Veleiro_Integration_Access
```

Then add the components to your pages (App Builder): the **Veleiro** panel on the Account & Opportunity record pages, and the **Veleiro Home** / **Veleiro Mappings** tabs to your app. Full step-by-step in [`docs/setup.md`](docs/setup.md).

## Configuration

All config is **data** in the `Veleiro_Config__c` hierarchy custom setting (org default):

| Field | Purpose | Example |
|---|---|---|
| `Api_Token__c` | Your Veleiro API token (Bearer). **Never commit this.** | `vlr_…` |
| `Base_Url__c` | API base (no trailing slash) | `https://app.beta.veleiro.dev/api/v1` |
| `App_Base_Url__c` | Human portal base for "Open in Veleiro" links | `https://app.beta.veleiro.dev` |

The `Veleiro_API` **Named Credential** allow-lists the host so Apex can call out without a Remote Site Setting.

## Component reference

- **Apex** — `VeleiroApiClient` (HTTP + contract), `VeleiroSyncService` (Account→client, Opp→project, `@InvocableMethod` for flows), `VeleiroSync` (pull), `VeleiroInsightService` (Velly), `VeleiroDashboardController`, `VeleiroMappingController`, `VeleiroSeed`. Each has a matching `*Test`.
- **LWC** — `veleiroPanel`, `veleiroOppPanel`, `veleiroDashboard`, `veleiroBriefing`, `veleiroInsight`, `veleiroMappingHome`, `veleiroSyncAction`, `veleiroSyncOppAction`.
- **Flow** — `Create_Veleiro_Project_On_Closed_Won` (record-triggered, async callout).
- **Objects** — custom fields on Account & Opportunity, `Veleiro_Config__c`, `Veleiro_Field_Mapping__c`.

## Branding — included, zero setup, zero binaries

The Veleiro logo and the **Velly** mascot are **embedded as base64 data-URIs** in a shared LWC module (`c/veleiroBrand`) — there are **no static resources and no binary files** in this repo. That means the branding deploys as pure text/metadata through *any* tool (the `sf` CLI, a ZIP import, or Veleiro's own metadata push) and renders **exactly** like the product demo, with the partner uploading nothing. Colors (navy `#040b25`, accent `#cfe6f8`) are baked into the LWC styles.

A ready-made **"Veleiro" Lightning app** (`applications/Veleiro`) ships too, wired to the Home/Mappings tabs — so it shows up in the App Launcher after deploy. It's brand-colored (no custom logo image, to stay 100% binary-free). Everything is additive; it never touches your existing apps, pages, layouts, or profiles.

## For coding agents 🤖

[`AGENTS.md`](AGENTS.md) is a machine-readable guide: the component map, the Veleiro API contract, the mapping model, the Velly insight rules, and safety rails. It's written so a Claude can analyze this repo, install it in a partner org, and extend it safely.

## Security

- **No secrets in git.** Your token lives only as data in `Veleiro_Config__c`.
- All Veleiro calls are **server-to-server** from Apex (no browser/CORS exposure of the token).
- Access is granted via the `Veleiro_Integration_Access` permission set, not by editing profiles.
- See [`docs/setup.md`](docs/setup.md) for hardening notes.

## Extending

The field-mapping model (`Veleiro_Field_Mapping__c`) and the API client are designed to be built on. Ideas and how-tos in [`docs/field-mapping.md`](docs/field-mapping.md) and [`AGENTS.md`](AGENTS.md).

## License

MIT — see [`LICENSE`](LICENSE).
