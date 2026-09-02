# CLAUDE.md

Guidance for Claude Code working in this repo. **The full guide is [`AGENTS.md`](AGENTS.md)** — read it first; it has the component map, the Veleiro API contract, the insight rules, install steps, and the safety rails. This file only highlights the essentials.

## What this is
A public, deploy-ready Salesforce (SFDX) package that links a partner's **Salesforce** (sales) to **Veleiro** (delivery): Account ⇄ client, Opportunity ⇄ project, plus a delivery dashboard and "Velly" AI insights. Metadata-only; package dir is `force-app/`. No build step.

## Non-negotiables
- **PUBLIC repo — never commit secrets.** The Veleiro token is DATA in `Veleiro_Config__c.Api_Token__c`, never in source, tests, or logs.
- **All Veleiro calls are server-to-server from Apex.** The token never reaches a browser/LWC.
- **`additional_fields` is replace-on-write** → always read-modify-write (`VeleiroSyncService.patchClientWithMerge`).
- **Branch on error `code`, not `message`.**
- **Production deploy needs ≥75% coverage** — every source class has a `*Test`; add tests when you add Apex.
- **Confirm before outward-facing actions** (deploy to a partner's production, creating/pushing public repos).

## Commands
```bash
# Deploy (production runs tests)
sf project deploy start -o <org> -d force-app -l RunLocalTests

# Run the test suite
sf apex run test -o <org> -l RunLocalTests -w 30

# Configure (token as data — edit a local copy, don't commit the token)
sf apex run -o <org> -f scripts/apex/configure.apex
sf apex run -o <org> -f scripts/apex/seedMappings.apex
sf org assign permset -o <org> -n Veleiro_Integration_Access
```

## Layout
`force-app/main/default/{classes,lwc,objects,flows,flowDefinitions,flexipages,tabs,namedCredentials,staticresources,permissionsets}` · `docs/` (deep dives) · `scripts/apex/` (setup helpers).
