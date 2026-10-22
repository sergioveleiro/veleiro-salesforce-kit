# Veleiro API contract

What the integration relies on. All of this is enforced by `VeleiroApiClient`; read it there before changing behavior.

- **Base / auth.** `Base_Url__c` = `callout:Veleiro_API/api/v1` — routes through the `Veleiro_API` Named Credential, which holds the host (`https://app.veleiro.ai` by default; `https://app.beta.veleiro.dev` for beta). Do NOT use a raw URL. Auth `Authorization: Bearer <token>`, server-to-server only.
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
| `/tasks` | `tckt_` | `url` (link al board, **se guarda tal cual**), `title`, `status_id`, `client_id`, `project_id`, `assignee_ids`, `labels`, `points`, `logged_minutes`, `files` |
| `/tasks/states` | `tckt_st_` | `name`, `state_type` ∈ `initial \| in_progress \| blocked \| review \| done` |
| `/members` | `prtr_mem_` | — |
| `/meetings` | `bot_` | `url` (link al portal, **se guarda tal cual**), `title`, `status`, `client_id`, `project_id` (**nullable**), `start_time`, `end_time`, `transcript_status`, `transcript_id`, `version` |

## Reuniones (`/meetings`)

Solo lectura, desde octubre de 2026. `GET /meetings` filtra por `project_id`, `client_id`, `updated_since`, `created_since` e `include_archived`; hay `GET /meetings/{id}` y `GET /meetings/{id}/transcript` (este ultimo con su propio limite de rate, aparte del general).

Tres cosas que cambian como se consume:

- **Una reunion cuelga siempre de un client y solo a veces de un project** (`project_id` es nullable), asi que el panel de Account ve mas que el de Opportunity.
- **El `url` viene hecho.** Es `https://app.veleiro.ai/a/partner-portal/meetings/<bot_...>/` y el schema pide guardarlo tal cual: armarlo a mano funciona hoy y se rompe el dia que el portal cambie de ruta.
- **La lista pagina por `updated_at` descendente**, no por la fecha de la reunion. Para mostrar "las ultimas N reuniones" hay que pedir una pagina y ordenar por `start_time` del lado de Salesforce (`VeleiroMeetingService` lo hace).

## Tiempo invertido (`logged_minutes`)

Cada task trae los minutos que el equipo registro contra ella, de todos los miembros. Es el numero que el kit pinta como *tiempo invertido* en los paneles (`VeleiroPulseService`).

Un detalle de la API que manda sobre el diseno: **registrar tiempo NO mueve el `updated_at` ni el `version` de la task**, asi que `updated_since` no sirve para traer "solo las horas nuevas". El total se recalcula leyendo las tasks del project, y por eso el pulso de una Account se corta en un maximo de projects en vez de recorrerlos todos.

`/tasks` filtra por `project_id` (no por `client_id`): para una Account hay que listar primero sus projects.

**El scope `meeting` es nuevo y las API keys nacen sin el.** Una key emitida antes recibe `403 insufficient_scope` aunque el token sea valido; hay que agregarselo en el portal de Veleiro, key por key. Lo mismo vale para `task`, que es lo que necesita el pulso de entrega. Por eso el kit trata ese codigo como "todavia no esta encendido" y no como una falla.

## Not available
There is **no workflow / automation / outbound-webhook API** in Veleiro — it's CRUD only. Anything reactive ("when a project hits 100%, notify the seller") must run on the Salesforce side: record-triggered flows for Salesforce events, or **scheduled Apex** that polls `listAll` and diffs for Veleiro-side changes.
