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

## Making the write path fully mapping-driven

Today `VeleiroSyncService` writes a fixed set of `additional_fields` for Account/Opportunity. To honor arbitrary mappings, iterate the active `Veleiro_Field_Mapping__c` rows for the object+entity and build the payload from them (Standard → top-level key, Additional Field → into `additional_fields`). The mapping data model is ready for this; it's the natural next extension.

> Remember the `additional_fields` rule: PATCH replaces the whole object, so merge — never blind-overwrite (`patchClientWithMerge`).
