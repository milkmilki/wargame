extends SceneTree
const Fixture = preload("res://tests/support/native_runtime_fixture.gd")
class CallbackState extends GameState:
	var calls := 0
	func release_nation_war_pool(nation_id: int, war_id: int) -> void:
		calls += 1
		super.release_nation_war_pool(nation_id,war_id)
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func fixture() -> GameState:
	var state := GameState.new()
	for id in range(4):
		var nation := Nation.new(); nation.id = id; state.nations.append(nation)
		var city := City.new(); city.id = id; city.owner_nation = id; state.cities.append(city)
		state.recognized_city_owners.append(id)
		var army := Army.new(); army.id = id; army.owner_nation = id; army.location_city = id
		army.path = [id] as Array[int]; army.ai_target_city = id; army.ai_order_until_day = 30
		state.armies.append(army)
	state.war_chronicle_contexts[7] = {"war_id":7,"pending":false}
	state._campaign_pair_revision.append(1)
	return state
func compare(state: GameState, label: String):
	var codec := Fixture.new()
	var expected := codec.unpack(codec.pack(state))
	for nation in expected.nations: expected.release_nation_war_pool(nation.id,7)
	ChronicleRules.mark_pending(expected,7)
	state.release_war_pool(7)
	check(var_to_bytes(NativeSnapshotBuilder.build(state)) == var_to_bytes(NativeSnapshotBuilder.build(expected)), label + ": complete state matches per-nation cleanup")
	check(state._campaign_pair_revision == expected._campaign_pair_revision, label + ": derived pair revision has the same invalidation")
	check(state.chronicle_pending_war_ids == [7] and state.war_chronicle_contexts[7].pending, label + ": chronicle is marked once")
	state.release_war_pool(7)
	check(state.chronicle_pending_war_ids == [7], label + ": repeated cleanup does not duplicate finalization")
func run():
	var state := fixture()
	state.release_war_pool(-1)
	check(state._campaign_pair_revision == [1] and state.chronicle_pending_war_ids.is_empty(), "negative war id leaves cache and chronicle unchanged")
	var empty := GameState.new(); empty._campaign_pair_revision.append(1)
	empty.release_war_pool(7)
	check(empty._campaign_pair_revision == [1], "empty nation list retains the original cache boundary")
	check(state.has_method("_war_pool_has_bindings"), "war release can detect an unbound pool before national scans")
	if not state.has_method("_war_pool_has_bindings"): finish(); return
	check(not state.call("_war_pool_has_bindings",7), "ordinary unbound armies do not bind a war")
	compare(state, "empty pool")
	for status in [Army.State.IDLE,Army.State.FIGHTING,Army.State.RETREATING]:
		var bound := fixture()
		bound.armies[0].campaign_war_id = 7; bound.armies[0].state = status
		check(bound.call("_war_pool_has_bindings",7), "army binding is found for state " + str(status))
		compare(bound, "bound army " + str(status))
	var front_state := fixture()
	var front := CoalitionCampaignFront.new(); front.front_id = 0; front.war_id = 7
	front_state.campaign_fronts[0] = front
	check(front_state.call("_war_pool_has_bindings",7), "empty participant front still requires its lifecycle cleanup")
	compare(front_state, "empty front")
	var contexts := fixture()
	var record := StateCampaign.new(); record.war_id = 7; record.lifecycle = StateCampaign.Lifecycle.ENDING
	contexts.state_campaigns[0] = record
	check(contexts.call("_war_pool_has_bindings",7), "ending state record keeps the conservative cleanup path")
	var pair := CoalitionCampaignPair.new(); pair.war_id = 8; contexts.campaign_pairs[0] = pair
	check(contexts.call("_war_pool_has_bindings",8), "pair without armies is still a binding")
	check(not contexts.call("_war_pool_has_bindings",9), "unrelated records do not bind an empty pool")
	var callback := CallbackState.new()
	callback.nations = fixture().nations
	callback.release_war_pool(7)
	check(callback.calls == callback.nations.size(), "custom state retains every virtual cleanup callback")
	finish()
func finish():
	for failure in failures: printerr("WAR_POOL_RELEASE_BATCH_FAIL ",failure)
	print("WAR_POOL_RELEASE_BATCH_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
