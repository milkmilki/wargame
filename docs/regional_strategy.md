# Regional Strategy

Each ruler retains one business-region target, represented by a city anchor
rather than a partition number. Administrative states follow their center's
trade region; docks and politically inactive land do not count toward completion.
Completion includes the nation's peaceful suzerainty system, not ordinary allies.

Ordinary rulers retain completed goals until succession. Conquerors and rulers
with martial or ambitious traits may select another reachable territorial
neighbor after integration. Existing offensive prohibitions take precedence.
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

Generated finance and food weights include latitude before integer apportionment.
Global output targets and existing bounds are preserved. Saved maps contain final
outputs and an optional latitude multiplier; loading never reapplies penalties.
Legacy maps and nongeographic fixtures default to a multiplier of one.

Regression gates: `tests/regional_strategy.gd`, `tests/latitude_output.gd`,
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
