# Regional Strategy

Founding geography (`Nation.environment_kind`) adds land preference only. The
seven types are farm, nomad, sea, highland, river, lake and forest. Immutable
state-seat profiles are prepared once by `NationEnvironment`; no daily mesh
scan occurs. A new business-region score gains `0.15 * affinity`, averaging each
state's affinity by its land area once, without counting Fu a second time.
A new state objective gains `2.0 * affinity` in `selection_score`. Its original
economic/strategic `value` remains unchanged for diplomacy. Region and objective
hard gates, committed objectives, defensive allocations and within-state Fu
ordering retain their existing rules. Shared campaign proposals use the existing
requesting/anchor nation's type; they remain one component-wide plan.
Objective cache keys include the requesting nation and its environment kind.

Classification priority is low steppe/desert (<1500 m), highland (>1300 m),
adjacent large lake (at least five connected water cells), deterministic coastal
selection (harbor 35%, otherwise island 40%, otherwise coast 8%), adjacent/on
major river (six times existing river threshold), inland forest/tundra/wetland,
then farm. Small islands contain at most six original provinces. The coastal
hash uses the world seed and province ID and never advances simulation RNG.
Agricultural potential is normalized from the existing 0–110 scale. Capital
relocation, territory loss and succession never change the founding type;
new fiefs and local rebel states derive it from their founding state seat.

Each ruler retains one business-region target, represented by a city anchor
rather than a partition number. Administrative states follow their center's
trade region; docks and politically inactive land do not count toward completion.
Completion includes the nation's peaceful suzerainty system, not ordinary allies.

Rulers may select another reachable territorial neighbor after integration by
default, without waiting for succession. The cautious trait retains a completed
goal instead; it takes precedence over conqueror, martial and ambitious profiles.
Existing offensive prohibitions also prevent retargeting. Succession applies the
same eligibility rule to the new ruler, while unfinished goals remain inherited.
The next region is compared with the current capital's region; moving the
capital does not retarget an active goal. Existing fronts may finish their state,
while newly selected fronts and prewar targets must satisfy the shared policy.
Legal recovery and internal suzerainty wars remain exceptions.

Environment similarity uses mean absolute latitude and raw height samples,
not output multipliers. Its weights and latitude-output knots are centralized in
`RegionalStrategy`. Geography and political control have separate revisioned
indices; capture invalidates control, not geography. Regional rivalry replaces
global unification pressure. The existing resource and peace era schedule is
unchanged and no longer contributes to rivalry.

New defensive alliances favor weak systems. Peaceful suzerainty members share
one strength total using the existing national-power estimate. A system at least
1.5 times the independent-system average or 20% of world power caps either side's
alliance score at 0.75, below the acceptance threshold of 1.0, after ruler modifiers.
Weak pairs retain the previous scoring. Ordinary proposals and prewar alliance
recruitment share the cap and acceptance prefilter; existing alliances, vassal
relationships and departure rules are unchanged. Strength caps are built once
per diplomatic evaluation batch, with civil-war branches counted separately.

Concurrent-war limits and war-desire overextension/distraction count distinct
active `war_id` values, not hostile alliance members. The enemy-country list
still drives combat and diplomatic contacts. Unidentified hostile pairs remain
separate; war-ID reassignment and merging invalidate diplomatic evaluation caches.

Conqueror rulers give their own real armies a base attack/defense multiplier of
5.0, retaining existing trait modifiers and morale. Offensive manpower demand
is `ceil(0.5 * (R + V))`; other rulers use 1.0. Staging and prewar previews apply
the same policy to `G + V` for states with Fu. Active sieges apply it only to R.
R and V remain unmodified raw values. Shared fronts use the anchor ruler's
policy, but allied armies retain their own ruler's combat modifiers. The
allocator's 45000 minimum per front and defensive demand are unchanged.

Generated finance and food weights include latitude before integer apportionment.
The symmetric smooth curve has knots at absolute latitude
`0:0.30, 18:0.55, 25:1.00, 35:1.00, 45:0.45, 65:0.10, 90:0.05`.
These are abstract production weights, not historical city-output ratios;
city density, manpower and trade do not receive another multiplier.
Global output targets and existing bounds are preserved. Saved maps contain final
outputs and an optional latitude multiplier; loading never reapplies penalties.
Legacy maps and nongeographic fixtures default to a multiplier of one.

Regression gates: `tests/war_count_and_conqueror.gd`,
`tests/regional_strategy.gd`, `tests/latitude_output.gd`,
`tests/campaign_chain_e2e.gd`, and `run_tests.sh`. The regional tests also cover
the coalition objective cache's proposer identity and snapshot/history anchors.

Coalition target selection scores actual territorial neighbors first and uses
existing dock expeditions only when no legal frontier target exists. Shared
planning caches alliance membership and the unchanged garrison requirement R
for one planning batch, with political, administrative and garrison revisions in
the keys. Field strength V remains dynamic; this cache does not freeze armies.

`tests/regional_planning_benchmark.gd` measures a fixed forty-nation military
workload with three warmups and twelve timed samples. Set
`REGIONAL_BENCH_PROFILE=1` for objective/allocation/execution breakdowns. Keep
the same scenario and front count when comparing revisions, rather than
comparing evolving simulations with different war counts.

Shipping is appended to the commerce graph only. Administrative/state/trade
partitions, regional affinity, administrative distances and military pathfinding
retain the land graph. Sea transport affects actual trade costs and returns,
without changing base city budgets or introducing maritime military movement.
