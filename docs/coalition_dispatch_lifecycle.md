# Coalition Dispatch, Rallying, and Counteroffense

The scheduler selects due war components before opening the command batch.
That batch includes the frozen armies of every normal-AI member of those
components, independently of the national economic/AI rotation. Empty army
snapshots are explicitly empty. Custom policies and armies created after the
tick snapshot are not automatically commanded.

Component scheduling stores the next due day. Normal planning schedules ten
days ahead; field-report completion and a newly issued camp sortie schedule
the affected component for the following day. Ordinary arrivals do not wake
the scheduler. A same-day batch cannot consume a post-combat next-day wake.

## Allocation Contract

- Defense receives troops at the state center. Offense receives them at its
  staging point or established camp; launched tactical actions keep their
  own deployment targets.
- Candidates use their owner's military access to the real receiving point.
  Target-root path fields are reused across friendly origins. Enemy-node
  origins use the existing forward path field.
- Unreachable idle troops lose their front binding but retain their war
  binding. In-flight legs and combat-locked fronts are not reallocated.
- Unassigned reserves, waiting war-pool troops, and troops released from
  completed tasks fill demand without spending the transfer budget.
- Active-front transfers remain limited to three armies per country per
  batch. Defense may donate only unlocked, idle surplus above its demand.
- Defense gaps are filled first, then both offensive floors of 45000, then
  the least fulfilled offensive front. Existing offensive fronts do not
  swap troops in response to ordinary requirement fluctuations.
- Each deficient front generates and sorts its candidate queue once.

`GameState.campaign_defense_context()` is the shared read-only definition
of a defense task: effective invasion, an issued valid incoming route,
related siege, or enemy-held Fu. A diplomatic objective alone is a warning,
not a permanent allocation obligation. Fu recapture reuses ordinary attack
readiness and selects an executable frontier rather than an inaccessible
rear target. Finished, unlocked defense releases troops into the original
war pool, allowing a real same-war counterattack in the same planning cycle.

Actual effective manpower and frozen combat reports retain their separate
meanings. Allocation also checks deployment feasibility; it does not rename
or inflate actual C. Reports and details expose `rally_idle_arrived` at the
receiving point, without claiming those troops are guaranteed to launch.

## Measured Regression Results

Deterministic fixtures in `tests/coalition_dispatch_lifecycle.gd`:

| Metric | Previous behavior | Current result |
| --- | --- | --- |
| 30000 assembled vs. demand 12500, member outside rotation | No order | Actual sortie; zero commit failures |
| Six unbound armies, demand 90000 | Three-army first-cycle cap | 90000 assigned in one cycle |
| Unreachable idle troop filling a defense gap | Retained phantom commitment | Zero phantom occupants; reachable reserve assigned |
| Active-front transfer budget | Three, also spent on initial mobilization | Three; initial mobilization separate |
| Finished defense to counterattack order | Could retain warning-only defense | Same planning cycle, original war binding |
| Physical rally travel | Mixed with scheduling failure | 25 travel days, 5 planning-wait days; sortie on day 30 |

The travel fixture fixes its road distance; it does not change production
march times. These are controlled reproductions, not world-wide averages.
The suite also covers empty/custom/frozen batches, war isolation, ordinary
arrival timing, report locks, two fronts, and actual movement commands.

Fixed 40-country front-creation benchmark uses seed 12345, 15 final fronts,
three warmups and 12 timed samples. Before: average 171.801 ms, peak
174.874 ms. Final code: average 132.605 ms, peak 136.271 ms (22.8% lower
average time). This measures campaign planning, not the entire AI tick.
Reusing bloc membership across participants removes repeated topology work;
it does not imply that every substage became faster. Candidate matching
still depends on the number of fronts; no strict O(army count) claim is made.

Final fixed-load profiling totals, including the three warmups:
objective scoring 1598.88 ms / 1290 calls, allocation 276.61 ms, and
offensive execution 150.07 ms. Correct rally validation and dispatch add
work in these stages; topology reuse reduces overall planning time.

The new dispatch gate contains 67 assertions. The main regression suite
contains 1171 assertions. The 40-country 365-day stress scenario passes
with zero command commit failures. The million-army scenario runs 1095
actual days with 1005000 initial troops per side and independently audits
war-pool totals and front bindings every day; commit failures and duplicate
bindings are zero. Completed land/river chains also verify real occupation,
camp progression, and the next state's defense/offense transition.

Run `run_tests.sh` for the permanent gate, land/river campaign chain,
battle-report locking, and the 1095-day million-army war audit. Run
`tests/ai_40_nation_stress.gd` and `tests/regional_planning_benchmark.gd`
separately for the stress and fixed-load performance reports.
