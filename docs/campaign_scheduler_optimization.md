# Campaign Scheduler Optimization

## Scope

2026-10-02 follow-up to the paired battlefield scheduler. Preserve battle,
movement, C/R/V, ten-day planning, field-report freezing, camp-defeat cooldowns,
and the active-front reassignment quota. No new persistent scheduling state,
snapshot schema, or mutex is introduced.

## Batch Ownership

The old mobilization reservation wrote uncommanded army IDs into
`_ai_planned_armies`. This mixed command deduplication with priority budgeting.
The batch now produces an explicit `mobilization_claims` set and passes it to
national preparation, garrison planning, and individual army decisions.
Claimed recruits wait for their group's next due day; surplus recruits remain
available for national orders. Claims do not bind armies or issue commands.

The allocator publishes its remaining deficits to the same batch context.
The claims query reuses those deficits and only aggregates actual force for
fronts not allocated in this batch. Candidate armies are filtered and sorted
once per country rather than again for each war component. Transfers update
the source deficit as well. Pending battlefield intentions still need a
minimum-force budget; they are not turned into empty active fronts.

Prepared group execution no longer repeats camp-failure and defense-task
maintenance already performed by the batch coordinator. Standalone component
planning retains a complete preparation path for explicit callers.

## Measured Hotspot

Diplomacy already resolved alliance membership once per scoring batch, but
each state's garrison requirement resolved it again through GameState.
The same cached bloc is now passed through the existing resistance queries.
The resistance formula is unchanged; direct callers still resolve their bloc.
The regression fixture reduces alliance resolution from 15 calls to 1 and
checks every state's requirement plus diplomacy invalidation.

Ruler archetype modifiers are constructed once as read-only prototypes before
worker queries. Mutable public reports return copies. Offensive eligibility
reads the prototype's ban directly; no trait changes that ban. Edits to a
ruler select the current prototype without a per-nation stale cache.

Encirclement evaluation reuses eligible roads within its existing snapshot
index, with a cursor-based BFS queue. Ownership, diplomacy, or road changes
require a new batch, as with the original index. An independent legacy oracle
verifies scores, candidate priority, and selected objectives.

## Verification

All new checks are in existing scripts already included in `run_tests.sh`.
They cover actual nonempty command batches, claim/command separation, surplus
garrison orders, army-storage reversal, fallback allied proposers, cooldown
scope, immutable ruler results, and road reuse/invalidation.

Fixed workload: seed 12345, 40 countries, 3 warmup rounds, 12 timing samples.
Before this optimization: average 123.231 ms, peak 125.508 ms. Final isolated
post-optimization measurement: average 76.008 ms, peak 76.968 ms (38.32% lower
average), passing the 5% regression budget. This is the planning workload,
not a claim about overall frame rate. The initial post-change sample was
75.934 ms average. Ten thousand ruler eligibility queries fell from 49.526 ms
to 11.199 ms.
Both snapshots hash to:
`4e4ae9a29338917bd0700e51a92ee6cf5b21ffb1640db41a733040cc93dc9a34`.
Each has 32 pairs and 12 fronts, zero duplicate bindings or defenses, and
131 new AI path-cache entries in round one with zero in subsequent rounds.

| Validation | Result |
| --- | --- |
| Complete `run_tests.sh` | Exit 0; primary suite 1171 passed, zero failures |
| Paired battlefield tests | 319 checks, zero failures |
| Independent encirclement oracle | 488 checks, equivalent scores and objectives |
| Double-million three-year war | 1095 days; zero command failures and duplicate bindings |
| Land / river campaign chains | Second centers captured on days 234 / 235, unchanged |
| 40-country annual stress plus 4-country control | `STRESS_PASS`; zero command failures; all scheduling invariants pass |
| Fixed planning snapshot | Identical before/after SHA256 |
| Whitespace check | `git diff --check` clean |

The final suite initially stopped at the Python map-tool stage because the
system Python lacked NumPy. Re-running the whole suite with the existing
bundled Python dependencies passed; no test was skipped or weakened.

Logs are in the Windows temporary directory: `structure-before-digest.log`,
`structure-planning-final.log`, `structure-full-suite-final.log`, and
`structure-stress40.log`. This turn did not repeat the four-seed or thirty-year
long runs; their earlier results are not presented as fresh validation.
