# Coalition Siege Participation

## Cause

Shared campaign fronts issue capital-attack commands to all participating
nations. The siege entry previously admitted only the first besieger's own
nation to side A. Its allies were rejected, retreated, and later received the
same attack command again. This was a disagreement about battle-side identity,
not a need for another movement lock or planning delay.

## Rule

A siege side can contain a conflict-safe allied bloc fighting the same war
against its opponent. Being allied without participating in that war, or
sharing a war ID without belonging to the bloc, is not sufficient.

City defenders keep their existing military-access rule. A separate allied
challenger bloc may occupy side B only when it is not occupied by city
defenders. The battle remains strictly two-sided. Capture still follows the
existing occupation claim; it is not assigned to a coalition representative.

When diplomacy changes, participants no longer hostile to the city leave
administratively. Remaining hostile besiegers keep the siege, with a valid
attacker and occupation identity. This exit adds no casualty, morale penalty
or victory reward. Existing challenger takeover and field-report completion
remain responsible for their usual lifecycle.

The eligibility query reuses the revision-keyed alliance-bloc cache. No new
persistent fields, daily scans, path searches or snapshot schema are added.

## Regression

`tests/coalition_siege_participation.gd` is included in `run_tests.sh`.
The test reproduces real allied movement from a shared camp, advances 60
blockade days with campaign execution every ten days, then resolves relief
field combat and garrison capture. Both first-arrival orders are covered.
Before the fix, each arrival order recorded 50 rejected-retreat days;
afterward neither records a rejected retreat. Additional cases cover neutral
allies, unrelated co-belligerents, separate wars, allied challengers, city
defender exclusion and partial peace.
