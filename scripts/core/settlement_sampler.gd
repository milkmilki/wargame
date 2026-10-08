class_name SettlementSampler
extends RefCounted
## Weighted sampling without replacement; local spacing, never global farthest-point scans.
const VERSION := "weighted_local_v2"
const MIN_SUITABILITY := 0.0005
const SPACING_SCALES := [1.0, 0.95, 0.90, 0.85, 0.80]
const RiverSupport = preload("res://scripts/core/river_settlement_support.gd")
const ValleySupport = preload("res://scripts/core/valley_water_support.gd")
const PhysicalLand = preload("res://scripts/core/terrain_land_components.gd")

static func sample(source: Image, mask: PackedByteArray, environment: Dictionary, city_count: int, aspect: float, seed_value: int, reserved_docks: Array = [], density_bounds: Dictionary = {}) -> Dictionary:
	var started := Time.get_ticks_usec()
	var bounds_error := MapSource.validate_density_bounds(density_bounds)
	if not bounds_error.is_empty(): return {"ok":false,"error":bounds_error,"generation_metadata":{"seed":seed_value}}
	var minimum_density := float(density_bounds.get("minimum",0.0))
	var maximum_density := float(density_bounds.get("maximum",1.0))
	var candidate_threshold := minf(minimum_density,MIN_SUITABILITY) if minimum_density>0.0 else MIN_SUITABILITY
	var size: Vector2i = environment["size"]
	var source_size := source.get_size()
	var source_scale := Vector2(source_size)
	var suitability: PackedFloat32Array = environment["suitability"].duplicate()
	var uniform: bool = environment.get("river_settlement_model", "flow_weighted") in ["uniform_v1","valley_v1"]
	var local_crossings: bool = environment.get("local_crossings", false)
	var river_possible: PackedByteArray = environment.get("river_support_possible", PackedByteArray())
	var rainfed_suitability: PackedFloat64Array = environment.get("rainfed_suitability", PackedFloat64Array())
	var maximum_suitability: PackedFloat64Array = environment.get("maximum_suitability", PackedFloat64Array())
	var river_candidates := 0
	var rejection_counts := {"environment": 0, "small_component": 0, "terrain_or_bank": 0, "dock_clearance": 0}
	var dock_clearance := TerrainMapGenerator.minimum_dock_city_spacing_for_count(city_count)
	var dock_buckets := {}
	for dock in reserved_docks:
		var p: Vector2 = dock.position * Vector2(aspect, 1.0)
		var first := Vector2i(((p - Vector2.ONE * dock_clearance) / dock_clearance).floor())
		var last := Vector2i(((p + Vector2.ONE * dock_clearance) / dock_clearance).floor())
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, y)
				if not dock_buckets.has(key): dock_buckets[key] = []
				dock_buckets[key].append(p)
	var count := mask.size()
	var priorities := PackedFloat64Array()
	priorities.resize(count)
	var positions := PackedVector2Array()
	positions.resize(count)
	var spacing := PackedFloat32Array()
	spacing.resize(count)
	var selected_flags := PackedByteArray()
	selected_flags.resize(count)
	var order: Array[int] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base_spacing := 0.060 * sqrt(64.0 / maxf(city_count, 1))
	var river_cells := _river_cell_segments(environment.get("hydrology", {}).get("features", []), size)
	var dock_corridor: PackedByteArray = environment.get("hydrology", {}).get("dock_corridor", PackedByteArray())
	var component_area := {}
	if not dock_corridor.is_empty():
		for component in environment.components:
			if component >= 0: component_area[component] = int(component_area.get(component, 0)) + 1
	var minimum_hinterland := PI * pow(TerrainMapGenerator.minimum_dock_city_spacing_for_count(city_count), 2.0)
	var physical: Dictionary = environment.get("physical_components", {})
	for i in range(count):
		if mask[i] == 0: continue
		suitability[i]=clampf(suitability[i],minimum_density,maximum_density)
		if minimum_density==0.0 and uniform and not river_possible.is_empty() and river_possible[i] == 0 and (rainfed_suitability[i] if not rainfed_suitability.is_empty() else RiverSupport.suitability(environment, i, 0.0)) < candidate_threshold:
			rejection_counts.environment += 1
			continue
		if (not uniform and suitability[i] < candidate_threshold) or (minimum_density==0.0 and uniform and (maximum_suitability[i] if not maximum_suitability.is_empty() else RiverSupport.suitability(environment, i, 1.0)) < candidate_threshold):
			rejection_counts.environment += 1
			continue
		if not component_area.is_empty() and float(component_area.get(environment.components[i], 0)) * aspect / count < minimum_hinterland:
			rejection_counts.small_component += 1
			# A tiny polygon cut off by a river cannot hold a city and a crossing
			# with the required clearance. It remains legitimately unassigned.
			continue
		var position := Vector2.ZERO
		var valid := false
		for attempt in range(4):
			position = (Vector2(i % size.x, i / size.x) + Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85))) / Vector2(size)
			var pixel := Vector2i(position * source_scale).clamp(Vector2i.ZERO, source_size - Vector2i.ONE)
			if source.get_pixelv(pixel).a * 255.0 > 128.5:
				if not physical.is_empty():
					var component := PhysicalLand.at(physical, position)
					if float(physical.areas.get(component, 0)) * aspect / (source_size.x * source_size.y) < minimum_hinterland:
						rejection_counts.small_component += 1
						continue
				var center := (Vector2(i % size.x, i / size.x) + Vector2.ONE * 0.5) / Vector2(size)
				var bank_valid := true
				for segment in river_cells.get(i, []):
					if Geometry2D.segment_intersects_segment(center, position, segment[0], segment[1]) != null:
						bank_valid = false
						break
				if not bank_valid: continue
				if uniform or local_crossings:
					var metric_position := position * Vector2(aspect, 1.0)
					var reserved := false
					for dock_position in dock_buckets.get(Vector2i((metric_position / dock_clearance).floor()), []):
						if metric_position.distance_squared_to(dock_position) < dock_clearance * dock_clearance:
							reserved = true
							break
					if reserved:
						rejection_counts.dock_clearance += 1
						continue
				if uniform:
					var support := RiverSupport.support_at(environment.river_support_index, source, position)
					if environment.has("valley_support"): support=maxf(support,ValleySupport.support_at(environment.valley_support,source,position))
					suitability[i] = clampf(RiverSupport.suitability(environment, i, support),minimum_density,maximum_density)
					if suitability[i] < candidate_threshold:
						rejection_counts.environment += 1
						continue
					if support > 0.0: river_candidates += 1
				valid = true
				break
		if not valid:
			rejection_counts.terrain_or_bank += 1
			continue
		positions[i] = position
		spacing[i] = base_spacing / sqrt(suitability[i])
		if not uniform and not local_crossings and not dock_corridor.is_empty() and dock_corridor[i] != 0:
			# Leave usable gaps for crossings without excluding river-bank cities.
			spacing[i] = maxf(spacing[i], TerrainMapGenerator.minimum_dock_city_spacing_for_count(city_count) * 2.2 / 0.8)
		priorities[i] = -log(maxf(rng.randf(), 0.0000001)) / suitability[i]
		order.append(i)
	var candidates_usec := Time.get_ticks_usec() - started
	order.sort_custom(func(a: int, b: int) -> bool:
		if priorities[a] != priorities[b]:
			return priorities[a] < priorities[b]
		return a < b
	)
	if environment.has("components"):
		var mass := {}
		var total := 0.0
		for i in order:
			var component: int = environment.components[i]
			mass[component] = float(mass.get(component, 0.0)) + suitability[i]
			total += suitability[i]
		var preferred: Array[int] = []
		var remaining: Array[int] = []
		var reserved := {}
		for i in order:
			var component: int = environment.components[i]
			if not reserved.has(component) and float(mass[component]) * city_count >= total:
				preferred.append(i)
				reserved[component] = true
			else: remaining.append(i)
		order = preferred + remaining
	var selected: Array[int] = []
	var grid := {}
	var bucket_width := base_spacing * 2.0
	var maximum_spacing := 0.0
	var final_scale := 1.0
	for scale_value in SPACING_SCALES:
		final_scale = float(scale_value)
		for i in order:
			if selected_flags[i] != 0:
				continue
			var p := positions[i] * Vector2(aspect, 1.0)
			var bucket := Vector2i(floor(p.x / bucket_width), floor(p.y / bucket_width))
			var radius := (spacing[i] + maximum_spacing) * 0.5 * final_scale
			var reach := int(ceil(radius / bucket_width))
			var clear := true
			# Wide queries otherwise scan thousands of empty spatial buckets.
			if reach > 3:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						for j in grid.get(bucket + Vector2i(dx, dy), []):
							var minimum := (spacing[i] + spacing[j]) * 0.5 * final_scale
							if (p - positions[j] * Vector2(aspect, 1.0)).length_squared() < minimum * minimum:
								clear = false
				if not clear: continue
				for j in selected:
					var minimum := (spacing[i] + spacing[j]) * 0.5 * final_scale
					if (p - positions[j] * Vector2(aspect, 1.0)).length_squared() < minimum * minimum:
						clear = false
						break
			for dy in range(-reach, reach + 1) if reach <= 3 else []:
				if not clear: break
				for dx in range(-reach, reach + 1):
					var key := bucket + Vector2i(dx, dy)
					if not grid.has(key): continue
					for j in grid[key]:
						var minimum := (spacing[i] + spacing[j]) * 0.5 * final_scale
						var delta := p - positions[j] * Vector2(aspect, 1.0)
						if delta.length_squared() < minimum * minimum:
							clear = false
							break
					if not clear: break
			if not clear: continue
			selected.append(i)
			selected_flags[i] = 1
			maximum_spacing = maxf(maximum_spacing, spacing[i])
			if not grid.has(bucket): grid[bucket] = []
			grid[bucket].append(i)
			if selected.size() >= city_count: break
		if selected.size() >= city_count: break
	var metadata := {"sampler_version": VERSION, "candidate_count": order.size(), "selected_count": selected.size(), "spacing_scale": final_scale, "sampling_usec": Time.get_ticks_usec() - started, "seed": seed_value}
	metadata["settlement_density_bounds"]={"minimum":minimum_density,"maximum":maximum_density}
	metadata.merge({"candidate_rejections": rejection_counts, "candidate_usec": candidates_usec, "reserved_dock_count": reserved_docks.size()})
	if uniform:
		metadata.merge({"river_settlement_model": environment.get("river_settlement_model","uniform_v1"), "river_support_version": RiverSupport.VERSION, "river_support_radius":environment.river_support_index.radius, "valley_support_version":ValleySupport.VERSION if environment.has("valley_support") else "", "river_candidate_count": river_candidates, "reserved_dock_count": reserved_docks.size(), "candidate_rejections": rejection_counts, "candidate_usec": candidates_usec})
	if selected.size() < city_count:
		return {"ok": false, "error": "适居候选与允许间距只能容纳 %d 座城市（请求 %d）；请减少城市数或调整纬度范围。" % [selected.size(), city_count], "generation_metadata": metadata}
	selected.sort()
	var final_positions: Array[Vector2] = []
	var pixels: Array[Vector2i] = []
	var heights: Array[float] = []
	var reliefs: Array[float] = []
	for i in selected:
		final_positions.append(positions[i])
		pixels.append(Vector2i(i % size.x, i / size.x))
		var pixel := Vector2i(positions[i] * source_scale).clamp(Vector2i.ZERO, source_size - Vector2i.ONE)
		heights.append(maxf((source.get_pixelv(pixel).a * 255.0 - 128.0) / 127.0, 0.0))
		reliefs.append(environment["relief"][i])
	var result := {"ok": true, "positions": final_positions, "pixels": pixels, "heights": heights, "reliefs": reliefs, "generation_metadata": metadata}
	if local_crossings:
		result["candidate_pool"] = {"order": order, "positions": positions, "spacing": spacing, "weights": suitability, "components": environment.get("components", PackedInt32Array()), "size": size, "aspect": aspect, "relief": environment.relief}
	return result

## A jittered seed must remain on its province-cell centre's river bank.
## Otherwise every legal cell-centre road would start by crossing the river.
static func _river_cell_segments(features: Array, size: Vector2i) -> Dictionary:
	var result := {}
	for feature in MapFeatureContract.major_rivers(features):
		var points: PackedVector2Array = feature.points
		for k in range(points.size() - 1):
			var a := Vector2i((points[k].min(points[k + 1]) * Vector2(size)).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
			var b := Vector2i((points[k].max(points[k + 1]) * Vector2(size)).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
			for y in range(a.y, b.y + 1):
				for x in range(a.x, b.x + 1):
					var i := y * size.x + x
					if not result.has(i): result[i] = []
					result[i].append([points[k], points[k + 1]])
	return result
