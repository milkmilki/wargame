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

## City Battle Supply Anchors (2026-10-13)

The city-defense side identifies allegiance, not local ration ownership.
Relief formations retain their rear `location_city` supply anchor after
`move_to`/`move_progress` report arrival at the battlefield. These formations
use the ordinary logistics graph and actual warehouse withdrawals; entering
the defending side must not replace that result with the target city's stock.
An army on a road likewise keeps ordinary supply. A closed rear route still
causes a real shortage.

The 2026-10-13 fix still kept virtual city garrisons and formations already
stationed in the besieged city locally isolated. The resident field-formation
case is corrected by the 2026-10-15 follow-up below. Established ration costs
and the existing fixed city siege clock remain unchanged. One shared predicate governs the daily
supply-plan exception, worker preparation, shortage-pressure exception and
the siege clock's local withdrawals/status updates, preventing both a later
false-zero overwrite and duplicate field-formation food charges.

`field_battle_supply` reproduces the old failure before the fix and passes
129 checks afterward: arrived/approaching relief, empty/nonempty city stocks,
exact capital/local withdrawals, real combat attributes, blocked roads and
sync/frame byte equivalence. The user's seed-1 Eurasia world was also rebuilt
to the screenshot's day-276 battle (7,494 versus 12,487 soldiers). Applying the
fixed supply settlement to that same state feeds both Lan2 relief formations
from the real capital stock: supply becomes 100%, effective fire 136,059.620
and average defense 10.917, while the target city retains zero food. This
verification does not rewind earlier casualties or predict an unchanged war
outcome when starting a fresh simulation with the fix.
The final full regression run passed all 163 entries, including the real
reverse-war annexation chain and the 365-day sync/frame equivalence scenario.

## Atlas Terminal Attack Supply (2026-10-14)

Splitting a hostile final attack road into ownerless traffic junctions used
to sever logistics after its first segment. Movement allowed the target's
district, but the warehouse field correctly excluded that district; the
formation's next rear junction therefore had no warehouse distance. This
was a segmentation bug: the same unsplit road supplied the formation from
its friendly endpoint.

Attack supply now joins a query-local corridor in the actual hostile target
district to the existing rear warehouse field. The corridor traverses traffic
junctions and terminates at friendly settlements; it cannot pass an uncaptured
enemy settlement, another foreign district, enemy road presence or a closed
road. A field encounter keeps its committed attack destination; arrived
besiegers use the battle's target. Resident field defenders follow the
2026-10-15 rule below rather than automatic local isolation.
Real warehouse withdrawals and the existing distance-consumption formula
remain the source of the supply ratio.

Stationary attack queries include the destination in their daily source and
weighted-loss keys. They cannot reuse the persistent owner/city cache of an
idle formation, and refresh terminal-road interdiction every day even when
the ordinary rear field is unchanged. Worker aliases share only matching
owner, rear junction and target. No global hostile logistics permission,
snapshot field or extension interface was added.

The user's PID34836 log identified seed1, 40 initial nations, Eurasia mask
(20–55 north, -15–145 east), and a final day565. A same-parameter rerun of the
pre-fix source reproduced day510 battle72 at Changyin: attacking formations
19/130/126 each had 11,658 soldiers, supply0 and a rear anchor at junction513;
Badong warehouse128 still held 29,673 food. Applying the fixed daily settlement
to that reproduced state gave all three supply1 while the city's empty local
stock and the then-isolated resident defender remained at supply0. The original log contains
periodic summaries, not a restorable runtime save; this is a reproduced case,
not a claim of byte-identical recovery of every user action.

`atlas_attack_supply` covers additive unsplit/split marching loss, field
contact, actual siege entry/withdrawals, resident and idle isolation, empty
warehouses, foreign districts, hostile settlements, road closures and enemy
interdiction. Warm-cache interdiction/reopening uses both synchronous and
worker settlement and compares complete native snapshots byte-for-byte.
The final dedicated test passes 91 checks. All 17 selected supply/access/war
regressions passed; after adding field-contact coverage, nine relevant entries
were rerun and passed, including compilation and the shared suite (502/0).
The final seed1 Eurasia run reached day565 with no territory, road occupancy,
army/battle binding or resource-stock audit failures (PID30840). These runs
validate the corrected rules; their war outcomes need not match the old log.

## Resident City-Field Supply (2026-10-15)

A city battle remains a `SIEGE` object while real defending field formations
fight under field-combat rules. The previous local-food predicate incorrectly
treated every formation physically stationed at that city as an isolated
guard. Most non-warehouse state capitals have no local food stock, so this
skipped reachable rear supply and repeatedly reset the defender's supply to
zero. The resulting zero fire/defense and starvation were real simulation
effects, not just an incorrect detail label.

All real field formations now use the ordinary accessible warehouse network,
including troops stationed at the city before battle entry, resident defenders
and relief formations. National food remains collected at the capital
warehouse; vassals share their existing food pool. Ordinary cities have no
independent field-food reserve: even residual `food_storage` cannot feed field
troops. The initially retained local fallback was removed following the user's
clarification. Only a registered warehouse can supply a field formation.
Troops stationed at their capital warehouse may draw its real stock at zero
distance, including while that warehouse is excluded from rear exports by the
existing siege rule. Empty or unreachable legal warehouses produce genuine
shortage or partial supply. The daily supply settlement charges the full
establishment once. The fixed city food clock continues separately for virtual
defense and cannot charge real field rations again or overwrite their supply result.
The global siege flag, hostile attack corridors and warehouse distance fields
are unchanged. Source caches and worker aliases account for the besieged city,
so warehouse self-supply refreshes after stock exhaustion or restocking and
real field formations never inherit a virtual guard's local-only source result.
Daily queries reuse the prepared siege set rather than scanning battles per
formation. No snapshot/API change is needed
(runtime schema30, extension API7).

The user's `run-2026-10-15T03-49-31-29600-64515512` log identified baseline
`5b0b1fc`, seed1, 40 countries and the Eurasia mask (20–55 north, -15–145 east).
Rebuilding its initial map reproduced six affected formations by day175,
including Tuole, Yuncheng and Zhengling. At day134, Tuole's defending army178
had zero supply although its unobstructed rear route reached warehouse117
with 22,265 food. Restoring that same frozen state and comparing the old
local-only predicate with the corrected predicate changes supply0 to supply1,
effective fire0 to 93,259.287 and defense0 to 16.767. The warehouse pays one
additional actual ration; local stock remains zero and the random stream is
unchanged. This comparison isolates the faulty rule; it does not claim future
war outcomes remain unchanged.

`city_field_defender_supply` passes 226 checks, covering same-country/allied
resident field troops, ordinary city stock rejection, real road cuts, empty
warehouses, warehouse registration, capital stock exhaustion/restocking,
virtual guards, self-supply, role/cache transitions, displayed supply and
combat attributes, no duplicate food charges, random-stream preservation and
sync/frame byte equivalence. `field_battle_supply` now passes 175 checks with
resident, arrived and approaching defenders; its isolated fixture explicitly
cuts the real rear route. `field_establishment_costs` retains all 34 checks
using complete supply withdrawals rather than discarded supply plans.
All 23 selected supply/access/war regressions pass, including native/GDScript equivalence,
365-day sync/frame equivalence, positive field victory and the real original
defender counterattacking and annexing the declarer. The shared suite also
passes 504 checks. Headless timings are correctness evidence, not GUI or
performance measurements.

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
