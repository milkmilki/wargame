# Campaign Action Readiness

Campaign ownership and effective manpower are allocation concepts, not proof
that an army can execute a new movement order.

`Simulation._campaign_action_force()` builds the cohort used for both the
launch threshold and dispatch. It contains effective armies that are either:

- Already at the action target or executing that exact action with a real
  movement path, including a road battle interrupting an issued attack.
- Idle at the required rally point (when one is required), with a legal route
  under their own nation's military access rules and no other queued order.

Fighting elsewhere, a stale AI target, and merely entering the target state
do not establish readiness. Route checks reuse the existing planning cache.

Defense rallies at the state center before a new sortie. Rallying later bound
reinforcements continues independently of an ongoing sortie. Offense rallies
at staging for the entry attack and at camp when regrouping after defeat;
cleared Fu detachments can still advance directly to the center.

`_dispatch_campaign_action()` counts troops already executing the action
before issuing new orders. Rejected commands do not consume its troop quota.
The action phase changes only after an existing action or accepted command
establishes execution. Recovering offensive troops keep their front and follow
the collective center objective once available, without contributing readiness.

Current action eligibility uses strict C > 0.9V (conqueror C > 0.45V), with at least one real available army even at V=0. R applies after arrival to determine siege versus blockade. A second wave in HOLD_CAMP requires idle armies physically back at camp; an issued outbound route cannot bypass regrouping. See [manpower requirements](field_manpower_requirements.md) for preparation and allocation rules.
Regression gate: `tests/campaign_action_readiness.gd` in `run_tests.sh`, plus
camp, sortie, battle-report, defeat-regroup, and land/river campaign-chain tests.
