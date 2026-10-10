extends SceneTree
class ScanState extends "res://tests/support/grid_world.gd":
	var land_scans := 0
	func land_cities() -> Array[City]:
		land_scans += 1
		return super.land_cities()
class ProxyState extends ScanState:
	func financial_nation_of(nation_id: int) -> int:
		return 1 if nation_id == 3 else super.financial_nation_of(nation_id)
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func equal_scalar(state: GameState, label: String):
	var bases := CityOutputRules.capital_tax_bases(state)
	for city in state.cities:
		check(Simulation.city_gold_output(state,city,{},int(bases.get(city.owner_nation,0))) == Simulation.city_gold_output(state,city), label+": city%d" % city.id)
func run():
	var script: RefCounted = preload("res://scripts/core/city_output_rules.gd").new()
	check(script.has_method("capital_tax_bases"), "monthly taxes have a one-pass national base aggregation")
	if not script.has_method("capital_tax_bases"):
		finish(); return
	var state := ScanState.new(); state.generate_world(24680, 4, 24)
	state.land_scans = 0
	var bases: Dictionary = script.call("capital_tax_bases",state)
	check(state.land_scans == 1, "all countries share one land-city enumeration")
	for city in state.cities:
		check(CityOutputRules.city_gold_output(state,city,{},int(bases.get(city.owner_nation,0))) == Simulation.city_gold_output(state,city), "batched and scalar gold agree city=%d" % city.id)
	var capital := state.cities[state.nations[0].capital_city_id]
	capital.gold_per_month = 1 << 33
	bases = script.call("capital_tax_bases",state)
	check(int(bases.get(0,0)) >= 1 << 33, "national bases retain int64 precision")
	check(CityOutputRules.city_gold_output(state,capital,{},int(bases.get(0,0))) == Simulation.city_gold_output(state,capital), "large capital income retains scalar precision")
	state.day = 30; capital.war_disruption_until_day = 60
	bases = script.call("capital_tax_bases",state)
	check(CityOutputRules.city_gold_output(state,capital,{},int(bases.get(0,0))) == Simulation.city_gold_output(state,capital), "war reduction is applied at the same point")
	check(script.call("capital_tax_bases",null).is_empty(), "null world has no tax bases")
	var proxy := ProxyState.new(); proxy.generate_world(24680,4,24)
	equal_scalar(proxy,"financial proxy and raw capital owner remain distinct")
	for mutation in ["vassal", "dock", "traffic", "negative", "invalid_capital", "inactive"]:
		var changed := ScanState.new(); changed.generate_world(24680,4,24)
		var c := changed.cities[changed.nations[0].capital_city_id]
		match mutation:
			"vassal": changed.suzerainty[0] = {"overlord_id":1,"tribute_rate":.25,"civil_war":false}
			"dock": c.is_dock = true
			"traffic": c.node_kind = City.NodeKind.TRAFFIC
			"negative": c.gold_per_month = -100
			"invalid_capital": changed.nations[0].capital_city_id = -1
			"inactive": c.politically_active = false
		equal_scalar(changed,mutation)
	var expected_state := ScanState.new(); expected_state.generate_world(24680,4,24)
	var actual_state := ScanState.new(); actual_state.generate_world(24680,4,24)
	var reference := Simulation.new(); var candidate := Simulation.new()
	reference.setup(expected_state); candidate.setup(actual_state)
	expected_state.day = 30; actual_state.day = 30
	reference.monthly_capital_tax_batch_disabled = true
	expected_state.land_scans = 0; actual_state.land_scans = 0
	reference._resolve_economy(); candidate._resolve_economy()
	check(var_to_bytes(NativeSnapshotBuilder.build(expected_state)) == var_to_bytes(NativeSnapshotBuilder.build(actual_state)), "real monthly commit preserves the entire state")
	check(actual_state.land_scans < expected_state.land_scans, "real monthly commit removes repeated capital scans")
	print("CAPITAL_TAX_LAND_SCANS reference=",expected_state.land_scans," candidate=",actual_state.land_scans)
	reference.free(); candidate.free()
	finish()
func finish():
	for failure in failures: printerr("CAPITAL_TAX_BATCH_FAIL ",failure)
	print("CAPITAL_TAX_BATCH_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
