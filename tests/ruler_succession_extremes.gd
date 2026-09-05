extends SceneTree
## Ruler succession is a deterministic calendar event. Extreme archetypes
## must expose their advertised numerical and territorial behavior.

var _valid := true


func _init() -> void:
	_test_reign_range_and_succession()
	_test_extreme_modifiers()
	_test_puppet_enfeoffment()
	if not _valid:
		quit(1)
		return
	print("RULER_SUCCESSION_EXTREMES_OK")
	quit(0)


func _test_reign_range_and_succession() -> void:
	for nation_id in range(64):
		for revision in range(8):
			var years := RulerProfile.reign_years(71237, nation_id, revision)
			_check(
				years >= RulerProfile.MIN_REIGN_YEARS
				and years <= RulerProfile.MAX_REIGN_YEARS,
				"reign duration escaped 10..30 years"
			)

	var state := GameState.new()
	state.generate_world(71237, 4, 40)
	var simulation := Simulation.new()
	simulation.setup(state)
	var nation := state.nations[0]
	var previous_name := nation.ruler_name
	var previous_archetype := nation.ruler_archetype
	var previous_traits := nation.ruler_traits.duplicate()
	var previous_revision := nation.ruler_revision
	var due_day := RulerProfile.succession_due_day(nation, state.world_seed)
	state.day = due_day - 1
	simulation._resolve_ruler_successions()
	_check(nation.ruler_revision == previous_revision, "ruler changed one day early")
	state.day = due_day
	simulation._resolve_ruler_successions()
	_check(nation.ruler_revision == previous_revision + 1, "ruler did not change on due day")
	_check(nation.ruler_started_day == due_day, "successor start day was not recorded")
	_check(nation.ruler_name != previous_name, "successor reused the previous ruler name")
	_check(
		nation.ruler_archetype != previous_archetype
		or nation.ruler_traits != previous_traits,
		"successor reused the complete previous profile"
	)
	var next_due := RulerProfile.succession_due_day(nation, state.world_seed)
	_check(
		next_due >= due_day + RulerProfile.MIN_REIGN_YEARS * RulerProfile.DAYS_PER_YEAR
		and next_due <= due_day + RulerProfile.MAX_REIGN_YEARS * RulerProfile.DAYS_PER_YEAR,
		"successor due day escaped configured range"
	)
	var summary := MapRenderer.ruler_summary(nation, state)
	_check(
		summary.contains("任期") and summary.contains("余"),
		"ruler summary does not expose reign duration"
	)
	simulation.free()


func _test_extreme_modifiers() -> void:
	var conqueror := RulerProfile.modifiers(RulerProfile.CONQUEROR)
	var guardian := RulerProfile.modifiers(RulerProfile.GUARDIAN)
	_check(
		is_equal_approx(float(conqueror[RulerProfile.KEY_MORALE]), 2.0)
		and is_equal_approx(float(conqueror[RulerProfile.KEY_DEFENSE]), 2.0),
		"conqueror military multipliers are not 2.0"
	)
	_check(
		is_equal_approx(float(guardian[RulerProfile.KEY_TRADE]), 2.0),
		"guardian trade multiplier is not 2.0"
	)


func _test_puppet_enfeoffment() -> void:
	var state := GameState.new()
	state.generate_world(84521, 2, 60)
	var ruler := state.nations[0]
	ruler.ruler_archetype = RulerProfile.PUPPET
	ruler.ruler_traits.clear()
	var initial_cities := state.land_cities_of(0).size()
	_check(
		initial_cities > DiplomacyAI.PUPPET_DIRECT_CORE_CITIES,
		"puppet fixture does not have enough direct cities"
	)
	var grants := 0
	while (
		state.land_cities_of(0).size()
			> DiplomacyAI.PUPPET_DIRECT_CORE_CITIES
		and grants < 32
	):
		var actions: Array[Dictionary] = []
		DiplomacyAI._collect_enfeoff_actions(state, actions, {}, {})
		var selected: Dictionary = {}
		for action in actions:
			if (
				int(action.get("kind", -1)) == DiplomacyAI.Action.ENFEOFF
				and int(action.get("a", -1)) == 0
			):
				selected = action
				break
		if selected.is_empty():
			break
		var region: Array[int] = []
		for city_value in selected.get("region_cities", []):
			region.append(int(city_value))
		var subject_id := state.enfeoff(0, region)
		_check(subject_id >= 0, "puppet enfeoff transaction failed")
		if subject_id < 0:
			break
		grants += 1
		state.day += DiplomacyAI.PUPPET_ENFEOFF_COOLDOWN_DAYS
	_check(grants >= 1, "puppet ruler created no vassals")
	_check(
		state.land_cities_of(0).size() == DiplomacyAI.PUPPET_DIRECT_CORE_CITIES,
		"puppet ruler did not reduce direct rule to the capital core: initial=%d current=%d grants=%d"
		% [initial_cities, state.land_cities_of(0).size(), grants]
	)
	var capital_hops := RebellionSystem.capital_hops(state, 0)
	var reachable_land := 0
	for city in state.land_cities_of(0):
		if capital_hops.has(city.id):
			reachable_land += 1
	_check(
		reachable_land == state.land_cities_of(0).size(),
		"puppet ruler left a disconnected direct core: reachable=%d direct=%d"
		% [reachable_land, state.land_cities_of(0).size()]
	)
	var centralize_actions: Array[Dictionary] = []
	DiplomacyAI._collect_centralization_actions(
		state, centralize_actions, {}, {}
	)
	_check(centralize_actions.is_empty(), "puppet ruler attempted to revoke a vassal")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_valid = false
	push_error("RULER_SUCCESSION_EXTREMES_FAILED: " + message)
