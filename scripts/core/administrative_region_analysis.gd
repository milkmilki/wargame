class_name AdministrativeRegionAnalysis
extends RefCounted
## Deterministic administrative regions. The partition graph is land-only:
## centers first claim their one-hop neighborhoods, and the selector refuses
## to open a state that would cover only itself, so every land-reachable
## center keeps at least one land neighbor at hop one.
##
## A politically active city with no land link at all cannot be covered that
## way. Promoting it to a one-city state would recreate exactly the shape the
## selector refuses to create, so instead it joins a neighboring state as a
## Fu over the attachment graph (landing, river and sea links), which makes
## the adopted Fu a real neighbor of its state.
##
## Adoption only follows links between two administrable cities. A dock is an
## independently assigned node in the initial nation partition, so a state
## that reaches its Fu through a dock can be split from that dock and turn the
## Fu into an enclave reachable only through foreign ports. A city whose only
## link is a dock therefore keeps its own state; that is the one remaining
## shape where a state can hold no Fu.

## Fringe cities attach at most this far from their state in the graph used
## for adoption, mirroring the land fringe cap.
const MAX_FRINGE_HOPS: int = 2


static func analyze(
	city_count: int,
	active_city_ids: PackedInt32Array,
	links: Array[Vector2i],
	positions: PackedVector2Array = PackedVector2Array(),
	attachment_links: Array[Vector2i] = []
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
	var assignment := _nearest_center_assignment(
		city_count, adjacency, centers
	)
	var region_ids: PackedInt32Array = assignment["region_ids"]
	var hop_distances: PackedInt32Array = assignment["hop_distances"]
	_adopt_land_isolated_cities(
		active,
		_build_adjacency(city_count, active_set, attachment_links),
		centers,
		region_ids,
		hop_distances
	)
	var center_by_city := PackedInt32Array()
	center_by_city.resize(maxi(city_count, 0))
	center_by_city.fill(-1)
	for city_id in active:
		center_by_city[city_id] = centers[region_ids[city_id]]
	return {
		"region_ids": region_ids,
		"region_count": centers.size(),
		"center_city_ids": PackedInt32Array(centers),
		"center_by_city": center_by_city,
		"hop_distances": hop_distances,
	}


## Land-isolated active cities join a neighboring state instead of becoming
## one-city states. Cities are visited in ascending id order and every
## adoption is written immediately, so a chain of isolated cities resolves
## through the first city of the chain that already belongs to a state.
##
## Adoption only follows real links. Merging a city that has no passable link
## to its state would leave that state internally unreachable, and the initial
## nation partition collapses every state into a single graph node, so such a
## city has to open its own state instead.
static func _adopt_land_isolated_cities(
	active: Array[int],
	attachment: Array[Array],
	centers: Array[int],
	region_ids: PackedInt32Array,
	hop_distances: PackedInt32Array
) -> void:
	for city_id in active:
		if region_ids[city_id] >= 0:
			continue
		var reached := _attachment_region(city_id, attachment, region_ids)
		var reached_region := int(reached["region"])
		if reached_region >= 0:
			region_ids[city_id] = reached_region
			hop_distances[city_id] = mini(
				int(reached["hops"]), MAX_FRINGE_HOPS
			)
			continue
		region_ids[city_id] = centers.size()
		hop_distances[city_id] = 0
		centers.append(city_id)


## Closest state already owning a city, reached over the attachment graph.
## The search is bounded only by the city's own attachment component, so a
## chain of isolated cities resolves as soon as it meets an assigned one.
## Returns region -1 when that component holds no state at all.
static func _attachment_region(
	start: int,
	attachment: Array[Array],
	region_ids: PackedInt32Array
) -> Dictionary:
	var visited := {start: true}
	var frontier: Array[int] = [start]
	var hops := 0
	while not frontier.is_empty():
		hops += 1
		var next: Array[int] = []
		for current in frontier:
			for neighbor_value in attachment[current]:
				var neighbor := int(neighbor_value)
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				if region_ids[neighbor] >= 0:
					return {
						"region": region_ids[neighbor],
						"hops": hops,
					}
				next.append(neighbor)
		frontier = next
	return {"region": -1, "hops": 0}


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
		# The candidate itself counts as one. Requiring a second uncovered city
		# prevents a leftover corner from becoming a one-city administrative state.
		if uncovered_one <= 1:
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


static func _nearest_center_assignment(
	city_count: int,
	adjacency: Array[Array],
	centers: Array[int]
) -> Dictionary:
	var region_ids := PackedInt32Array()
	var hop_distances := PackedInt32Array()
	region_ids.resize(maxi(city_count, 0))
	hop_distances.resize(maxi(city_count, 0))
	region_ids.fill(-1)
	hop_distances.fill(-1)
	var queue: Array[int] = []
	for region_id in range(centers.size()):
		var center := centers[region_id]
		region_ids[center] = region_id
		hop_distances[center] = 0
		queue.append(center)
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor_value in adjacency[current]:
			var neighbor := int(neighbor_value)
			if hop_distances[neighbor] >= 0:
				continue
			region_ids[neighbor] = region_ids[current]
			hop_distances[neighbor] = hop_distances[current] + 1
			queue.append(neighbor)
	return {
		"region_ids": region_ids,
		"hop_distances": hop_distances,
	}


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
