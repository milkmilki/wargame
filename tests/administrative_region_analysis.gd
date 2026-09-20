extends SceneTree


func _init() -> void:
	var active := PackedInt32Array([0, 1, 2, 3, 4, 5, 6])
	var links: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3),
		Vector2i(3, 4), Vector2i(4, 5),
	]
	var positions := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(2.0, 0.0),
		Vector2(3.0, 0.0), Vector2(4.0, 0.0), Vector2(5.0, 0.0),
		Vector2(10.0, 0.0),
	])
	var result := AdministrativeRegionAnalysis.analyze(
		7, active, links, positions
	)
	var reversed_links := links.duplicate()
	reversed_links.reverse()
	var repeated := AdministrativeRegionAnalysis.analyze(
		7, active, reversed_links, positions
	)
	var region_ids: PackedInt32Array = result["region_ids"]
	var centers: PackedInt32Array = result["center_city_ids"]
	var center_by_city: PackedInt32Array = result["center_by_city"]
	var hops: PackedInt32Array = result["hop_distances"]
	var region_sizes := {}
	for city_id in active:
		var region_id := region_ids[city_id]
		region_sizes[region_id] = int(region_sizes.get(region_id, 0)) + 1
	var valid: bool = (
		region_ids == repeated["region_ids"]
		and centers == repeated["center_city_ids"]
		and center_by_city == repeated["center_by_city"]
		and hops == repeated["hop_distances"]
		and centers.has(6)
		and center_by_city[6] == 6
		and hops[6] == 0
		and hops[0] == 2
		and int(region_sizes[region_ids[6]]) == 1
	)
	for city_id in active:
		valid = (
			valid
			and region_ids[city_id] >= 0
			and center_by_city[city_id] >= 0
			and hops[city_id] >= 0
			and hops[city_id] <= 2
			and (
				city_id == 6
				or int(region_sizes[region_ids[city_id]]) >= 2
			)
		)
	for link in links:
		valid = valid and not (
			centers.has(link.x) and centers.has(link.y)
		)
	var boundary_active := PackedInt32Array([0, 1, 3, 4])
	var boundary_links: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(3, 4),
	]
	var boundary := AdministrativeRegionAnalysis.analyze(
		5,
		boundary_active,
		boundary_links,
		PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(2.0, 0.0),
			Vector2(3.0, 0.0), Vector2(4.0, 0.0),
		])
	)
	var boundary_ids: PackedInt32Array = boundary["region_ids"]
	valid = (
		valid
		and boundary_ids[2] == -1
		and boundary_ids[0] == boundary_ids[1]
		and boundary_ids[3] == boundary_ids[4]
		and boundary_ids[1] != boundary_ids[3]
	)
	var generated_state := GameState.new()
	generated_state.generate_world(94001)
	var generated_max_hops := 0
	var generated_region_sizes := {}
	for city in generated_state.cities:
		if not city.politically_active or city.is_dock:
			continue
		var generated_region_id := (
			generated_state.administrative_region_ids[city.id]
		)
		generated_region_sizes[generated_region_id] = int(
			generated_region_sizes.get(generated_region_id, 0)
		) + 1
		generated_max_hops = maxi(
			generated_max_hops,
			generated_state.administrative_hop_distances[city.id]
		)
	valid = valid and generated_max_hops <= 2
	for city in generated_state.cities:
		if not city.politically_active or city.is_dock:
			continue
		var generated_region_id := (
			generated_state.administrative_region_ids[city.id]
		)
		if int(generated_region_sizes[generated_region_id]) > 1:
			continue
		valid = valid and _is_isolated_land_city(generated_state, city.id)
	if valid:
		print(
			"ADMINISTRATIVE_REGION_ANALYSIS_OK regions=%s centers=%s hops=%s generated_regions=%d generated_max_hops=%d"
			% [
				str(region_ids), str(centers), str(hops),
				generated_state.administrative_region_count,
				generated_max_hops,
			]
		)
		quit(0)
		return
	push_error(
		"ADMINISTRATIVE_REGION_ANALYSIS_FAILED result=%s boundary=%s"
		% [str(result), str(boundary)]
	)
	quit(1)


func _is_isolated_land_city(state: GameState, city_id: int) -> bool:
	for neighbor_id in state.neighbors(city_id):
		var neighbor := state.cities[neighbor_id]
		var edge := state.edge_of(city_id, neighbor_id)
		if (
			edge != null
			and edge.kind == Edge.Kind.LAND
			and edge.max_manpower > 0
			and neighbor.politically_active
			and not neighbor.is_dock
		):
			return false
	return true
