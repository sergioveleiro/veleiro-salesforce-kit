# Veleiro API contract

What the integration relies on. All of this is enforced by `VeleiroApiClient`; read it there before changing behavior.

- **Base / auth.** `Base_Url__c` = `callout:Veleiro_API/api/v1` — routes through the `Veleiro_API` Named Credential, which holds the host `https://app.beta.veleiro.dev` (the allowlist). Do NOT use a raw URL. Auth `Authorization: Bearer <token>`, server-to-server only.
- **Envelope.** Payload under `{"data": …}`. Lists add `has_more` (bool) and `next_cursor` (string).
- **Pagination.** Cursor-based, no offset. Follow `next_cursor` while `has_more`. Cursors expire (~24h). `VeleiroApiClient.listAll` handles it.
- **No trailing slash.** Paths must not end in `/` (a trailing slash 301-redirects and drops the body).
- **Versioning / concurrency.** Each resource has a `version`. Writes send `If-Match: <version>`. A `409 version_conflict` returns `detail.current_version`; re-read or retry with it.
- **`additional_fields`.** A PATCH **replaces the whole object** — always read-modify-write (GET, merge your keys, PATCH).
- **Errors.** `{"error":{"code","message","detail"}}`. Branch on `code`, never `message`.
- **Rate limit.** ~600 req/min → `429` with `Retry-After`.
- **CORS excludes `/api`.** Browser calls are blocked by design → the token lives in Apex only.

## Error codes (enum)
`invalid_token` · `insufficient_scope` · `not_found` · `validation_failed` · `version_conflict` · `invalid_cursor` · `rate_limited` · `method_not_allowed` · `internal_error`

## Resources used

| Resource | Id prefix | Key fields |
|---|---|---|
| `/clients` | `org_` | `name`, `slug`, `version`, `additional_fields` (we store `sf_account_id`, `sf_account_name`, `sf_website`) |
| `/projects` | `prjct_` | `name`, `client_id`, `progress` (0–100), `status`, `version`, `additional_fields` (`sf_opportunity_id`, `sf_amount`, `sf_close_date`) |
| `/tasks` | `tckt_` | `status_id`, `client_id`, `project_id` |
| `/tasks/states` | `tckt_st_` | `name`, `state_type` ∈ `initial \| in_progress \| blocked \| review \| done` |
| `/members` | `prtr_mem_` | — |

## Not available
There is **no workflow / automation / outbound-webhook API** in Veleiro — it's CRUD only. Anything reactive ("when a project hits 100%, notify the seller") must run on the Salesforce side: record-triggered flows for Salesforce events, or **scheduled Apex** that polls `listAll` and diffs for Veleiro-side changes.
