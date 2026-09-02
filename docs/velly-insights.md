# Velly insights

**Velly** is the Veleiro mascot, used here as an AI-style copilot that turns *delivery* data into *sales* actions for the seller. It appears as a health score + next-best-action on the Account page (`veleiroInsight`) and as a natural-language briefing + queues on the home dashboard (`veleiroBriefing`).

## It's grounded, not scripted
The score is deterministic and computed from **real** Veleiro signals in `VeleiroInsightService.score()`:
- `progress` (0–100) and `status` of the client's projects
- days since `updated_at` (a stall / momentum proxy)
- count of tasks whose state `state_type = 'blocked'` (Input Required / Action Needed)

## The rules (first match wins)

| # | Condition | Health | Motion | Meaning for the seller |
|---|---|---|---|---|
| 1 | ≥1 blocked task | 🟠 Choppy waters | `unblock` | Client is blocking delivery — a nudge protects the renewal |
| 2 | `progress==0` & stalled ≥14d | 🔴 Off course | `protect` | Drifting — #1 churn signal |
| 3 | `progress==0` & stalled ≤7d | 🟡 Just set sail | `onboard` | Fresh kickoff — set the first milestone |
| 4 | stalled >21d | 🔴 Off course | `protect` | Momentum stopped |
| 5 | `progress≥95` | 🟢 Smooth sailing | `reference` | Ask for a reference / case study |
| 6 | `progress≥30` | 🟢 Smooth sailing | `expand` | Healthy — expansion play |
| 7 | else | 🟡 Steady | `nurture` | On track — watch for an opening |

## Queues (dashboard)
- **Expand now** ← `expand`, `reference`
- **At risk** ← `protect`, `unblock`
- **Needs attention** ← `onboard`, `nurture`

## Tuning / extending
- Change thresholds or copy directly in `score()`. Keep every branch tied to a **real signal** so insights never contradict what's on screen.
- Add a coverage test in `VeleiroInsightServiceTest` — use the `oneProject(progress, status, daysAgo)` helper to drive a specific branch.
- The score → color mapping used by the LWCs: ≥70 green, 45–69 amber, <45 red.
