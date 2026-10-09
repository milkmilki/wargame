extends SceneTree

const SuccessionAudit = preload("res://tests/succession_audit.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.world_seed = 12345
	state.rng.seed = 12345
	state.day = 360
	var parent := Nation.new()
	parent.id = 0
	parent.ruler_name = "李安"
	parent.capital_city_id = 0
	parent.warehouse_city_ids = [0] as Array[int]
	parent.manpower_pool = 0
	parent.treasury_gold = 100
	state.nations.append(parent)
	for id in range(3):
		var city := City.new()
		city.id = id
		city.owner_nation = 0
		city.map_position = Vector2(0.2 + 0.3 * id, 0.5)
		city.is_capital = id == 0
		city.has_warehouse = id == 0
		city.food_storage = 100 if id == 0 else 0
		city.food_per_half_year = 100
		city.manpower_per_month = 10
		city.gold_per_month = 10
		city.garrison_manpower = 0
		city.loyalty_target_nation = 0
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.recognized_city_owners.append(0)
	state.administrative_center_by_city = PackedInt32Array([0, 1, 1])
	state.administrative_center_city_ids = PackedInt32Array([0, 1])
	state.administrative_region_ids = PackedInt32Array([0, 1, 1])
	state.administrative_region_count = 2
	state.administrative_region_revision = 1
	for id in range(2):
		state._add_edge(id, id + 1)
		state.edge_of(id, id + 1).distance = 0.1
	FamilyTree.ensure_all(state)
	state.refresh_derived()
	return state

func run() -> void:
	var state := fixture()
	check(state.armies.is_empty(), "fixture has no stationed armies")
	check(state.nations[0].manpower_pool == 0, "fixture cannot mobilize regular army")
	check(SuccessionAudit.inspect(state).errors.is_empty(), "parent starts with valid lifecycle")
	var rebel_id := state.start_regional_rebellion(0, [1, 2] as Array[int])
	check(rebel_id == 1, "real regional rebellion succeeds")
	if rebel_id >= 0:
		var rebel := state.nations[rebel_id]
		var ruler := PrincePolitics.person(state, rebel_id, rebel.ruler_person_id)
		print("REBELLION_RULER_DIAGNOSTIC: ", JSON.stringify({
			"nation": rebel_id, "manpower": rebel.manpower_pool,
			"ruler": ruler, "audit": SuccessionAudit.inspect(state).errors,
		}))
		check(not ruler.is_empty(), "new rebel has a ruler")
		check(bool(ruler.get("alive", true)), "new rebel ruler is alive")
		check(bool(ruler.get("children_initialized", false)), "new rebel ruler generation initialized without regular army")
		check(SuccessionAudit.inspect(state).errors.is_empty(), "new rebel immediately satisfies succession audit")
		check(state.cities[0].owner_nation == 0 and state.cities[1].owner_nation == rebel_id and state.cities[2].owner_nation == rebel_id, "full region transferred and parent capital preserved")
	for failure in failures:
		push_error("REBELLION_RULER_LIFECYCLE_FAIL: " + failure)
	print("REBELLION_RULER_LIFECYCLE: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
