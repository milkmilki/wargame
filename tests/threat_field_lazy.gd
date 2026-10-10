extends SceneTree
const Eager = preload("res://tests/support/eager_threat_reference.gd")
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func make_view(state: GameState, observer: int) -> AiWorldView:
	var view := AiWorldView.new()
	view.state = state; view.nation_id = observer; view.day = state.day
	for army in state.armies:
		if army.owner_nation == observer: view.friendly_armies.append(army)
		else: view.enemy_armies.append(army)
	return view
func verify(view: AiWorldView, readonly_base: bool):
	var cache := {}
	var expected = Eager.build(view)
	for army in view.state.armies:
		ThreatField.build_shared_travel_request(view.state, army.location_city, 0, cache)
	var cache_before := var_to_bytes(cache)
	if readonly_base: cache.make_read_only()
	var actual := ThreatField.build(view, cache, {}, readonly_base)
	if readonly_base: check(var_to_bytes(cache) == cache_before, "readonly base cache is unchanged")
	check(actual.get("_threat_values") is Dictionary, "private lazy values exist")
	if not actual.get("_threat_values") is Dictionary: return
	check(actual.get("_threat_values").is_empty(), "build does not accumulate unqueried threat")
	check(actual.get("_support_values").is_empty(), "build does not accumulate unqueried support")
	var partial := ThreatField.build(view)
	partial.threat_at(view.state.cities.size()-1)
	check(var_to_bytes(partial.threat_by_city) == var_to_bytes(expected.threat_by_city), "full getter fills untouched cities after one query")
	# Query in reverse order: full dictionary must retain the old insertion order.
	for id in range(view.state.cities.size()-1,-1,-1):
		check(var_to_bytes(actual.threat_at(id)) == var_to_bytes(expected.threat_at(id)), "exact threat%d"%id)
		check(var_to_bytes(actual.support_at(id)) == var_to_bytes(expected.support_at(id)), "exact support%d"%id)
	check(actual.threat_at(-1) == 0.0 and actual.support_at(999999) == 0.0, "invalid queries return zero")
	check(var_to_bytes(actual.threat_by_city) == var_to_bytes(expected.threat_by_city), "full threat dictionary exact keys/order/values")
	check(var_to_bytes(actual.support_by_city) == var_to_bytes(expected.support_by_city), "full support dictionary exact keys/order/values")
	actual.threat_by_city[0] = 123.0
	check(actual.threat_at(0) == 123.0, "public dictionary remains mutable")
	actual.threat_by_city.erase(0)
	check(actual.threat_at(0) == 0.0, "erased key is not recomputed")
	actual.support_by_city = {0:789.0}
	check(actual.support_at(0) == 789.0 and actual.support_at(1) == 0.0, "public setter replaces computed field")
	actual.support_by_city.clear()
	check(actual.support_at(0) == 0.0, "cleared dictionary stays empty")
func run():
	for seed_value in [1,7,2024]:
		var state := preload("res://tests/support/grid_world.gd").new()
		state.generate_world(seed_value,4,64)
		# Moving endpoints, blocked edges, traffic nodes, unequal powers and no sources.
		for i in range(state.armies.size()):
			var army := state.armies[i]
			army.size = 1000+i*137; army.morale = .35+.1*(i%6); army.supply_ratio = .2+.2*(i%4)
			if i%2 == 0 and not state.neighbors(army.location_city).is_empty():
				army.on_edge = true; army.move_from = army.location_city
				army.move_to = state.neighbors(army.location_city)[0]; army.move_progress = .31
		state.edges[0].max_manpower = 0
		for observer in range(4):
			for readonly_base in [false,true]: verify(make_view(state,observer),readonly_base)
		state.atlas_layout = {"model":"lazy-threat-fixture"}
		state.cities[1].node_kind = City.NodeKind.TRAFFIC
		verify(make_view(state,0),true)
		var view := make_view(state,0)
		var expected = Eager.build(view)
		var shared := {}
		var frozen := ThreatField.build(view,shared)
		# Freeze before first query: later army, topology and caller-owned cache edits
		# must not alter this day's field.
		for army in state.armies: army.size = 0; army.move_progress = .99
		for edge in state.edges: edge.max_manpower = 0; edge.distance *= 10
		for entry in shared.values():
			if entry is Dictionary: entry.clear()
		shared.clear()
		for id in range(state.cities.size()):
			check(var_to_bytes(frozen.threat_at(id)) == var_to_bytes(expected.threat_at(id)), "frozen threat after mutations")
			check(var_to_bytes(frozen.support_at(id)) == var_to_bytes(expected.support_at(id)), "frozen support after mutations")
		state.armies.clear()
		verify(make_view(state,0),false)
		verify(make_view(state,0),true)
	var manual := ThreatField.new()
	manual.threat_by_city[1] = 5.0
	check(manual.threat_at(1) == 5.0 and manual.support_at(1) == 0.0, "manually constructed field remains compatible")
	print("THREAT_FIELD_LAZY checks=%d failures=%d"%[checks,failures.size()])
	for failure in failures: print("FAIL ",failure)
	quit(0 if failures.is_empty() else 1)
