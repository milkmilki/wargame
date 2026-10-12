extends SceneTree
## Direct province queries must match the unchanged complete activity index.
const Direct = preload("res://tests/direct_center_camp.gd")
class CountingState extends "res://tests/support/grid_world.gd":
	var full_builds := 0
	func campaign_defense_activity_index() -> Dictionary:
		full_builds += 1
		return super.campaign_defense_activity_index()

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("DEFENSE_CENTER_FAIL ", message)

func fixture() -> CountingState:
	var original := Direct.fixture()
	var state := CountingState.new()
	for property in original.get_property_list():
		var name: String = property.name
		if name == "script" or int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		state.set(name, original.get(name))
	return state

func compare(state: CountingState, label: String) -> void:
	var full := state.campaign_defense_activity_index()
	var rng_before := state.rng.state
	for owner in range(state.nations.size()):
		for center in state.administrative_center_city_ids:
			for war in [-1, state.war_id_between(0, 1), 999]:
				var expected := state.campaign_defense_context(owner, center, war, full)
				state.full_builds = 0
				var actual := state.campaign_defense_context(owner, center, war)
				check(var_to_bytes(actual) == var_to_bytes(expected), label + ": full context and ordered IDs match")
				check(state.full_builds == 0, label + ": direct query avoids a complete-world index")
	check(state.rng.state == rng_before, label + ": RNG unchanged")

func run() -> void:
	var state := fixture()
	var present := Direct.army(state, 0, 3)
	var incoming := Direct.army(state, 0, 2)
	incoming.state = Army.State.MOVING
	incoming.ai_action = ActionCandidate.Kind.ATTACK
	incoming.ai_target_city = 3
	incoming.path = [3] as Array[int]
	var camper := Direct.army(state, 0, 2)
	var front := Direct.front(state, [camper] as Array[Army])
	front.camp_city_id = 2
	compare(state, "present, incoming and rear camp")
	camper.state = Army.State.RECOVERING
	compare(state, "ineffective camp still creates hostile activity")
	camper.state = Army.State.MOVING
	camper.location_city = 1
	camper.ai_target_city = 2
	camper.path = [2] as Array[int]
	compare(state, "returning camp route")
	var camp_capacity := state.edge_of(1, 2).max_manpower
	state.edge_of(1, 2).max_manpower = 0
	compare(state, "closed camp route")
	state.edge_of(1, 2).max_manpower = camp_capacity
	state.cities[4].owner_nation = 0
	var siege := Battle.new()
	siege.kind = Battle.Kind.SIEGE
	siege.city = state.cities[3]
	siege.siege_attacker_nation = 0
	state.battles.append(siege)
	compare(state, "occupied fu and siege")
	state.armies.append(present)
	compare(state, "duplicate army records do not double-count")
	var random := RandomNumberGenerator.new()
	random.seed = 77238
	for sample in range(40):
		state = fixture()
		for city in state.cities:
			city.owner_nation = random.randi_range(0, 2)
		for index in range(48):
			var army := Direct.army(state, random.randi_range(0, 2), random.randi_range(-1, 7), random.randi_range(0, 18000))
			army.state = random.randi_range(0, Army.State.RECOVERING)
			army.starving = random.randf() < .1
			army.supply_ratio = 0.0 if random.randf() < .1 else 1.0
			army.ai_action = ActionCandidate.Kind.ATTACK
			army.ai_target_city = random.randi_range(-1, 7)
			army.path.clear()
			if army.ai_target_city >= 0:
				army.path.append(army.ai_target_city)
			if index % 3 == 0:
				army.on_edge = true
				army.move_from = random.randi_range(0, 7)
				army.move_to = random.randi_range(0, 7)
		compare(state, "random %d" % sample)
	print("DEFENSE_CENTER_ACTIVITY checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
