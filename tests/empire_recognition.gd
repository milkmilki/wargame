extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(73001)
	var service = load("res://scripts/core/empire_status.gd")
	if service == null:
		push_error("EMPIRE_RECOGNITION_FAIL: empire recognition service absent")
		quit(1)
		return
	# Two actual regions split between two independent countries.
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	var foreign := state.land_cities_of(1)
	state.region_ids[land[0].id] = 10
	state.region_ids[land[1].id] = 20
	state.region_ids[foreign[0].id] = 20
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	service.reconcile(state)
	check(state.nations[0].get("state_level") == 0, "one complete region plus one partial cannot promote")
	check(state.nations[0].empire_founder_person_id == -1, "ordinary allies do not complete imperial integration")
	state.cities[foreign[0].id].owner_nation = 0
	service.reconcile(state)
	check(state.nations[0].get("state_level") == 0, "unconfirmed occupation cannot promote")
	state.cities[foreign[0].id].owner_nation = 1
	state.suzerainty[1] = {"overlord_id": 0, "civil_war": true}
	service.reconcile(state)
	check(state.nations[0].get("state_level") == 0, "rebellious subjects cannot promote root")
	state.suzerainty[1].civil_war = false
	service.reconcile(state)
	check(state.nations[0].get("state_level") == 1, "two lawful peaceful regions promote root")
	check(state.nations[1].get("state_level") == 0, "subject does not promote with root")
	var founder: int = state.nations[0].get("empire_founder_person_id")
	check(founder == state.nations[0].ruler_person_id, "current ruler is Taizu")
	var revision := state.family_revision
	service.reconcile(state)
	check(state.family_revision == revision, "repeated recognition is idempotent")
	state.suzerainty.clear()
	state.region_ids.fill(-1)
	service.reconcile(state)
	check(state.nations[0].get("state_level") == 1 and state.nations[0].get("empire_founder_person_id") == founder, "empire and founder survive losses")
	state = preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(73001)
	state.region_ids.fill(-1)
	land = state.land_cities_of(0)
	state.region_ids[land[0].id] = 10
	state.region_ids[land[1].id] = 20
	land[1].politically_active = false
	for city in state.cities:
		if city.is_dock: state.region_ids[city.id] = 30
	service.reconcile(state)
	check(state.nations[0].state_level == 0, "docks, inactive land and invalid regions never add an imperial region")
	for failure in failures:
		push_error("EMPIRE_RECOGNITION_FAIL: " + failure)
	print("EMPIRE_RECOGNITION_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
