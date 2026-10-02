# Prewar Ultimatums and Foreign Dynasties

## Resolution Boundary

Normal AI preparation emits `ISSUE_ULTIMATUM`, not `DECLARE_WAR`. Simulation
revalidates the preparation, resources, ruler, objective, access and truce before
evaluating it. Resolution takes place in the same diplomacy batch. There is no
pending ultimatum, extra timer or per-day military scan. Explicit declarations
used by combat fixtures retain their existing behavior.

Only independent, peaceful sovereign polities without civil-war branches or
unreleased rebellion identities can accept. A vassal initiator can receive a
foreign polity as its own direct subject when its existing war eligibility allows
it. A refusal proceeds through the existing declaration and prepared-army launch.

## Deterministic Score

`UltimatumRules` owns the thresholds and formula. Military intimidation counts
only effective, idle, physically assembled preparation armies which have not
been commandeered by another war/front. ArmyPower already incorporates ruler
combat modifiers; they are not multiplied a second time.

Defending strength comprises effective polity troops physically inside its
territory, capital-state garrison strength and discounted adjacent allied
reserves. Allied assistance excludes other preparation/war commitments and is
capped at half of the core defending strength. Capital-state trade-region
similarity supplies the environment factor; grid fixtures use similarity 1.

```
M = clamp(log2(max(A,1) / max(D,1)) / 2, 0, 1)
score = clamp((20 + 60M + I - R) * (0.35 + 0.65S), 0, 100)
```

At score 80 a polity can annex if its political land-city count is at most one
third of the initiator's peaceful suzerainty land count. Otherwise score 55 is
submission; lower scores refuse. Equality is sufficient. Military points cap at
fourfold power, so arbitrarily large armies cannot override extreme environment
differences. Coefficients are balancing parameters, not historical measurements.

## Political Transactions

`GameState.accept_submission()` attaches an existing sovereign and preserves its
nation ID, ruler/reign, capital, treasury, manpower and army ownership. Children
remain beneath it. The transaction installs the proposed suzerainty, inherited
diplomacy and root grain-pool migration atomically. External alliances are replaced
by the new lord's obligations. Alliance synchronization also merges already-written
WAR edges into the corresponding existing war IDs.
After submission revokes a former external alliance, Simulation reuses the
existing diplomatic repatriation path in both directions. Former allies and
submitted troops stationed abroad withdraw without invented routing casualties;
in-transit troops retain the existing current-segment completion semantics.

`GameState.annex_nations()` annexes the target and all its peaceful subjects in one
territory commit. It builds operations in one city pass and migrates army/group
ownership using original-owner mappings. Single-country annexation delegates to
this same path; coalition-peace draft composition retains its existing planner.
No battle victory, capture loot or routing casualty is fabricated by either
accepted outcome. Technical transaction failure retains preparation instead of
being interpreted as refusal.

Diplomacy batches freeze political identities once. An earlier action changing
alive/overlord/peaceful-root status invalidates queued intentions made under the
old identity. Every ultimatum is additionally revalidated at execution.

## Bloodlines and Display

Political submission is not enfeoffment. Existing family/person IDs are retained,
even when two unrelated rulers share a surname. Foreign rulers keep their names
and receive a title based on the former national name. Their successors and newly
enfeoffed relatives inherit their own surname, not the supreme political lord's.

The family panel has links for the lord, related/foreign subjects and archived
annexed governments. Clicking switches the displayed tree or highlighted ruler;
Back restores the previous selection. Tree switches do not reopen the panel's
pause scope. Annexation keeps every former tree without fabricating parent links.

Native snapshot schema 17 contains sorted trees/members, nation family/person
references, title bases, family revision and allocation counters. Map templates
remain the same format. Genealogies initialize at world creation/loading and
rebirth rather than depending on whether the user opens a family panel.

## Verification

Permanent gates in `run_tests.sh`: `ultimatum_rules`, `peaceful_integration`,
`foreign_vassal_family`, `ultimatum_e2e`. Visual verification uses
`foreign_vassal_visual_smoke` at 1280x720 and 960x540. The long-run audit reports
outcome counts, environment similarity totals and invalid peaceful outcomes.

The fixed 40-country planning benchmark against fc0604a measured 76.451ms before
and 76.871ms after (+0.55%, 12 timed samples). Both audits had zero overfull pairs,
duplicate defense tasks and duplicate army bindings; path-cache entries remained
131. Snapshot hashes intentionally differ because the schema and genealogy
coverage changed. This benchmark covers military planning, not ultimatum scoring
or an overall simulation-speed guarantee.

Fresh stress observations: the 40-country 365-day scenario and its four-country
control passed with zero command commit failures. Four seeds over 1095 days had
11 refusals, zero submissions/annexations and zero invalid peaceful outcomes;
combined net captures were 182. Seed 12345 over 10950 days had seven refusals,
zero peaceful outcomes, 96 net captures, zero duplicate bindings, zero cooldown
violations and zero illegal regional declarations. These natural scenarios do
not establish that peaceful integration is frequent: the approved thresholds and
assembled-force-versus-polity-force comparison are conservative. Dedicated
end-to-end fixtures exercise actual annexation, submission, refusal/invasion,
existing-war inheritance and the 360-day best-effort path without weakening the
production thresholds.

The final `run_tests.sh` rerun after alliance-repatriation integration exited 0.
Final targeted verification also passed the 40-country/160-city runtime serial
versus parallel equivalence check, family-tree smoke/fallback checks, and the
real OpenGL foreign-family panel at both window sizes. The full suite includes
the main 1171-check regression, 319 coalition-pair checks, land/river campaign
chains and the 1095-day double-million-army war (zero command commit failures
and duplicate bindings). Existing exit-time ObjectDB/resource leak diagnostics
remain visible in some legacy fixtures; they are not new ultimatum test failures.
