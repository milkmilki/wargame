# Diplomatic Changes and Battle Participation

## Cause

Seed 45678 exposed an administrative lifecycle error. Coalition peace
correctly retained besiegers still hostile to a third nation, but its later
repatriation pass withdrew them merely because the enemy city did not grant
military access. Alliance exit could likewise withdraw an army fighting a
third nation based on its origin city or future route. Both changed army
state and cleared battle_id without removing the battle-side references.

A later arrival could not rejoin: the entry function saw the existing side
membership and returned. The active battle could continue to apply combat
effects to an army that was moving or retreating. This was not a pathfinding
failure or a false positive in the hostile-node audit.

## Contract

- Diplomacy and control changes reconcile actual battle eligibility before
  repatriating ordinary deployments. Enemy-city access is not required for
  a legitimate ongoing siege.
- Active participants retain FIGHTING and their matching battle_id. Revoked
  future routes are cleared without withdrawing the current combatant. The
  normal arrival logic handles a neutral destination after combat ends.
- Administrative exit removes all battle-side references and then releases
  the matching army reference. Cleaning an old battle never changes a newer
  binding. It does not create combat losses or victory rewards.
- Territory settlement reconciles affected sieges before its displacement
  pass, including former defenders and retained third-party attackers.
- A transient active-participant index is built once per administrative
  event. There is no new daily production scan, lock, cooldown or persisted
  state. Battle entry is not changed to silently repair corrupt membership.

## Regression Coverage

`tests/diplomatic_battle_lifecycle.gd` covers unrelated peace, repeated peace,
alliance exit during field combat and siege, idle-garrison repatriation,
third-party control transfer, complete administrative exit, post-combat
revoked destinations and cleanup of old references after a newer binding.
The old implementation failed eight assertions in the initial reproducer.
The expanded suite has 38 checks and is included in `run_tests.sh`.

`tests/coalition_siege_participation.gd` now checks partial peace through the
full coordinator, not only the siege filtering helper. `tests/ai_longrun.gd`
audits both directions of active battle membership daily and rejects duplicate
membership, unmatched army state and missing live battle references. Its
existing hostile-node assertion is unchanged.

## Verification (2026-10-03)

- Lifecycle regressions: 38 checks passed; coalition siege: 30 checks passed.
- Main logic suite: 1172 passed, 0 failed. Shared morale, administrative peace,
  city defection, report locks, direct-center regroup/counterattack and land/river
  campaign chains passed. Dual-million-army war completed 1095 days with zero
  command commit failures and zero duplicate bindings (46.052 seconds).
- All four seeds (12345, 23456, 34567, 45678) completed 1095 days; long-run
  process exited 0. Hostile-node events and bidirectional active-battle binding
  errors were zero in every seed. Duplicate bindings/defenses, overfull pairs,
  cooldown violations and illegal regional declarations were also zero.
- Seed 45678 hostile-node events changed from 602 to 0. Its net captures changed
  from 51 to 48 and living nations from 7 to 9: correcting battle lifecycles
  changes outcomes, without promising faster conquest.
- The 40-nation stress scenario completed 365 days with zero command commit
  failures and `STRESS_PASS` (56.072 seconds, 35 surviving nations).
- Full regression coverage was attempted. The shell's default Python was a
  Windows Store stub and the local Python lacked NumPy; stages 23 onward were
  continued with the bundled Python. All remaining tests passed except
  `ui_disclosure_scene.gd`, which accessed a missing `nation.finance` section
  header at line 77. The stopped test did not exit itself after the script
  error. No UI production code or assertions were changed in this repair.
  Therefore the complete test suite is not reported as green.
- No isolated same-load performance benchmark was run. The million-army
  elapsed-time observation is not a planning performance guarantee.

Raw logs in the parent workspace: `diplomatic-lifecycle-red.log`,
`diplomatic-lifecycle-green2.log`, `diplomatic-lifecycle-full-suite2.log`,
`diplomatic-lifecycle-suite-tail.log`, `diplomatic-lifecycle-suite-tail2.log`,
`diplomatic-lifecycle-longrun.log`, and `diplomatic-lifecycle-stress.log`.
