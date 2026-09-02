# Field mapping

How Salesforce fields map to Veleiro. The mappings are **data** (`Veleiro_Field_Mapping__c` records), so partners can change them without editing code, and the console (`Veleiro Mappings` tab) renders them grouped by object.

## The model — `Veleiro_Field_Mapping__c`

| Field | Meaning |
|---|---|
| `SObject__c` | Salesforce object (`Account`, `Opportunity`, …) |
| `SF_Field__c` | Salesforce field API name (`Name`, `Amount`, …) |
| `Veleiro_Target__c` | Veleiro key it maps to (`name`, `sf_amount`, …) |
| `Target_Type__c` | `Standard` (a first-class Veleiro field like `name`) or `Additional Field` (goes into `additional_fields`) |
| `Is_Standard__c` | Whether it's a default/out-of-the-box mapping |
| `Active__c` | Only active rows are used/shown |

## Defaults (from `VeleiroSeed`)

**Account → client**
| Salesforce | → | Veleiro | Type |
|---|---|---|---|
| `Name` | → | `name` | Standard |
| `Id` | → | `sf_account_id` | Additional |
| `Website` | → | `sf_website` | Additional |

**Opportunity → project**
| Salesforce | → | Veleiro | Type |
|---|---|---|---|
| `Name` | → | `name` | Standard |
| `Amount` | → | `sf_amount` | Additional |
| `CloseDate` | → | `sf_close_date` | Additional |

## Adding a mapping
1. Create a `Veleiro_Field_Mapping__c` row (via the UI, data load, or extend `VeleiroSeed`).
2. Reference it where the payload is built (`VeleiroSyncService`). Today the write path sets a fixed set of `additional_fields`; to make it fully mapping-driven, iterate the active mappings for the object and build the payload from them. This is the natural extension point.

> Remember the `additional_fields` rule: PATCH replaces the whole object, so merge — never blind-overwrite (`patchClientWithMerge` shows the pattern).
