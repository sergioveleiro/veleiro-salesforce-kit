# Sample API callouts

Every Veleiro call the kit makes goes through `VeleiroApiClient` to `/api/v1` on the packaged Named Credential.

- Production host: `https://app.veleiro.ai`
- Beta host: `https://app.beta.veleiro.dev`

Authorization is `Bearer <subscriber API token>`. On the secure Named Credentials the platform adds that header. On the legacy Named Credentials, Apex adds it. Paths have no trailing slash. List responses are `{"data":[...],"has_more":true,"next_cursor":"..."}`. One resource is `{"data":{...}}`. Writes that send `If-Match` use the stored Veleiro version.

`additional_fields` values below are the mapped Salesforce fields plus the system keys named in each row. Dates are `yyyy-MM-dd`. Datetimes are UTC `yyyy-MM-dd'T'HH:mm:ss'Z'`.

## Clients

| Method | Path | When | Body / query |
|---|---|---|---|
| `GET` | `/clients` | Dashboard, insights, link scan, pull, client matcher, connection check | Query `limit` (`1` for the connection check, `5` when the mapping screen looks for keys already in use, `100` while paging). Optional `cursor`. |
| `GET` | `/clients/{clientId}` | Before a client PATCH | None. `{clientId}` matches `[A-Za-z0-9_]+` (for example `org_…`). |
| `POST` | `/clients` | Account has no client yet | `{"name":"Acme","website_url":"https://acme.com","additional_fields":{"sf_account_id":"001…","sf_website":"https://acme.com"}}`. `website_url` is omitted when `Account.Website` is blank or not a usable URL. Other `additional_fields` keys come from the Account → client mappings. |
| `PATCH` | `/clients/{clientId}` | Account already linked | `If-Match: <version>`. Body is the mapped top-level fields plus `additional_fields` merged with what GET returned. `website_url` is not sent. A `409` with `error.code = version_conflict` retries once with `detail.current_version` when Salesforce is the conflict winner. |

## Projects

| Method | Path | When | Body / query |
|---|---|---|---|
| `GET` | `/projects` | Dashboard, insights, link scan, meetings filter, pulse | Query `limit`, optional `cursor`, and `client_id` when the pulse or the meeting filter is scoped to one client. |
| `GET` | `/projects/{projectId}` | Opportunity panel (live progress) and before a project PATCH | None. `{projectId}` is `prjct_…`. |
| `POST` | `/projects` | Opportunity or other mapped record has no project yet | `{"name":"Acme - Implementation","client_id":"org_…","additional_fields":{"sf_opportunity_id":"006…"}}`. Records that are not Opportunities send `sf_record_id` and `sf_object` instead of `sf_opportunity_id`. Mapped top-level fields are included. `client_id` comes from a mapped field or from the record's Account. |
| `PATCH` | `/projects/{projectId}` | Project already linked | Same merge and `If-Match` rules as clients. `client_id` is not changed. |

## Tasks

| Method | Path | When | Body / query |
|---|---|---|---|
| `GET` | `/tasks/states` | Insights and the delivery pulse | None. Response rows include `id` and `state_type` (`initial`, `in_progress`, `blocked`, `review`, `done`). |
| `GET` | `/tasks` | Insights (all tasks) and the pulse (one project) | Query `limit`, optional `cursor`, and `project_id` for the pulse. The kit reads `status_id`, `logged_minutes`, `is_archived`, `project_id`, and `client_id`. It does not create or edit tasks. |

A token without the `task` scope gets `403` `insufficient_scope`. The pulse reports that as "not switched on" and does not treat it as a failed sync.

## Meetings

| Method | Path | When | Body / query |
|---|---|---|---|
| `GET` | `/meetings` | Account panel (`client_id`) or Opportunity panel (`project_id`) | Query `limit` plus `client_id` or `project_id`. Rows include `id`, `url`, `title`, `status`, `client_id`, `project_id`, `start_time`, `end_time`, `transcript_status`. `url` is stored and shown as returned. |
| `GET` | `/meetings/{meetingId}/transcript` | User opens one meeting | None. `{meetingId}` matches `[A-Za-z0-9_]+` (for example `bot_…`). Response `data` includes `source`, `text`, and `participants[]` of `{name, email}`. |

A token without the `meeting` scope gets `403` `insufficient_scope`. The panel explains that in one line. No other call fails because of it.

## Not called

The kit does not call `/members`, and it does not POST or PATCH tasks, meetings, or transcripts. There is no inbound call from Veleiro to Salesforce.
