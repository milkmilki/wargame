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
	var valid: bool = (
		region_ids == repeated["region_ids"]
		and centers == repeated["center_city_ids"]
		and center_by_city == repeated["center_by_city"]
		and hops == repeated["hop_distances"]
		and centers.has(6)
		and center_by_city[6] == 6
		and hops[6] == 0
	)
	for city_id in active:
		valid = (
			valid
			and region_ids[city_id] >= 0
			and center_by_city[city_id] >= 0
			and hops[city_id] >= 0
			and hops[city_id] <= 1
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
	for city in generated_state.cities:
		if not city.politically_active or city.is_dock:
			continue
		generated_max_hops = maxi(
			generated_max_hops,
			generated_state.administrative_hop_distances[city.id]
		)
	valid = valid and generated_max_hops <= 1
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
