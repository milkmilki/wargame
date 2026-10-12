extends SceneTree
## Byte-exact oracle checks against the existing GDScript cost functions.
var failures := 0
var checks := 0
const CONSTANTS := [Pathfinding.DANGER_WEIGHT, Pathfinding.SUPPLY_DISTANCE_LOSS, Pathfinding.SUPPLY_DANGER_MULT, Simulation.MARCH_DAYS_MIN, Simulation.MARCH_DAYS_PER_DISTANCE_STEP]

class WrongEdge:
	extends RefCounted
	var max_manpower: int = 10000
	var precise_distance: String = "invalid"
	var distance: int = 1
	var danger: float = 0.0
	var travel_time_multiplier: float = 1.0
	var supply_loss_multiplier: float = 1.0

class WrongCity:
	extends RefCounted
	var owner_nation: String = "invalid"

func _initialize() -> void:
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	if graph == null or not graph.has_method("pack_edge_inputs"):
		check(false, "native pack_edge_inputs is registered")
		_finish()
		return
	var edges: Array = []
	var precise := [-1.0, 0.0, 0.000000004, 0.25, 1.125, PI, 1000000.125]
	var distances := [-4, 0, 1, 3, 17, 1000000000]
	var travel := [0.0, 0.03, 0.05, 0.99999, 1.3]
	var loss := [-2.0, -0.0, 0.0, 0.25, 1.0, 1.3333333333333333]
	var dangers := [-0.0, 0.125, 0.5, 1.0, 3.0]
	var capacities := [-1, 0, 10000, 50000]
	for index in range(96):
		var edge := Edge.new()
		edge.control_city_id = index % 3 - 1
		edge.precise_distance = precise[index % precise.size()]
		edge.distance = distances[index % distances.size()]
		edge.travel_time_multiplier = travel[index % travel.size()]
		edge.supply_loss_multiplier = loss[index % loss.size()]
		edge.danger = dangers[index % dangers.size()]
		edge.max_manpower = capacities[index % capacities.size()]
		edges.append(edge)
	_configure(graph, edges.size())
	for modes in range(16):
		var result: Dictionary = graph.call("pack_edge_inputs", edges, modes, PackedFloat64Array(CONSTANTS))
		check(not result.has("error"), "valid edge inputs modes=%d" % modes)
		_compare(_oracle(edges, modes), result, "mode%d" % modes)
	# Mutations between standalone calls must be read from live Edge properties.
	var changed: Edge = edges[0]
	changed.max_manpower = 50000
	changed.precise_distance = 1.3333333333333333
	changed.travel_time_multiplier = 0.751234567891
	changed.supply_loss_multiplier = 0.5555555555
	changed.danger = 0.123456789
	_compare(_oracle(edges, 15), graph.call("pack_edge_inputs", edges, 15, PackedFloat64Array(CONSTANTS)), "direct edits")
	# A source literal -0.0 may be folded by GDScript. Construct its actual IEEE
	# sign bit to prove maxf's equality behavior in the supply-loss formula.
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	changed.precise_distance = 1.0
	changed.supply_loss_multiplier = negative_zero
	check(PackedFloat64Array([changed.supply_loss_multiplier]).to_byte_array()[7] == 128, "binary negative zero reaches Edge property")
	var zero_reference := _oracle(edges, 15)
	check((zero_reference.supply as PackedFloat64Array).to_byte_array()[7] == 0, "reference maxf normalizes negative zero loss")
	_compare(zero_reference, graph.call("pack_edge_inputs", edges, 15, PackedFloat64Array(CONSTANTS)), "binary negative zero")
	_invalid_cases(graph, edges)
	var empty_graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	_configure(empty_graph, 0)
	_compare(_oracle([], 15), empty_graph.call("pack_edge_inputs", [], 15, PackedFloat64Array(CONSTANTS)), "no edges")
	_owner_cases()
	_control_cases()
	_finish()

func _configure(graph: RefCounted, count: int) -> void:
	var controls := PackedInt32Array()
	controls.resize(count)
	controls.fill(-1)
	check(graph.call("configure", PackedInt32Array([0, 0]), PackedInt32Array(), PackedInt32Array(), controls, PackedFloat64Array([0.0, 0.0, 0.5, 0.0, 0.0])), "snapshot configures")

func _oracle(edges: Array, modes: int) -> Dictionary:
	var result := {"enabled": PackedByteArray(), "controls": PackedInt32Array(), "path": PackedFloat64Array(), "danger": PackedFloat64Array(), "supply": PackedFloat64Array(), "travel": PackedFloat64Array()}
	for edge: Edge in edges:
		result.enabled.append(1 if edge.max_manpower > 0 else 0)
		# This oracle fixture configures one node. Invalid jurisdiction has the
		# same inaccessible meaning as GameState.atlas_edge_access's bound check.
		result.controls.append(edge.control_city_id if edge.control_city_id == 0 else -1)
		if modes & 1:
			result.path.append(Pathfinding._edge_transport_distance(edge, 0))
		if modes & 2:
			var danger_cost := Pathfinding._edge_transport_distance(edge, 0)
			danger_cost += edge.danger * Pathfinding.DANGER_WEIGHT * (edge.distance_units() if edge.precise_distance >= 0.0 else 1.0)
			result.danger.append(danger_cost)
		if modes & 4:
			result.supply.append(Pathfinding._supply_edge_loss(edge) if edge.max_manpower > 0 else 0.0)
		if modes & 8:
			result.travel.append(Simulation.edge_travel_days(edge, 0))
	return result

func _compare(expected: Dictionary, actual: Dictionary, label: String) -> void:
	for key in expected:
		check(actual.has(key), label + " key " + key)
		if actual.has(key):
			check(var_to_bytes(expected[key]) == var_to_bytes(actual[key]), label + " exact " + key)

func _invalid_cases(graph: RefCounted, edges: Array) -> void:
	check(graph.call("pack_edge_inputs", [], 15, PackedFloat64Array(CONSTANTS)).has("error"), "wrong edge count rejected")
	for replacement in [null, 7, {}, WrongEdge.new()]:
		var invalid := edges.duplicate()
		invalid[0] = replacement
		check(graph.call("pack_edge_inputs", invalid, 15, PackedFloat64Array(CONSTANTS)).has("error"), "null/nonobject/wrong property type rejected")
	for property in ["precise_distance", "travel_time_multiplier", "danger", "supply_loss_multiplier"]:
		for value in [INF, -INF, NAN]:
			var invalid := edges.duplicate()
			var edge := Edge.new()
			edge.set(property, value)
			invalid[0] = edge
			check(graph.call("pack_edge_inputs", invalid, 15, PackedFloat64Array(CONSTANTS)).has("error"), "nonfinite " + property)
	for modes in [-1, 16]:
		check(graph.call("pack_edge_inputs", edges, modes, PackedFloat64Array(CONSTANTS)).has("error"), "unknown mode rejected")
	check(graph.call("pack_edge_inputs", edges, 15, PackedFloat64Array()).has("error"), "missing constants rejected")
	var invalid_constants := PackedFloat64Array(CONSTANTS)
	invalid_constants[0] = NAN
	check(graph.call("pack_edge_inputs", edges, 15, invalid_constants).has("error"), "nonfinite constant rejected")
	var unconfigured: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	check(unconfigured.call("pack_edge_inputs", edges, 15, PackedFloat64Array(CONSTANTS)).has("error"), "unconfigured snapshot rejected")

func _owner_cases() -> void:
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	check(graph.has_method("pack_owner_inputs"), "native pack_owner_inputs is registered")
	var geometry := PackedFloat64Array()
	geometry.resize(30)
	geometry.fill(0.0)
	check(graph.call("configure", PackedInt32Array([0, 0, 0, 0, 0, 0, 0]), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), geometry), "owner snapshot configures")
	var cities: Array = []
	for owner in [2, 2, -1, 3, -2147483648, 2147483647]:
		var city := City.new()
		city.owner_nation = owner
		cities.append(city)
	var result: Dictionary = graph.call("pack_owner_inputs", cities)
	check(var_to_bytes(result.owners) == var_to_bytes(PackedInt32Array([2, 2, -1, 3, -2147483648, 2147483647])), "exact signed32 owners")
	check(var_to_bytes(result.unique) == var_to_bytes(PackedInt32Array([2, -1, 3, -2147483648, 2147483647])), "first discovery owner order")
	cities[0].owner_nation = 4
	result = graph.call("pack_owner_inputs", cities)
	check(var_to_bytes(result.owners) == var_to_bytes(PackedInt32Array([4, 2, -1, 3, -2147483648, 2147483647])), "live owner edit")
	check(var_to_bytes(result.unique) == var_to_bytes(PackedInt32Array([4, 2, -1, 3, -2147483648, 2147483647])), "live owner discovery")
	for entry in [null, 7, {}, WrongCity.new()]:
		var invalid := cities.duplicate()
		invalid[0] = entry
		check(graph.call("pack_owner_inputs", invalid).has("error"), "invalid owner object/type rejected")
	for owner in [-2147483649, 2147483648]:
		cities[0].owner_nation = owner
		check(graph.call("pack_owner_inputs", cities).has("error"), "owner int32 overflow rejected")
	check(graph.call("pack_owner_inputs", []).has("error"), "owner count rejected")
	var empty: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	check(empty.call("configure", PackedInt32Array([0]), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedFloat64Array()), "empty owner snapshot")
	result = empty.call("pack_owner_inputs", [])
	check(result.owners.is_empty() and result.unique.is_empty(), "empty owner arrays")

func _control_cases() -> void:
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	check(graph.call("api_version") == 3, "native administrative batches require API version 3")
	check(graph.call("configure", PackedInt32Array([0, 0, 0, 0]), PackedInt32Array(), PackedInt32Array(), PackedInt32Array([0, 0]), PackedFloat64Array([0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0.])), "live control snapshot configures")
	var edge_a := Edge.new()
	var edge_b := Edge.new()
	edge_a.control_city_id = 0
	edge_b.control_city_id = 2
	var edges: Array = [edge_a, edge_b]
	var packed: Dictionary = graph.call("pack_edge_inputs", edges, 0, PackedFloat64Array(CONSTANTS))
	check(packed.controls == PackedInt32Array([0, 2]), "single packing pass reads current controls")
	var owners := PackedInt32Array([0, 1, 2])
	var permissions := {0: true, 1: false, 2: false}
	var masked: Dictionary = graph.call("make_access_mask", owners, permissions, packed.controls)
	check(masked.mask == PackedByteArray([1, 0]), "permissions use explicit current controls rather than configured owners")
	edge_a.control_city_id = 1
	edge_b.control_city_id = 0
	packed = graph.call("pack_edge_inputs", edges, 0, PackedFloat64Array(CONSTANTS))
	masked = graph.call("make_access_mask", owners, permissions, packed.controls)
	check(packed.controls == PackedInt32Array([1, 0]) and masked.mask == PackedByteArray([0, 1]), "direct jurisdiction edits affect the next packing call")
	check((graph.call("make_access_mask", owners, permissions, PackedInt32Array([0])) as Dictionary).has("error"), "explicit control count is validated")
	check((graph.call("make_access_mask", owners, permissions, PackedInt32Array([-1, 99])) as Dictionary).mask == PackedByteArray([0, 0]), "invalid control IDs are inaccessible")
	var base := PackedByteArray([0, 0])
	var controls := PackedInt32Array([1, 2])
	check((graph.call("patch_access_mask", base, controls, 1, -1) as Dictionary).mask == PackedByteArray([1, 0]), "permitted enemy goal patches its live controls")
	check((graph.call("patch_access_mask", base, controls, -1, 2) as Dictionary).mask == PackedByteArray([0, 1]), "permitted exit patches its live controls")
	check(base == PackedByteArray([0, 0]), "native patch leaves the shared base mask unchanged")
	check((graph.call("patch_access_mask", base, PackedInt32Array([-1, 99]), -1, 99) as Dictionary).mask == base, "patch never opens invalid controls")
	check((graph.call("patch_access_mask", base, PackedInt32Array([1]), 1, -1) as Dictionary).has("error"), "patch control count is validated")
	edge_a.control_city_id = 9223372036854775807
	edge_b.control_city_id = -9223372036854775807
	packed = graph.call("pack_edge_inputs", edges, 0, PackedFloat64Array(CONSTANTS))
	check(packed.controls == PackedInt32Array([-1, -1]), "arbitrary int64 jurisdiction is rejected as inaccessible without narrowing")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", label)

func _finish() -> void:
	print("NATIVE_EDGE_INPUTS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
