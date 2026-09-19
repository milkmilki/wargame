class_name AdministrativeRegionAnalysis
extends RefCounted
## Deterministic land-only administrative regions. Center selection continues
## until every normal city is covered in one hop. Two-hop assignment remains a
## defensive fallback for malformed or otherwise unassignable fringe input.


static func analyze(
	city_count: int,
	active_city_ids: PackedInt32Array,
	links: Array[Vector2i],
	positions: PackedVector2Array = PackedVector2Array()
) -> Dictionary:
	var active: Array[int] = []
	var active_set := {}
	for city_value in active_city_ids:
		var city_id := int(city_value)
		if city_id < 0 or city_id >= city_count or active_set.has(city_id):
			continue
		active_set[city_id] = true
		active.append(city_id)
	active.sort()
	var adjacency := _build_adjacency(city_count, active_set, links)
	var centrality: PackedFloat32Array = (
		RegionGraphAnalysis.analyze(
			city_count, PackedInt32Array(active), links
		)["betweenness"]
		if not active.is_empty()
		else PackedFloat32Array()
	)
	var centers: Array[int] = []
	var min_hops := PackedInt32Array()
	min_hops.resize(maxi(city_count, 0))
	min_hops.fill(-1)
	while _has_city_beyond_one_hop(active, min_hops):
		var best := _select_center(
			active, adjacency, centers, min_hops, centrality, positions
		)
		if best < 0:
			break
		centers.append(best)
		min_hops = _minimum_hops(city_count, active, adjacency, centers)
	var region_ids := PackedInt32Array()
	var center_by_city := PackedInt32Array()
	var hop_distances := PackedInt32Array()
	region_ids.resize(maxi(city_count, 0))
	center_by_city.resize(maxi(city_count, 0))
	hop_distances.resize(maxi(city_count, 0))
	region_ids.fill(-1)
	center_by_city.fill(-1)
	hop_distances.fill(-1)
	for city_id in active:
		var best_region := -1
		var best_distance := 3
		for region_id in range(centers.size()):
			var distance := _distance_within_two(
				centers[region_id], city_id, adjacency
			)
			if distance >= 0 and distance < best_distance:
				best_distance = distance
				best_region = region_id
		if best_region < 0:
			# Defensive fallback for malformed disconnected input.
			best_region = centers.size()
			centers.append(city_id)
			best_distance = 0
		region_ids[city_id] = best_region
		center_by_city[city_id] = centers[best_region]
		hop_distances[city_id] = best_distance
	return {
		"region_ids": region_ids,
		"region_count": centers.size(),
		"center_city_ids": PackedInt32Array(centers),
		"center_by_city": center_by_city,
		"hop_distances": hop_distances,
	}


static func _build_adjacency(
	city_count: int,
	active_set: Dictionary,
	links: Array[Vector2i]
) -> Array[Array]:
	var adjacency: Array[Array] = []
	adjacency.resize(maxi(city_count, 0))
	for city_id in range(adjacency.size()):
		adjacency[city_id] = [] as Array[int]
	var seen := {}
	for link in links:
		var city_a := mini(link.x, link.y)
		var city_b := maxi(link.x, link.y)
		if city_a == city_b or not active_set.has(city_a) or not active_set.has(city_b):
			continue
		var key := "%d:%d" % [city_a, city_b]
		if seen.has(key):
			continue
		seen[key] = true
		(adjacency[city_a] as Array[int]).append(city_b)
		(adjacency[city_b] as Array[int]).append(city_a)
	for neighbors in adjacency:
		neighbors.sort()
	return adjacency


static func _select_center(
	active: Array[int],
	adjacency: Array[Array],
	centers: Array[int],
	min_hops: PackedInt32Array,
	centrality: PackedFloat32Array,
	positions: PackedVector2Array
) -> int:
	var best := -1
	var best_score: Array = []
	for candidate in active:
		if _adjacent_to_center(candidate, adjacency, centers):
			continue
		var within_one := _nodes_within(candidate, adjacency, 1)
		var within_two := _nodes_within(candidate, adjacency, 2)
		var uncovered_one := 0
		var uncovered_two := 0
		for city_id in within_one:
			if min_hops[city_id] < 0 or min_hops[city_id] > 1:
				uncovered_one += 1
		for city_id in within_two:
			if min_hops[city_id] < 0 or min_hops[city_id] > 1:
				uncovered_two += 1
		if uncovered_one <= 0:
			continue
		var score: Array = [
			uncovered_one,
			uncovered_two,
			float(centrality[candidate]) if candidate < centrality.size() else 0.0,
			(adjacency[candidate] as Array).size(),
		]
		if best < 0 or _candidate_better(
			candidate, score, best, best_score, positions
		):
			best = candidate
			best_score = score
	return best


static func _candidate_better(
	candidate: int,
	score: Array,
	current: int,
	current_score: Array,
	positions: PackedVector2Array
) -> bool:
	for index in range(score.size()):
		if not is_equal_approx(float(score[index]), float(current_score[index])):
			return float(score[index]) > float(current_score[index])
	if candidate < positions.size() and current < positions.size():
		var a := positions[candidate]
		var b := positions[current]
		if not is_equal_approx(a.y, b.y):
			return a.y < b.y
		if not is_equal_approx(a.x, b.x):
			return a.x < b.x
	return candidate < current


static func _adjacent_to_center(
	candidate: int,
	adjacency: Array[Array],
	centers: Array[int]
) -> bool:
	for center in centers:
		if (adjacency[candidate] as Array[int]).has(center):
			return true
	return false


static func _has_city_beyond_one_hop(
	active: Array[int],
	min_hops: PackedInt32Array
) -> bool:
	for city_id in active:
		if min_hops[city_id] < 0 or min_hops[city_id] > 1:
			return true
	return false


static func _minimum_hops(
	city_count: int,
	active: Array[int],
	adjacency: Array[Array],
	centers: Array[int]
) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(maxi(city_count, 0))
	result.fill(-1)
	for city_id in active:
		for center in centers:
			var distance := _distance_within_two(center, city_id, adjacency)
			if distance >= 0 and (result[city_id] < 0 or distance < result[city_id]):
				result[city_id] = distance
	return result


static func _distance_within_two(
	start: int,
	target: int,
	adjacency: Array[Array]
) -> int:
	if start == target:
		return 0
	if (adjacency[start] as Array[int]).has(target):
		return 1
	for neighbor in adjacency[start]:
		if (adjacency[int(neighbor)] as Array[int]).has(target):
			return 2
	return -1


static func _nodes_within(
	start: int,
	adjacency: Array[Array],
	max_distance: int
) -> Array[int]:
	var result: Array[int] = [start]
	if max_distance <= 0:
		return result
	for neighbor in adjacency[start]:
		var city_id := int(neighbor)
		if not result.has(city_id):
			result.append(city_id)
	if max_distance >= 2:
		var direct := result.duplicate()
		for city_id in direct:
			for neighbor in adjacency[city_id]:
				var next := int(neighbor)
				if not result.has(next):
					result.append(next)
	return result
