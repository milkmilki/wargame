# Shared Field Morale

## Decision

Real-army field engagements resolve morale and victory per side, not per
formation. This includes city field engagements inside the siege shell.
Blockade and virtual-garrison assault retain their existing individual rules.

`Army.morale` remains the only persisted morale source. A round aggregates
`sum(size * combat_morale) / sum(size * combat_max_morale)` and projects this
shared ratio onto each formation's own maximum morale. Ruler modifiers enter
the aggregation once. There is no persistent battle morale pool to overwrite
supply losses or require synchronization with army records.

## Round And Arrival Rules

- All living participants, including reserves and pending arrivals, share the
  ratio. Only committed frontline soldiers receive direct combat casualties.
- Existing casualty, base-decay and frontline-starvation coefficients erode
  the surviving side's collective morale capacity. Effective side morale
  remains the basis of combat efficiency and the `0.15` rout threshold.
- Arrivals keep their own morale until the next round. High-morale arrivals
  can raise the shared ratio; low-morale arrivals can lower it. There is no
  separate reinforcement bonus or accumulated reinforcement allowance.
- An already completed engagement cannot accept arrivals. Repeated entry
  cannot duplicate participants. Only a genuine other active engagement
  prevents entry; stale army battle IDs do not.
- Supply losses between rounds remain in army records and enter the next
  aggregate. Administrative exits stop receiving subsequent combat losses.
- Field participants do not individually exit on morale. The siege shell and
  city evacuation also defer to the collective field outcome.

## Settlement And Compatibility

After the round writes shared morale, defeated survivors retain the existing
pursuit attrition and real retreat paths. Qualified winning survivors receive
the existing 10% establishment and 20% maximum-morale rewards once. Different
individual morale maxima do not split a road battle's winning-side outcome.

An attacking city-field winner returns to blockade or garrison assault on the
next day. Later defenders trigger a new field engagement using actual current
army values. Each battlefield has its own morale; front combat-report locking
still lasts until all related real field engagements finish.

Native snapshot schema is 19, without obsolete reinforcement allowance arrays.
Combat logs carry rules version 3, formation maxima, ruler modifiers and
the actual funding multiplier. Funding affects attack/defense, not shared
morale or morale recovery. See [military_funding_and_food.md](military_funding_and_food.md).
Earlier rule-version logs are rejected rather than replayed under new rules.
Maps are unchanged.

## Verification

`tests/field_shared_morale.gd` is a permanent `run_tests.sh` gate. It covers
mixed maxima/modifiers, depleted formations, reserves, high/low morale arrivals,
same-round splitting, sequential arrival, administrative removal, supply losses,
collective road retreat, siege pre-round cleanup, snapshot shape and replay.

The same script accepts `-- --benchmark`: 160 formations and 3,000 measured
rounds after 200 warmup rounds, with size/morale reset outside the timed region.
On the local Windows Godot 4.7.1 build, the initial before/after measurement was
1,905.043 versus 1,639.694 microseconds per round (13.9% lower). Final isolated
verification measured 1,746.699 microseconds, still 8.3% below the baseline;
peak time was 3,246 versus 3,764 microseconds. This is a
fixed-workload combat measurement, not a claim about overall game speed or
shorter wars. The script also prints a full-battle duration/casualty/rout trace.

Final checks: 37 focused assertions; 1,172 main-suite checks; complete
`run_tests.sh`; 10,000-case combat-statistics groups; 40-nation/365-day pressure;
runtime AI, supply and reinforcement frame-slice equivalence; land/river
campaign chains; and 1,095-day double-million-army combat. The final city-exit
refinement was additionally checked against the main suite and all affected
siege, defection, report-lock, regroup, chain and million-army regressions.
The million-army run reported zero command failures and duplicate bindings.
The reserve-heavy 60,000 versus 45,000 field trace ended after 41 rounds,
with 18,424/21,551 combat casualties and zero individual morale routs.
