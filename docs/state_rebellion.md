# Administrative State Rebellions

Local uprisings inside a peaceful vassal realm put the parent, its sovereign
overlord and all peaceful direct/indirect fellow vassals at war with the rebels.
All participants share the parent's war ID and the 360-day minimum-war lock.
Ordinary foreign allies stay neutral; this grants no new transit rights or
automatic armies and does not bypass readiness, supply or campaign allocation.
Existing city capture and suppression cleanup release the realm's war bindings.
`regional_rebellion_realm.gd` covers real submissions, nested vassals, foreign
alliance exclusion and a sibling vassal's actual siege victory and cleanup.

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
all parent-controlled land in that state. A new rebel nation requires the complete
state to be both controlled and legally owned by the parent, and uses its seat as
the capital. Partial-state, cross-state and third-party legal territory cannot be
used to found a new rebel core. Rejection happens before creating a ruler, drawing
random values, raising troops or moving resources. Road closure alone does not
repartition a state.

Peace recognition requires control of an original uprising seat. Retaining only
a core prefecture is insufficient. When the seat remains with the rebel, the
state's parent/rebel legal land transfers together, including prefectures the
parent has recaptured. Direct recognition and coalition peace use the same
read-only member selection, and returned prefecture stocks follow the recipient's
physical food pool. Foreign legal territory in an already mixed legacy
state is protected. A defeated residual-prefecture rebellion is absorbed through
the ordinary suppression and cleanup transaction.
When a third country inherits an eliminated parent's legal core, obsolete active
rebellion records end once as external interference; cleanup does not revive the
parent or overwrite the successor's title.

Ordinary coalition peace and the direct occupation-recognition entry point share
one seat-based planner. Capturing only a prefecture restores its old legal owner;
capturing the seat confirms the opposing settled side's whole-state territory to
the actual seat controller. Suzerainty dissolution also settles internal land by
the seat, rather than permanently confirming each occupied prefecture separately.
Temporary control can still differ while fighting continues; docks remain
separate nodes and unrelated third-party legal claims are not confiscated.
An unresolved occupation from another war defers cession of that entire state.
Only the settling war's temporary occupations are restored; external controllers,
sponsors and war IDs remain. This guard also applies to direct rebel recognition.

Enclave cleanup groups owned members of a state into one indivisible settlement
unit. It cedes only complete, legally owned and controlled states; contested states
and legacy prefectures under another legal seat cannot be transferred alone.
This administrative grouping does not create roads or grant military passage.

The Korean-peninsula Chengdu case was reproduced with the original `e70556b`
source and original seed-1, 40-country Eurasia template from day zero. On day 4830,
Wei rebelled with seat Weicheng (57) and Chengdu (255). The parent recaptured
Chengdu on day 4871. On day 4980, the parent's peace with countries 30/47 triggered
`peace_enclave_transferred`: the city-level cleanup ceded Chengdu alone to Xing
(92), although Xing had not captured it and the Wei rebellion was still active.
Replanning that exact pre-commit state with whole-state cleanup leaves Chengdu
with the parent and preserves the separate rebellion war. The synthetic real
transaction regression also verifies later whole-state recognition after the
360-day lock; it does not require the revised simulation to retain old outcomes.
In the same pre-commit state's revised continuation, the parent retook the seat
and suppressed Wei on day 5149; both cities remained with the parent at day 5250.
The dedicated suite checks both recognition and suppression rather than requiring
the original run's independent-Wei outcome. Its 212 checks and the main suite's
504 checks pass, alongside real defender-counterattack elimination and daily
synchronous/frame-sliced equivalence regressions.

An active, unrecognized local rebel capital is a military headquarters, not a
sovereign capital for capitulation. A siege victory transfers its actual control
and applies the ordinary same-state defection rule while preserving existing
legal title. Freeze eligible dependent cities before the first transfer, since
that transfer can relocate the rebel capital into a dependent city. Other rebel
states continue resisting; only complete territorial loss triggers elimination
cleanup. The 360-day voluntary peace lock does not prevent military recapture
or cleanup after elimination. Recognized independent nations and vassal civil
wars retain their existing capital-resolution rules.
Monthly political transfers also reuse the siege-participant reconciliation
entry point, so old city defenders cannot keep losing troops in an obsolete
battle after the political change.

Monthly grouping is linear in cities plus active rebellion records; each parent
reads only its own state reports. No new daily task or regional route search is added.
Regression gates: `tests/administrative_state_integrity.gd` (whole-state enclave
cleanup, real forward/reverse peace, direct recognition, dissolution, partial-core
rejection, third-party protection, resource conservation and idempotence),
`tests/administrative_peace_settlement.gd`, `tests/peace_enclave.gd`,
`tests/regional_rebel_capital_capture.gd` (siege victory before
and after the peace lock, surviving second state, rebel counterattack, and
recognized sovereign capitulation),
`tests/state_rebellion.gd`, `tests/politics_trade_smoke.gd`,
`tests/war_campaign_pool.gd`, and `run_tests.sh`.
