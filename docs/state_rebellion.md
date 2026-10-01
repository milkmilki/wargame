# Administrative State Rebellions

City loyalty and its low-loyalty counter remain independent, including the
existing vassal-rebellion assessment. Local independence and political
restoration instead use administrative states, not trade/business regions or
connected groups of unhappy cities.

At monthly settlement, one index groups politically active land by its state
center and that center's controller. Only land controlled by the same parent
counts toward the state's mean loyalty and transfers with it. Three consecutive
eligible monthly means at or below 25 trigger the existing political transaction.
The center stores `administrative_rebellion_progress`; ownership transfer,
political reset and administrative partition rebuild clear it. Native snapshots
record it; map definitions do not export this runtime counter.

Capital states, active rebel nations, civil-war participants, active rebellion
cores, wartime occupied land and any owned member still in cooldown block the
state and reset its progress. Third-party land, docks and inactive land neither
count nor transfer. Land held without its state center cannot independently
found a local rebel nation.

The center determines the political destination. A living foreign target receives
all parent-controlled land in that state; otherwise a new rebel nation forms with
the state center as its capital. Transactions reject partial-state or cross-state
lists. Resource sharing, troop defection, uprising mobilization, legal title and
peace rules are unchanged. Road closure alone does not repartition a state.
Monthly political transfers also reuse the siege-participant reconciliation
entry point, so old city defenders cannot keep losing troops in an obsolete
battle after the political change.

Monthly grouping is linear in cities plus active rebellion records; each parent
reads only its own state reports. No new daily task or regional route search is added.
Regression gates: `tests/state_rebellion.gd`, `tests/politics_trade_smoke.gd`,
`tests/war_campaign_pool.gd`, and `run_tests.sh`.
