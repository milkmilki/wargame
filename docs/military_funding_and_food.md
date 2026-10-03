# Money/Food Separation And Military Funding

## Decision

Manpower limits available recruits; food forecast limits sustainable military
scale; the last actual monthly military payment controls combat quality.
This replaces cash creation fees, cash military eligibility, fiscal
demobilization and payment-dependent recovery. It does not add another
resource gate or a persistent combat-quality state.

Recruitment retains formation limits and legal deployment nodes. Field refill
retains manpower reserves, monthly caps and legal reinforcement routes.
Virtual garrison refill retains manpower, food supply, capacity and monthly
caps, but no payment restriction. Political arrears consequences, rebellion
and the existing peace preference remain.

## One Combat Contract

After income, tribute and court expense, pay up to the treasury balance:

    p = clamp(actual military payment / full military expense, 0, 1)
    funding_multiplier = 0.5 + 0.5 * p

Zero expense yields p=1; initial payment is 1. Full funding is the ceiling.
Underfunding does not accumulate debt and does not slow morale recovery.

Army.combat_attack() and Army.combat_defense() apply funding once, independently
of ruler effects. Base attack/defense never mutate. Virtual garrisons use the
same owner's payment without inheriting field-army ruler multipliers. Existing
city defense, terrain and supply effects remain separate. ArmyPower and
ultimatum garrison estimates use the same effective attributes. Multiple
countries sharing a battle or food pool keep distinct national payment.

Existing derived refresh and battle synchronization update the multiplier
after monthly settlement; creation, transfer and annexation initialize it
immediately. R/C/V and the 45000/90000 task thresholds remain headcounts, not
funding-adjusted strength. There is no unpaid sortie gate.

## Food Qualification And Cash Reporting

ResourceForecastRules returns food_feasible, food_growth_allowed and
gold_shortage. The mixed feasible/growth_allowed contract is removed.

The 360-day event forecast keeps harvest-before-field-supply order,
pre-harvest lows, per-army fractional consumption, warehouse clipping and
shared suzerainty-pool commitments. Growth uses the food recovery budget;
refill and ordinary preparation use candidate food feasibility. Cash cannot
block preparation, ultimatum or declaration, including the existing 360-day
assembly fallback. Manpower, routes, ruler and diplomacy restrictions remain.

Accepted candidate changes update troop/upkeep totals and pooled demand in
the existing batch. No member can spend another member's already promised
food again. The existing small-country survival exception remains; defensive
tasks and existing wars are not forcibly terminated by a failed forecast.

Cash prediction still assumes full military expense, showing the minimum
treasury, date, shortage and reserve target. A negative predicted balance
represents unmet full funding, not a real negative treasury or projected debt.
No future payment rate, conquests, rewards or annual conversion are assumed.

## Removed Conversion And Compatibility

Annual automatic gold/manpower/food conversion, its rule module, allowance
and metadata are removed. Normal trade, tribute and one-time political
resource transfers keep their existing behavior. Current trade purchases
were already zero-filled compatibility fields; this change does not create
a new gold-purchasing feature.

Native snapshot schema remains 19 and stores the existing national payment
ratio, not the derived multiplier. History captures past payment for display.
Combat log rules move from 2 to 3 and record each participant's actual funding
multiplier; old or incomplete logs are rejected explicitly. Maps are unchanged.

## Verification (2026-10-03)

Focused tests cover payment curves, conqueror non-duplication, virtual
garrisons, mixed nations, mirrored casualties/morale, live synchronization,
transfer, annexation, monthly finance, history, log compatibility and replay.
Zero-cash fixtures exercise real formation creation, refill, ordinary and
retreat recovery, preparation, all ultimatum outcomes and refused-entry
movement. High cash cannot override food shortage. Shared-pool sync/frame
tests compare full schema-19 snapshots under actual underfunding.

40-nation pressure completed 365 days: 40 to 132 armies, 35 surviving
nations, zero command commit failures. The dual-million-army fixture completed
1095 days with 1,005,000 initial soldiers per nation, zero command commit
failures and zero duplicate bindings.

Four 1095-day observations (payment sampled for living nations at month end):

| Seed | Final Soldiers | Payment Mean/Min | Unpaid Nation-Months | Starving Army-Days | War Declarations | Cities With Changed Owner |
| --- | --- | --- | --- | --- | --- | --- |
| 12345 | 2664593 | 0.8426/0.0597 | 53 | 1488 | 1 | 23 |
| 23456 | 2062271 | 0.8428/0.1053 | 58 | 5395 | 4 | 72 |
| 34567 | 1578319 | 1.0000/1.0000 | 0 | 10740 | 6 | 53 |
| 45678 | 2633499 | 0.8233/0.0149 | 64 | 5334 | 4 | 41 |

All four had zero battle binding errors, hostile-city stationary errors,
duplicate bindings/defenses, overfull pairs, cooldown violations and illegal
regional declarations. The last column counts cities whose final owner differs
from the initial owner, including political transfers and rebellion; it is not
a count of conquest events or proof of faster unification. Observed starvation
is not eliminated by a frozen forecast: loss, supply routes and deployment
can change later.

Raw logs in the parent workspace: separation-longrun.log, separation-stress.log,
separation-funding-final.log and separation-integration-final.log. Standard
suite logs use the world-war- prefix in the host temporary directory.

Final verification after the combat ordering optimization repeated the full
run_tests.sh suite (1172 main assertions, zero failures), 10000-case combat
statistics, the four-seed observations and the 365-day pressure fixture. The
four seeds retained the exact results above. The native disclosure interaction
fixture passed all 64 checks; no current UI failure was excluded. Funding
passed 56 focused checks and food eligibility passed 15. The separate 60-day
war/diplomacy runtime fixture compared all script properties across synchronous
and worker/frame-sliced execution and passed.

## Isolated Performance Comparison

Baseline: a5000f84a77072f4e40b60071c8ac0550046da51, extracted outside the
working checkout. Godot 4.7.1, identical workloads, no concurrent stress or
simulation jobs. Three alternating before/after passes, 12 timed samples each
after warmup (36 per side). Means below average all timed samples; peaks are
the largest observed sample. Combat samples resolve 200 battles, six armies
per side and ten rounds each, with logging disabled and full funding. The
heterogeneous case varies sizes, attributes and morale.

| Workload | Before Mean (ms) | After Mean (ms) | Mean Change | Before Peak (ms) | After Peak (ms) |
| --- | --- | --- | --- | --- | --- |
| Resource reports and capacity | 70.879 | 71.637 | +1.07% | 82.963 | 86.993 |
| Coalition battlefield planning | 141.431 | 138.318 | -2.20% | 162.554 | 163.914 |
| Combat, uniform armies | 259.256 | 266.332 | +2.73% | 297.357 | 286.176 |
| Combat, heterogeneous armies | 231.507 | 236.905 | +2.33% | 278.893 | 267.899 |

All measured mean changes meet the 5% budget, not a guarantee for every map or
machine. Initial measurements exceeded the combat budget; profiling isolated
repeated physical sorting. The final implementation checks adjacent order and
sorts only if needed, without a persistent cache or altered tie-break rule.
Mirroring, funded sorting and combat statistics were rerun after that change.

Final raw evidence: separation-final-bench-*.log,
separation-final-ai_longrun.log, separation-final-ai_40_nation_stress.log,
separation-final-combat_statistics.log and separation-runtime-final.log in
the parent workspace. Concurrent-suite stress timings are not used as the
isolated performance baseline. Long-run starvation and arrears remain
observations for future balance work, not failures silently removed from data.

The 40-nation stress report now ends each case with largest_power: root nation
ID/name, controlled land cities / all map land cities, territory_share, and
direct/vassal counts. A power is one peaceful suzerainty tree: ordinary allies
are separate and civil-war branches split off. Actual ownership is used, docks
are excluded, unowned land remains in the denominator, and ties use lower root
ID. This final-only summary does not enter simulation tick timing.
The 365-day seed-12345 verification passed: largest root 34 (Dun), 20/200
land cities = 10.00%, all 20 directly held and none held by vassals.
