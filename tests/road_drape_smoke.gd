extends SceneTree
## Verifies that rendered road samples follow terrain height between cities.

const TIMEOUT_MSEC := 15000
const ROAD_ELEVATION := 0.125


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var overlay := MapRenderer.new()
	root.add_child(overlay)
	overlay.setup(state, simulation)
	overlay.set_world_layer_visible(false)
	var map_3d := StrategicMap3D.new()
	root.add_child(map_3d)
	map_3d.setup(state, simulation, overlay)
	var started := Time.get_ticks_msec()
	while (
		map_3d._terrain == null
		or map_3d._terrain.land_cell_count() <= 0
	):
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("ROAD_DRAPE_TIMEOUT")
			quit(1)
			return
		await process_frame

	var tested_samples := PackedVector3Array()
	var tested_from := Vector2.ZERO
	var tested_to := Vector2.ZERO
	for edge in state.edges:
		if edge.kind != Edge.Kind.LAND or edge.max_manpower <= 0:
			continue
		var from := state.cities[edge.city_a].map_position
		var to := state.cities[edge.city_b].map_position
		var samples := map_3d._draped_world_samples(
			from,
			to,
			ROAD_ELEVATION
		)
		var min_y := INF
		var max_y := -INF
		for sample in samples:
			min_y = minf(min_y, sample.y)
			max_y = maxf(max_y, sample.y)
		if max_y - min_y > 0.08:
			tested_samples = samples
			tested_from = from
			tested_to = to
			break
	if tested_samples.size() < 9:
		push_error("ROAD_DRAPE_NO_RELIEF_EDGE")
		quit(1)
		return
	for index in range(tested_samples.size()):
		var ratio := float(index) / float(tested_samples.size() - 1)
		var map_position := tested_from.lerp(tested_to, ratio)
		var expected := (
			map_3d._terrain.height_at_map_position(map_position)
			+ ROAD_ELEVATION
		)
		if absf(tested_samples[index].y - expected) > 0.0001:
			push_error("ROAD_DRAPE_HEIGHT_MISMATCH")
			quit(1)
			return
	var major_mesh := map_3d._roads.mesh as ArrayMesh
	var minor_mesh := map_3d._minor_roads.mesh as ArrayMesh
	var major_vertices: PackedVector3Array = (
		major_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	)
	var minor_vertices: PackedVector3Array = (
		minor_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	)
	var vertex_count := major_vertices.size() + minor_vertices.size()
	if (
		vertex_count <= state.edges.size() * 12
		or map_3d._road_width_for_capacity(Edge.TERRAIN_STANDARD_MANPOWER)
			<= map_3d._road_width_for_capacity(Edge.TERRAIN_LOW_MANPOWER)
	):
		push_error("ROAD_DRAPE_GEOMETRY_TOO_SIMPLE")
		quit(1)
		return
	print(
		"ROAD_DRAPE_OK samples=",
		tested_samples.size(),
		" vertices=",
		vertex_count,
		" elevation_span=",
		tested_samples[0].distance_to(
			tested_samples[-1]
		)
	)
	map_3d.free()
	overlay.free()
	simulation.free()
	quit(0)
