extends SceneTree
const Factory = preload("res://tests/native_graph_equivalence.gd")
class ToggleAccessState extends GameState:
	var grants_access := false
	func has_military_access(_traveler: int, _owner: int) -> bool:
		return grants_access
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("AI_HUB_CACHE_FAIL ", label)

func verify(view: AiWorldView, army: Army, cache: Dictionary, label: String) -> void:
	var expected := army.starving and army.supply_ratio <= UtilityAI.BREAKOUT_SUPPLY_RATIO and not Pathfinding.can_reach_manpower_hub(view.state, army)
	var utility: Script = load("res://scripts/ai/utility_ai.gd")
	var actual: bool = utility.call("_is_encircled_low_supply", view, army, cache)
	check(actual == expected, label)

func run() -> void:
	var custom := ToggleAccessState.new()
	var custom_nation := Nation.new(); custom_nation.id = 0
	custom_nation.warehouse_city_ids = [0] as Array[int]
	custom.nations.append(custom_nation)
	var custom_city := City.new(); custom_city.id = 0; custom_city.owner_nation = 0; custom_city.has_warehouse = true
	custom.cities.append(custom_city); custom.adjacency[0] = [] as Array[int]
	var custom_view := AiWorldView.new(); custom_view.state = custom
	var custom_army := Army.new(); custom_army.owner_nation = 0
	custom_army.location_city = 0; custom_army.starving = true; custom_army.supply_ratio = .1
	var custom_cache := {}
	verify(custom_view, custom_army, custom_cache, "custom callback denies access")
	custom.grants_access = true
	verify(custom_view, custom_army, custom_cache, "custom callback edits remain live")
	check(custom_cache.is_empty(), "custom state does not receive a frozen network")
	for mirror in [false, true]:
		var factory := Factory.new()
		var state: GameState = factory.fixture(mirror)
		factory.free()
		state.cities[0].has_warehouse = true
		state.nations[0].warehouse_city_ids = [0] as Array[int]
		var view := AiWorldView.new()
		view.state = state; view.nation_id = 0; view.day = state.day
		var troop := Army.new()
		troop.owner_nation = 0; troop.size = 1000
		troop.starving = true; troop.supply_ratio = .1
		var cache := {}
		var before_rng := state.rng.state
		for city in state.cities:
			troop.location_city = city.id
			verify(view, troop, cache, "city %d mirror=%s" % [city.id, mirror])
		check(cache.size() == 1 and cache.has(0), "one nation network serves repeated armies")
		for edge in state.edges:
			troop.on_edge = true; troop.move_from = edge.city_a; troop.move_to = edge.city_b
			verify(view, troop, cache, "edge")
		troop.on_edge = false; troop.location_city = 3
		# Each decision phase starts with a fresh cache; direct live calls keep
		# observing topology, ownership and diplomacy edits between calls.
		state.edge_of(0, 5).max_manpower = 0
		state.edge_of(0, 4).max_manpower = 0
		verify(view, troop, {}, "next phase captures road closure")
		check(UtilityAI._is_encircled_low_supply(view, troop) == not Pathfinding.can_reach_manpower_hub(state, troop), "standalone predicate remains live")
		state.edge_of(0, 5).max_manpower = 10000
		state.cities[3].owner_nation = 2
		verify(view, troop, {}, "next phase captures neutral ownership")
		state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
		verify(view, troop, {}, "next phase captures alliance")
		var unused := {}
		troop.starving = false
		verify(view, troop, unused, "not starving")
		troop.starving = true; troop.supply_ratio = .5
		verify(view, troop, unused, "adequate supply")
		troop.supply_ratio = NAN
		verify(view, troop, unused, "NaN supply retains short circuit")
		check(unused.is_empty(), "no network is built when predicate short circuits")
		troop.supply_ratio = .1; troop.owner_nation = -1
		verify(view, troop, {}, "invalid owner")
		check(state.rng.state == before_rng, "reachability consumes no RNG")
	print("AI_HUB_CACHE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
