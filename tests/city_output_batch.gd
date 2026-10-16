extends SceneTree
class CountingState extends "res://tests/support/grid_world.gd":
	var administrative_queries := 0
	var financial_queries := 0
	var remapped_owner := 3
	func city_administrative_output_enabled(id: int) -> bool:
		administrative_queries += 1
		return super.city_administrative_output_enabled(id)
	func financial_nation_of(id: int) -> int:
		financial_queries += 1
		return 1 if id == remapped_owner else super.financial_nation_of(id)
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func verify(state: GameState, label: String):
	var rng_before := state.rng.state
	for potential in [false, true]:
		var expected := PackedInt32Array()
		expected.resize(state.cities.size())
		var bases := CityOutputRules._national_base_gold(state, not potential)
		for city in state.cities:
			var base := bases[city.owner_nation] if city.owner_nation >= 0 and city.owner_nation < bases.size() else 0
			expected[city.id] = CityOutputRules.city_potential_gold_output(state, city, {}, base) if potential else CityOutputRules.city_gold_output(state, city, {}, base)
		var actual := CityOutputRules.city_potential_gold_outputs(state) if potential else CityOutputRules.city_gold_outputs(state)
		check(actual == expected, label + ": scalar and batch agree, potential=" + str(potential))
	check(state.rng.state == rng_before, label + ": random stream unchanged")
func run():
	check(CityOutputRules.city_gold_outputs(null).is_empty(), "null actual output")
	check(CityOutputRules.city_potential_gold_outputs(GameState.new()).is_empty(), "empty potential output")
	for mutation in ["initial", "vassal", "disruption", "expired", "inactive", "dock", "traffic", "negative", "unowned", "capital"]:
		var state := CountingState.new()
		state.generate_world(24680, 4, 24)
		var city := state.cities[state.nations[0].capital_city_id]
		match mutation:
			"vassal": state.suzerainty[0] = {"overlord_id":1,"tribute_rate":.25,"civil_war":false}
			"disruption": city.war_disruption_until_day = 60; state.day = 30
			"expired": city.war_disruption_until_day = 60; state.day = 60
			"inactive": city.politically_active = false
			"dock": city.is_dock = true
			"traffic": city.node_kind = City.NodeKind.TRAFFIC
			"negative": city.gold_per_month = -100
			"unowned": city.owner_nation = -1
			"capital": state.nations[0].capital_city_id = -1
		verify(state, mutation)
		# The batch is fresh even when dependencies change without a revision bump.
		city.owner_nation = 2; city.gold_per_month = 127; city.war_disruption_until_day = state.day + 1
		verify(state, mutation + ": direct edits")
	var measured := CountingState.new(); measured.generate_world(7, 4, 24)
	measured.administrative_queries = 0
	CityOutputRules.city_gold_outputs(measured)
	check(measured.administrative_queries <= measured.cities.size() * 2, "actual batch checks administration at most twice per city")
	measured.financial_queries = 0
	CityOutputRules.city_potential_gold_outputs(measured)
	check(measured.financial_queries <= measured.cities.size() + measured.nations.size(), "potential batch resolves governance once per owner")
	measured.suzerainty[0] = {"overlord_id":1,"tribute_rate":.25,"civil_war":false}
	verify(measured, "same-instance vassal admission")
	measured.suzerainty.erase(0)
	verify(measured, "same-instance independence")
	measured.remapped_owner = 2
	verify(measured, "same-instance financial identity change")
	for failure in failures: printerr("CITY_OUTPUT_BATCH_FAIL ", failure)
	print("CITY_OUTPUT_BATCH_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
