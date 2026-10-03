# Court Expense And Rolling Resource Forecast

## Decision

One resource forecast replaces frozen pre-war fiscal income and independent
multi-year food vetoes. It estimates the next 360 days using present income,
trade, deployment and ruler policy. It does not solve an optimization problem,
simulate battles, assume future conquests, or schedule another daily task.

## Court Expense

RulerProfile owns the fixed rates: conqueror/reformer 10 percent,
inept/tyrant 50 percent, everyone else 30 percent. Additional traits do not
alter the rate. Ruler and trait gold-output multipliers have been removed;
food, manpower, trade efficiency and army upkeep modifiers remain independent.

Monthly expense is floor(max(city income + net trade income + tribute received
- tribute paid, 0) * rate). Income and tribute settle first, court expense
second, military finance third. Payment stops at zero treasury and creates
no court arrears. Conversion and annexation transfers are not income.
Nation stores the last settled rate, amount due and actual payment.
The forecast always budgets the amount due, even when payment was capped.

## Forecast Contract

ResourceForecastRules.evaluate(input, change) is read-only. DiplomacyAI builds
the batch input from national military/cash totals and shared food pools.
Reports include end balances, minimum balances and their days, hard shortages,
soft targets, recovery budgets and denial reasons.

The event loop advances between month boundaries. Daily field food is
accumulated with each army's existing fractional debt; garrison consumption
precedes the half-year harvest, and field supply follows it. Harvests are
clipped to storage capacity. Negative projected balances are retained so a
later harvest cannot hide an earlier shortage. Month-phase callers explicitly
reserve current-day supply that has not yet settled. No army or map scan is
performed inside the pure event loop.

Cash is national; food is evaluated once as the shared suzerainty pool.
Internal pool transfers cancel. Present or smoothed food demand freezes
observed deployment costs. Proposed growth keeps the conservative garrison
production allowance and maximum incremental supply cost. A new offensive
deployment cannot rely on peacetime local supply costs. No new pathfinding is
performed to predict a future supply route.

## Hard Conditions And Soft Reserves

Candidate creation, refill and ordinary offensive preparation must avoid
cash and food shortages throughout the horizon. Human resources, actual
assembly, passage rights and diplomatic restrictions still apply. The
360-day preparation fallback relaxes its original troop threshold, not
resource qualification. Existing war and defensive tasks are not terminated
by a failed forecast. The existing small-country survival exception remains
and can explicitly carry a resource risk.

Gold targets use monthly necessary expense: court, military, trade purchases
and outgoing tribute. Peace uses 36 months, war 6. Food targets use field
and garrison consumption plus exports, capped by warehouse capacity; peace
uses 18 months, war 6. The same ruler reserve-month modifier applies to both
and is clamped at zero. Recovery is spread over 36 months.

Soft recovery limits peaceful army growth and saving budgets, but is not a
second declaration gate. Wartime resource demobilization requires projected
shortage or actual unpaid military expense, not simply a missed reserve
preference. Existing demobilization cadence and lifecycle protections remain.

## Candidate Commitments

Each batch summarizes armies, garrisons and food pools once. A proposed
formation includes its creation payment, per-army upkeep rounding and supply
increment. Refill first distributes deterministic grants and then evaluates
the actual changed formations. Accepted changes immediately update the batch
cash and pooled demand and invalidate derived reports. Stable commit order is
shared by synchronous and frame-sliced execution. Demobilization invalidates
the input after the real mutation rather than reusing pre-change totals.

Annual conversion uses these hard and soft targets, donor protection and
capacity limits rather than equal resource shares. See
[automatic_resource_balance.md](automatic_resource_balance.md).

## Display And Compatibility

Live financial details show court expense, after-court income, forecast lows
and dates, reserve targets and restriction reasons. Repeated redraws reuse
the generated detail payload until its state/selection token changes.
Historical views display recorded court settlement only.

Native runtime snapshot schema is 19. It adds the last court settlement and
removes frozen pre-war income. Deterministic fingerprints cover the new
values. Forecasts and temporary commitments are not persisted. The map format
is unchanged; old native runtime snapshots retain strict version rejection.

## Verification And Limits

The run_tests.sh suite includes court_expense, resource_forecast,
resource_forecast_integration and resource_conversion_forecast. Fixed
fixtures compare 360 forecast days with real monthly settlement and field
supply, including fractional debt and harvest order. Other guards cover
shared commitments, no double creation payment, tribute, capped court
payment, conversion conservation and historical values.

resource_planning_benchmark is a manual fixed-load comparison of 40 nations
and 500 cities, 12 measured batches after one warmup. Monthly fiscal flow
construction is outside that timing in both revisions. ai_longrun reports
resource starvation army-days, unpaid nation-months, expense due/paid,
conversion value and optional forecast timings. Denial counters count
candidate probes, not distinct refused actions.

The estimate is deliberately frozen. Future losses, ruler changes, newly
blocked supplies and changed trade can invalidate it, so each planning batch
rolls forward and commits revalidate. A passed forecast is not a promise of no
starvation or debt in an uncontrolled multi-year simulation. Fixed expense
also does not imply every treasury must stop growing.

## Verification Results (2026-10-03)

Godot 4.7.1 on the development Windows host:

- Complete run_tests.sh exited 0; main suite 1172 passed, 0 failed.
- Four new resource tests passed, including exact fixed-settlement oracles
  and a full native snapshot comparison of shared-pool monthly reinforcement
  in synchronous and frame-sliced execution.
- The separate 40-nation/160-city reinforcement frame comparison completed
  200 days per world: 63 armies compared, 0 differences.
- Land/river campaign chains, ultimatum, family/suzerainty, history, detail
  single-build, cache equivalence and UI checks passed.
- 40-nation pressure completed 365 days, 40 to 127 armies, 35 surviving
  nations, and 0 command commit failures.
- Dual-million-army war completed 1095 days with 1,005,000 initial troops
  per nation, 0 command commit failures and 0 duplicate bindings (45.491 s).

Sequential fixed-load samples (12 after one warmup; no other test running):

| Workload | HEAD Mean/Peak | Working Tree Mean/Peak | Mean Change |
| --- | --- | --- | --- |
| Resource planning, 40 nations/500 cities | 43.291/44.738 ms | 43.668/44.630 ms | +0.9% |
| Military planning, 32 pairs/14 fronts | 84.911/87.524 ms | 84.423/87.252 ms | -0.6% |

Both remained within the 5 percent mean regression budget. The baseline is
HEAD 9ddcfe3; it excludes the pre-existing uncommitted alliance and capital
changes retained in this working tree. This is a same-workload revision
comparison, not an isolated attribution of every timing difference. Military
path-cache additions remained 141 in the first round and 0 thereafter.

All four long-run seeds completed 1095 days. Their resource observations:

| Seed | Starving Army-Days | Unpaid Nation-Months | Court Due/Paid | Conversion Gold Value |
| --- | --- | --- | --- | --- |
| 12345 | 1496 | 0 | 61403/61403 | 26573 |
| 23456 | 4408 | 0 | 51042/51042 | 10559 |
| 34567 | 6860 | 0 | 27325/27325 | 1426 |
| 45678 | 8197 | 21 | 55729/55729 | 3252 |

Across those seeds, duplicate bindings, duplicate defense tasks, overfull
pairs, cooldown violations and illegal regional declarations were all zero.
Pure forecast timing totals were 4.100, 4.487, 3.592 and 4.677 seconds,
respectively (169427, 188741, 147067 and 185491 candidate probes). These
counters count probes rather than distinct denied actions.

The long-run script nevertheless exited 1: seed 45678 recorded 602 hostile
node-stay events. Read-only diagnostics show armies listed in active siege
32 at city 73 while their own state is MOVING, battle_id is -1, on_edge is
false and route progress exceeds 1.0. It reproduces from day 904 in the final
code; it is not a false-positive exemption or a forecast rounding problem.
At completion of the resource-only change, the battle participation/lifecycle
inconsistency remained unresolved. The test assertion was not relaxed.

Follow-up on 2026-10-03: diplomatic repatriation was withdrawing still-valid
third-party combatants without removing battle membership. The lifecycle
repair and expanded regressions are documented in
[diplomatic_battle_lifecycle.md](diplomatic_battle_lifecycle.md). All four
seeds subsequently completed 1095 days with zero hostile-node events and
zero bidirectional active-battle binding errors; seed 45678 changed from
602 hostile-node events to zero. These later outcomes do not replace the
original resource-only observation table above.

Raw manual logs are in the parent workspace: resource-longrun-final3.log,
resource-stress-final3.log, resource-reinforcement-slice-final2.log,
resource-bench-baseline4.log/resource-bench-final4.log and
resource-military-baseline2.log/resource-military-final2.log. Standard suite
logs are in the host temporary directory with the world-war- prefix.
