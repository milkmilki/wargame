extends SceneTree
## War groups depend on political topology, not daily force positions.
var checks := 0
var failures: Array[String] = []

class CountingState extends "res://tests/support/grid_world.gd":
	var component_builds := 0
	func coalition_campaign_components(war_id: int = -1) -> Array[Dictionary]:
		component_builds += 1
		return super.coalition_campaign_components(war_id)

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)

func compare(sim: Simulation, label: String) -> int:
	var state := sim.state as CountingState
	var expected := state.coalition_campaign_components()
	var builds := state.component_builds
	var actual: Array = sim.call("_cached_coalition_campaign_components")
	check(var_to_bytes(actual) == var_to_bytes(expected), label + ": exact direct components")
	return state.component_builds - builds

func run():
	var state := CountingState.new()
	state.generate_world(1, 4, 36)
	state.atlas_layout = {"model": "component-cache-test", "territorial_pairs": [] as Array[Vector2i]}
	var sim := Simulation.new(); sim.state = state
	if not sim.has_method("_cached_coalition_campaign_components"):
		check(false, "reuse coalition topology across army movement and scheduled decisions")
		finish(sim); return
	check(compare(sim, "peaceful world") == 1, "empty topology built once")
	check(compare(sim, "peaceful world again") == 0, "empty result is a valid cache hit")
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	state.merge_war_ids(state.war_id_between(0, 2), state.war_id_between(1, 2))
	check(compare(sim, "initial") == 1, "initial topology built once")
	var rng_state := state.rng.state
	for day in range(1, 6):
		state.day = day
		state.armies[0].location_city = day
		state.armies[0].size -= 1
		state.cities[0].food_storage += 1
		state.garrison_revision += 1
		check(compare(sim, "movement day%d" % day) == 0, "movement, stock and garrison do not rebuild coalition groups")
	check(state.rng.state == rng_state, "cache lookup never consumes random stream")
	var mutable: Array = sim.call("_cached_coalition_campaign_components")
	mutable[0]["defense_centers"] = [999]
	(mutable[0]["members"] as Array).clear()
	mutable.clear()
	check(compare(sim, "caller mutation") == 0, "caller mutation cannot poison cached components")
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	check(compare(sim, "alliance split") == 1, "alliance change immediately rebuilds")
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.NEUTRAL)
	check(compare(sim, "peace") == 1, "peace immediately removes component")
	var transfer := state.transfer_city_control(0, 3, 3, GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL, "coalition_cache_test")
	check(bool(transfer.get("ok", false)), "real control transfer succeeds")
	check(compare(sim, "conquest") == 1, "control transfer invalidates connectivity")
	state.road_network_revision += 1
	check(compare(sim, "road") == 1, "road topology invalidates groups")
	state.administrative_region_revision += 1
	check(compare(sim, "administrative") == 1, "administrative topology invalidates groups")
	state.nations[2].alive = false
	check(compare(sim, "alive") == 1, "direct alive change also invalidates")
	state.nations[2].alive = true
	state.nations[2].succession_identity = true
	check(compare(sim, "identity") == 1, "succession identity changes relation interpretation")
	state.nations[2].succession_identity = false
	var conflict := SuccessionConflict.new()
	conflict.nation_id = 0; conflict.rebel_nation_id = 2; conflict.war_id = state.war_id_between(0, 2)
	state.succession_conflicts[0] = conflict
	check(compare(sim, "internal succession war") == 1, "succession wars excluded without requiring diplomatic revision")
	state.succession_conflicts.clear()
	check(compare(sim, "succession resolved") == 1, "succession removal restores external component")
	var war := state.war_id_between(0, 2)
	state.vassal_conflicts[war] = {"active": true, "central": [0], "rebels": [2]}
	check(compare(sim, "faction") == 1, "faction membership invalidates")
	state.vassal_conflicts[war]["rebels"] = [2, 3]
	check(compare(sim, "faction membership") == 1, "in-place faction membership change invalidates")
	state.vassal_conflicts[war]["active"] = false
	check(compare(sim, "faction inactive") == 1, "faction active state invalidates")
	state.diplomatic_relations[state._diplomacy_key(0, 2)] = GameState.DiplomaticRelation.NEUTRAL
	check(compare(sim, "direct relation change") == 1, "in-place relation change invalidates without revision")
	state.war_relation_ids[state._diplomacy_key(0, 2)] = war + 100
	check(compare(sim, "war id migration") == 1, "war id change invalidates even without revision")
	sim.ai_coalition_component_cache_disabled = true
	check(compare(sim, "disabled") == 1, "oracle switch restores uncached query")
	sim.ai_coalition_component_cache_disabled = false
	state.atlas_layout.clear()
	check(compare(sim, "legacy") == 1 and compare(sim, "legacy again") == 1, "legacy world retains direct query")
	var other := CountingState.new(); other.generate_world(1, 4, 36)
	other.atlas_layout = {"model": "component-cache-test", "territorial_pairs": [] as Array[Vector2i]}
	sim.state = other
	check(compare(sim, "new world") == 1, "different world cannot reuse old groups")
	finish(sim)

func finish(sim: Simulation):
	sim.free()
	for failure in failures: printerr("ATLAS_COALITION_COMPONENTS_FAIL ", failure)
	print("ATLAS_COALITION_COMPONENTS_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
