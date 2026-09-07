# Field mapping

Map **any** Salesforce object to a Veleiro **client** or **project**, and define which fields carry over — all from the **Veleiro Mappings** tab (the `veleiroMappingHome` LWC), no code required. Mappings are stored as data (`Veleiro_Field_Mapping__c`).

## How it works in the UI

1. Pick a **Salesforce object** (any createable/queryable object) and a **Veleiro entity** (`client` or `project`).
2. **Known pairs auto-fill.** `Account → client` and `Opportunity → project` load their sensible defaults automatically — review and **Save**.
3. **Anything else is manual.** For any other combination, add rows by hand: pick the Salesforce field, type the Veleiro target key, choose the type, **Save**.
4. Add / remove fields per pair; a **Configured mappings** summary shows everything currently set.

## The model — `Veleiro_Field_Mapping__c`

| Field | Meaning |
|---|---|
| `SObject__c` | Salesforce object (`Account`, `Opportunity`, `Case`, …) |
| `Veleiro_Entity__c` | Veleiro entity: `client` or `project` |
| `SF_Field__c` | Salesforce field API name |
| `Veleiro_Target__c` | Veleiro key it maps to (`name`, `sf_amount`, …) |
| `Target_Type__c` | `Standard` (a first-class Veleiro field) or `Additional Field` (into `additional_fields`) |
| `Is_Standard__c` | Whether it came from an out-of-the-box default |
| `Active__c` | Only active rows are used/shown |

## Defaults (auto-filled for known pairs)

**Account → client**: `Name→name` (Standard), `Id→sf_account_id`, `Website→sf_website`.
**Opportunity → project**: `Name→name` (Standard), `Amount→sf_amount`, `CloseDate→sf_close_date`.

Defined in `VeleiroSeed.defaultsFor(object, entity)` and served to the UI via `VeleiroMappingController.defaultTemplate(...)`.

## Controller API (`VeleiroMappingController`)

- `getObjects()` / `getFields(sobjectName)` — populate the pickers.
- `getMappingsFor(object, entity)` — load a saved pair.
- `defaultTemplate(object, entity)` — the known defaults (unsaved) for auto-fill.
- `saveMappings(object, entity, rows, deletedIds)` — upsert the pair's rows and delete removed ones.
- `getMappings()` — all active mappings for the summary.

## The write path is mapping-driven

`VeleiroSyncService` builds the outbound payload from the active `Veleiro_Field_Mapping__c` rows for the object+entity (`buildPayload`): **Standard** targets become top-level Veleiro keys (e.g. `name`), **Additional Field** targets go into `additional_fields`. It reads the mapped SF fields with a dynamic SOQL, so any field you configure in the panel is what gets pushed — nothing is hardcoded.

Two rules on top of the mappings:

- **System linkage always ships.** `sf_account_id` (Account→client) and `sf_opportunity_id` (Opportunity→project) are injected on every push regardless of the mapping — they are how Veleiro back-references the Salesforce record. You never need to map them by hand.
- **`name` is guaranteed.** Veleiro requires it, so if the partner hasn't mapped anything to `name`, the record's `Name` is used as a fallback.

If a pair has **no configured mappings**, the write falls back to `VeleiroSeed.defaultsFor(object, entity)` so the integration is never a no-op for an unconfigured partner.

> Remember the `additional_fields` rule: PATCH replaces the whole object, so merge — never blind-overwrite (`patchClientWithMerge`).
