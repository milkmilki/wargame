extends SceneTree
## Ruler succession is a deterministic calendar event. Extreme archetypes
## must expose their advertised numerical and territorial behavior.

var _valid := true


func _init() -> void:
	_test_reign_range_and_succession()
	_test_capital_income_and_succession_relocation()
	_test_suzerainty_rulers_share_surname()
	_test_extreme_modifiers()
	_test_conqueror_war_benefits()
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
	var dynasty_surname := WorldNaming.ruler_surname(previous_name)
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
		WorldNaming.ruler_surname(nation.ruler_name) == dynasty_surname,
		"independent succession changed the dynasty surname"
	)
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


func _test_capital_income_and_succession_relocation() -> void:
	var state := GameState.new()
	state.generate_grid_world(71239)
	state._random_ruler_profiles_enabled = true
	var nation := state.nations[0]
	var old_capital := state.cities[nation.capital_city_id]
	var base_gold := old_capital.gold_per_month
	var expected_capital_addition := 0
	for city in state.land_cities_of(nation.id):
		expected_capital_addition += city.gold_per_month
	expected_capital_addition = int(floor(
		float(expected_capital_addition) * 0.20
	))
	old_capital.set("capital_since_day", 0)
	state.day = 10 * RulerProfile.DAYS_PER_YEAR
	_check(
		Simulation.city_gold_output_before_governance(state, old_capital)
			== base_gold + expected_capital_addition,
		"capital did not receive twenty percent of national base city gold"
	)
	state.day = 60 * RulerProfile.DAYS_PER_YEAR
	_check(
		Simulation.city_gold_output_before_governance(state, old_capital)
			== base_gold + expected_capital_addition,
		"capital gold addition still changed with capital tenure"
	)

	var component := state._largest_owned_component(
		nation.id, state.land_cities_of(nation.id)
	)
	var successor_capital: City = null
	for city in component:
		city.fort_strength = 0
		if city.id != old_capital.id and successor_capital == null:
			successor_capital = city
	_check(successor_capital != null, "capital relocation fixture has no alternative city")
	if successor_capital == null:
		return
	# 继位只重新评估首都价值；旧都仍然最优时继续作为首都，并保留任期起点。
	old_capital.fort_strength = 999
	successor_capital.fort_strength = 100
	var due_day := RulerProfile.succession_due_day(nation, state.world_seed)
	state.day = due_day
	var simulation := Simulation.new()
	simulation.setup(state)
	simulation._resolve_ruler_successions()
	_check(
		nation.capital_city_id == old_capital.id,
		"ruler succession forced a capital move despite the old capital winning"
	)
	_check(
		int(old_capital.get("capital_since_day")) == 0,
		"retained capital lost its tenure start day"
	)

	# 下一任继位时出现价值更高的候选，才按同一套既有规则迁都。
	old_capital.fort_strength = 0
	successor_capital.fort_strength = 1000
	var next_due_day := RulerProfile.succession_due_day(
		nation, state.world_seed
	)
	state.day = next_due_day
	simulation._resolve_ruler_successions()
	_check(
		nation.capital_city_id == successor_capital.id,
		"ruler succession did not move to the newly highest-value capital"
	)
	_check(
		int(old_capital.get("capital_since_day")) == -1,
		"demoted capital retained its tenure start day"
	)
	_check(
		int(successor_capital.get("capital_since_day")) == next_due_day,
		"new capital did not start its tenure on the succession day"
	)
	state.day += 5 * RulerProfile.DAYS_PER_YEAR
	_check(
		Simulation.city_gold_output_before_governance(
			state, successor_capital
		) == successor_capital.gold_per_month + expected_capital_addition,
		"new capital did not receive the national base city gold addition"
	)
	simulation.free()


func _test_suzerainty_rulers_share_surname() -> void:
	var state := GameState.new()
	state.generate_grid_world(71241)
	state._random_ruler_profiles_enabled = true
	var region: Array[int] = []
	for city in state.land_cities_of(0):
		if not city.is_capital:
			region.append(city.id)
		if region.size() >= 3:
			break
	var subject_id := state.enfeoff(0, region)
	_check(subject_id >= 0, "surname fixture failed to create a vassal")
	if subject_id < 0:
		return
	var root := state.nations[0]
	var subject := state.nations[subject_id]
	var dynasty_surname := root.ruler_name.substr(0, 1)
	_check(
		subject.ruler_name.substr(0, 1) == dynasty_surname,
		"new vassal ruler did not inherit the overlord surname"
	)

	var simulation := Simulation.new()
	simulation.setup(state)
	var subject_name_before := subject.ruler_name
	var subject_due := RulerProfile.succession_due_day(
		subject, state.world_seed
	)
	root.ruler_started_day = subject_due
	state.day = subject_due
	simulation._resolve_ruler_successions()
	_check(
		subject.ruler_name != subject_name_before
			and subject.ruler_name.substr(0, 1) == dynasty_surname,
		"vassal succession did not preserve the suzerainty surname"
	)

	root.ruler_started_day = state.day
	var root_due := RulerProfile.succession_due_day(root, state.world_seed)
	subject.ruler_started_day = root_due
	var root_name_before := root.ruler_name
	state.day = root_due
	simulation._resolve_ruler_successions()
	_check(
		root.ruler_name != root_name_before
			and root.ruler_name.substr(0, 1) == dynasty_surname
			and subject.ruler_name.substr(0, 1) == dynasty_surname,
		"overlord succession broke the shared suzerainty surname"
	)
	simulation.free()


func _test_extreme_modifiers() -> void:
	var conqueror := RulerProfile.modifiers(RulerProfile.CONQUEROR)
	var guardian := RulerProfile.modifiers(RulerProfile.GUARDIAN)
	_check(
		is_equal_approx(float(conqueror[RulerProfile.KEY_MORALE]), 2.0)
		and is_equal_approx(float(conqueror[RulerProfile.KEY_DEFENSE]), 2.0)
		and is_equal_approx(float(conqueror[RulerProfile.KEY_UPKEEP]), 0.5)
		and is_equal_approx(float(conqueror[RulerProfile.KEY_WAR_BENEFIT]), 2.0)
		and is_equal_approx(
			float(conqueror[RulerProfile.KEY_OFFENSIVE_INTERVAL]), 0.5
		),
		"conqueror military multipliers do not match the extreme profile"
	)
	_check(
		is_equal_approx(float(guardian[RulerProfile.KEY_TRADE]), 2.0),
		"guardian trade multiplier is not 2.0"
	)


func _test_conqueror_war_benefits() -> void:
	_check(
		is_equal_approx(
			DiplomacyAI._war_desire_score(3.0, 0.5, 0.75, 0.25, 2.0),
			5.5
		),
		"conqueror did not double only positive war benefits"
	)
	var state := GameState.new()
	state.generate_world(15873, 2, 20)
	var simulation := Simulation.new()
	simulation.setup(state)
	var conqueror := state.nations[0]
	conqueror.ruler_archetype = RulerProfile.CONQUEROR
	conqueror.ruler_traits.clear()
	_check(
		simulation._campaign_offensive_interval(0)
			== int(round(
				float(Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS)
					* 0.5 / 1.85
			)),
		"conqueror offensive interval was not halved"
	)
	simulation.free()


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
	state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	var wartime_actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(
		state, wartime_actions, {}, {}
	)
	var wartime_enfeoff := false
	for action in wartime_actions:
		wartime_enfeoff = wartime_enfeoff or (
			int(action.get("kind", -1)) == DiplomacyAI.Action.ENFEOFF
			and int(action.get("a", -1)) == 0
		)
	_check(
		DiplomacyAI._overlord_under_war_pressure(state, 0, {})
			and not wartime_enfeoff,
		"puppet ruler must not enfeoff during war pressure"
	)
	state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.NEUTRAL
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
	_check(
		grants >= 2,
		"puppet ruler could not enfeoff repeatedly without advancing world time"
	)
	_check(
		state.land_cities_of(0).size() == DiplomacyAI.PUPPET_DIRECT_CORE_CITIES,
		"puppet ruler did not reduce direct rule to the capital core without a cooldown: initial=%d current=%d grants=%d"
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
