class_name RegionGraphAnalysis
extends RefCounted
## Deterministic Leiden community detection and unweighted Brandes node
## betweenness for a static transport graph.

const DEFAULT_RESOLUTION: float = 1.0
const KEY_CITY_SHARE: float = 0.05
const MAX_LOCAL_MOVE_PASSES: int = 64
const MAX_LEVELS: int = 16
const EPSILON: float = 0.000000001


static func analyze(
	city_count: int,
	active_city_ids: PackedInt32Array,
	links: Array[Vector2i],
	resolution: float = DEFAULT_RESOLUTION
) -> Dictionary:
	var active: Array[int] = []
	var active_set := {}
	for city_value in active_city_ids:
		var city_id := int(city_value)
		if (
			city_id < 0
			or city_id >= city_count
			or active_set.has(city_id)
		):
			continue
		active_set[city_id] = true
		active.append(city_id)
	active.sort()
	var adjacency := _build_adjacency(city_count, active_set, links)
	var region_ids := _leiden_partition(
		adjacency, active, maxf(resolution, EPSILON), city_count
	)
	var betweenness := _brandes_betweenness(
		adjacency, active, city_count
	)
	var key_city_ids := _key_cities(active, betweenness)
	var region_count := 0
	for city_id in active:
		region_count = maxi(region_count, region_ids[city_id] + 1)
	return {
		"region_ids": region_ids,
		"region_count": region_count,
		"betweenness": betweenness,
		"key_city_ids": key_city_ids,
	}


static func _build_adjacency(
	city_count: int,
	active_set: Dictionary,
	links: Array[Vector2i]
) -> Array[Dictionary]:
	var adjacency: Array[Dictionary] = []
	adjacency.resize(maxi(city_count, 0))
	for city_id in range(adjacency.size()):
		adjacency[city_id] = {}
	var seen := {}
	for raw_link in links:
		var city_a := mini(raw_link.x, raw_link.y)
		var city_b := maxi(raw_link.x, raw_link.y)
		if (
			city_a == city_b
			or not active_set.has(city_a)
			or not active_set.has(city_b)
		):
			continue
		var key := "%d:%d" % [city_a, city_b]
		if seen.has(key):
			continue
		seen[key] = true
		adjacency[city_a][city_b] = 1.0
		adjacency[city_b][city_a] = 1.0
	return adjacency


static func _leiden_partition(
	original_adjacency: Array[Dictionary],
	active: Array[int],
	resolution: float,
	city_count: int
) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(maxi(city_count, 0))
	result.fill(-1)
	if active.is_empty():
		return result
	var graph: Array[Dictionary] = []
	var groups: Array[Array] = []
	var original_to_local := {}
	for local_id in range(active.size()):
		original_to_local[active[local_id]] = local_id
		graph.append({})
		groups.append([active[local_id]])
	for original_a in active:
		var local_a := int(original_to_local[original_a])
		for original_b_value in original_adjacency[original_a]:
			var original_b := int(original_b_value)
			if not original_to_local.has(original_b):
				continue
			graph[local_a][int(original_to_local[original_b])] = float(
				original_adjacency[original_a][original_b]
			)
	for _level in range(MAX_LEVELS):
		var partition := _local_move_partition(graph, resolution)
		partition = _split_disconnected_communities(graph, partition, groups)
		partition = _normalize_partition(partition, groups)
		var community_count := _partition_count(partition)
		if community_count >= graph.size():
			for node_id in range(graph.size()):
				for original_id_value in groups[node_id]:
					result[int(original_id_value)] = partition[node_id]
			return _normalize_result_ids(result, active)
		var aggregated := _aggregate_graph(graph, groups, partition)
		graph = aggregated["adjacency"]
		groups = aggregated["groups"]
	for node_id in range(graph.size()):
		for original_id_value in groups[node_id]:
			result[int(original_id_value)] = node_id
	return _normalize_result_ids(result, active)


static func _local_move_partition(
	adjacency: Array[Dictionary],
	resolution: float
) -> PackedInt32Array:
	var node_count := adjacency.size()
	var communities := PackedInt32Array()
	var degrees := PackedFloat64Array()
	var totals := PackedFloat64Array()
	communities.resize(node_count)
	degrees.resize(node_count)
	totals.resize(node_count)
	var total_degree := 0.0
	for node_id in range(node_count):
		communities[node_id] = node_id
		var degree := 0.0
		for weight_value in adjacency[node_id].values():
			degree += float(weight_value)
		degrees[node_id] = degree
		totals[node_id] = degree
		total_degree += degree
	if total_degree <= EPSILON:
		return communities
	for _pass in range(MAX_LOCAL_MOVE_PASSES):
		var moved := false
		for node_id in range(node_count):
			var current := communities[node_id]
			var degree := degrees[node_id]
			if degree <= EPSILON:
				continue
			totals[current] -= degree
			var weight_by_community := {}
			for neighbor_value in adjacency[node_id]:
				var neighbor := int(neighbor_value)
				if neighbor == node_id:
					continue
				var community := communities[neighbor]
				weight_by_community[community] = float(
					weight_by_community.get(community, 0.0)
				) + float(adjacency[node_id][neighbor])
			var candidates: Array[int] = [current]
			for community_value in weight_by_community:
				var community := int(community_value)
				if not candidates.has(community):
					candidates.append(community)
			candidates.sort()
			var best := current
			var best_gain := _move_gain(
				current, degree, totals, weight_by_community,
				total_degree, resolution
			)
			for candidate in candidates:
				var gain := _move_gain(
					candidate, degree, totals, weight_by_community,
					total_degree, resolution
				)
				if (
					gain > best_gain + EPSILON
					or (
						is_equal_approx(gain, best_gain)
						and candidate < best
					)
				):
					best = candidate
					best_gain = gain
			communities[node_id] = best
			totals[best] += degree
			moved = moved or best != current
		if not moved:
			break
	return communities


static func _move_gain(
	community: int,
	degree: float,
	totals: PackedFloat64Array,
	weight_by_community: Dictionary,
	total_degree: float,
	resolution: float
) -> float:
	return (
		float(weight_by_community.get(community, 0.0))
		- resolution * degree * totals[community] / total_degree
	)


static func _split_disconnected_communities(
	adjacency: Array[Dictionary],
	partition: PackedInt32Array,
	groups: Array[Array]
) -> PackedInt32Array:
	var members_by_community := {}
	for node_id in range(partition.size()):
		var community := partition[node_id]
		if not members_by_community.has(community):
			members_by_community[community] = [] as Array[int]
		(members_by_community[community] as Array[int]).append(node_id)
	var community_ids: Array[int] = []
	community_ids.assign(members_by_community.keys())
	community_ids.sort()
	var refined := PackedInt32Array()
	refined.resize(partition.size())
	refined.fill(-1)
	var next_community := 0
	for community in community_ids:
		var unseen := {}
		for node_id in members_by_community[community]:
			unseen[int(node_id)] = true
		while not unseen.is_empty():
			var starts: Array[int] = []
			starts.assign(unseen.keys())
			starts.sort_custom(func(a: int, b: int) -> bool:
				return _group_minimum(groups[a]) < _group_minimum(groups[b])
			)
			var queue: Array[int] = [starts[0]]
			unseen.erase(starts[0])
			var cursor := 0
			while cursor < queue.size():
				var node_id := queue[cursor]
				cursor += 1
				refined[node_id] = next_community
				var neighbors: Array[int] = []
				for neighbor_value in adjacency[node_id]:
					var neighbor := int(neighbor_value)
					if (
						neighbor != node_id
						and partition[neighbor] == community
						and unseen.has(neighbor)
					):
						neighbors.append(neighbor)
				neighbors.sort()
				for neighbor in neighbors:
					unseen.erase(neighbor)
					queue.append(neighbor)
			next_community += 1
	return refined


static func _normalize_partition(
	partition: PackedInt32Array,
	groups: Array[Array]
) -> PackedInt32Array:
	var minimum_by_community := {}
	for node_id in range(partition.size()):
		var community := partition[node_id]
		var minimum := _group_minimum(groups[node_id])
		minimum_by_community[community] = mini(
			int(minimum_by_community.get(community, minimum)), minimum
		)
	var community_ids: Array[int] = []
	community_ids.assign(minimum_by_community.keys())
	community_ids.sort_custom(func(a: int, b: int) -> bool:
		return int(minimum_by_community[a]) < int(minimum_by_community[b])
	)
	var remap := {}
	for normalized_id in range(community_ids.size()):
		remap[community_ids[normalized_id]] = normalized_id
	var result := PackedInt32Array()
	result.resize(partition.size())
	for node_id in range(partition.size()):
		result[node_id] = int(remap[partition[node_id]])
	return result


static func _aggregate_graph(
	adjacency: Array[Dictionary],
	groups: Array[Array],
	partition: PackedInt32Array
) -> Dictionary:
	var community_count := _partition_count(partition)
	var aggregated: Array[Dictionary] = []
	var aggregated_groups: Array[Array] = []
	aggregated.resize(community_count)
	aggregated_groups.resize(community_count)
	for community in range(community_count):
		aggregated[community] = {}
		aggregated_groups[community] = []
	for node_id in range(adjacency.size()):
		var community_a := partition[node_id]
		aggregated_groups[community_a].append_array(groups[node_id])
		for neighbor_value in adjacency[node_id]:
			var neighbor := int(neighbor_value)
			var community_b := partition[neighbor]
			aggregated[community_a][community_b] = float(
				aggregated[community_a].get(community_b, 0.0)
			) + float(adjacency[node_id][neighbor])
	for group in aggregated_groups:
		group.sort()
	return {"adjacency": aggregated, "groups": aggregated_groups}


static func _brandes_betweenness(
	adjacency: Array[Dictionary],
	active: Array[int],
	city_count: int
) -> PackedFloat32Array:
	var centrality := PackedFloat64Array()
	centrality.resize(maxi(city_count, 0))
	for source in active:
		var predecessors: Array[Array] = []
		predecessors.resize(city_count)
		for city_id in range(city_count):
			predecessors[city_id] = []
		var distance := PackedInt32Array()
		var paths := PackedFloat64Array()
		distance.resize(city_count)
		distance.fill(-1)
		paths.resize(city_count)
		distance[source] = 0
		paths[source] = 1.0
		var queue: Array[int] = [source]
		var stack: Array[int] = []
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			stack.append(current)
			var neighbors: Array[int] = []
			for neighbor_value in adjacency[current]:
				var neighbor := int(neighbor_value)
				if neighbor != current:
					neighbors.append(neighbor)
			neighbors.sort()
			for neighbor in neighbors:
				if distance[neighbor] < 0:
					distance[neighbor] = distance[current] + 1
					queue.append(neighbor)
				if distance[neighbor] == distance[current] + 1:
					paths[neighbor] += paths[current]
					predecessors[neighbor].append(current)
		var dependency := PackedFloat64Array()
		dependency.resize(city_count)
		while not stack.is_empty():
			var target := int(stack.pop_back())
			if paths[target] > EPSILON:
				for predecessor_value in predecessors[target]:
					var predecessor := int(predecessor_value)
					dependency[predecessor] += (
						paths[predecessor] / paths[target]
						* (1.0 + dependency[target])
					)
			if target != source:
				centrality[target] += dependency[target]
	var normalization := (
		1.0 / float((active.size() - 1) * (active.size() - 2))
		if active.size() > 2
		else 0.0
	)
	var result := PackedFloat32Array()
	result.resize(maxi(city_count, 0))
	for city_id in active:
		result[city_id] = float(centrality[city_id]) * normalization
	return result


static func _key_cities(
	active: Array[int],
	betweenness: PackedFloat32Array
) -> PackedInt32Array:
	var candidates: Array[int] = []
	for city_id in active:
		if betweenness[city_id] > EPSILON:
			candidates.append(city_id)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		if not is_equal_approx(betweenness[a], betweenness[b]):
			return betweenness[a] > betweenness[b]
		return a < b
	)
	if candidates.is_empty():
		return PackedInt32Array()
	var requested := maxi(int(ceil(float(active.size()) * KEY_CITY_SHARE)), 1)
	var cutoff := betweenness[candidates[mini(requested, candidates.size()) - 1]]
	var result := PackedInt32Array()
	for city_id in candidates:
		if betweenness[city_id] + EPSILON < cutoff:
			break
		result.append(city_id)
	return result


static func _partition_count(partition: PackedInt32Array) -> int:
	var count := 0
	for community in partition:
		count = maxi(count, community + 1)
	return count


static func _group_minimum(group: Array) -> int:
	var result := 2147483647
	for value in group:
		result = mini(result, int(value))
	return result


static func _normalize_result_ids(
	region_ids: PackedInt32Array,
	active: Array[int]
) -> PackedInt32Array:
	var minimum_by_region := {}
	for city_id in active:
		var region_id := region_ids[city_id]
		minimum_by_region[region_id] = mini(
			int(minimum_by_region.get(region_id, city_id)), city_id
		)
	var old_ids: Array[int] = []
	old_ids.assign(minimum_by_region.keys())
	old_ids.sort_custom(func(a: int, b: int) -> bool:
		return int(minimum_by_region[a]) < int(minimum_by_region[b])
	)
	var remap := {}
	for new_id in range(old_ids.size()):
		remap[old_ids[new_id]] = new_id
	for city_id in active:
		region_ids[city_id] = int(remap[region_ids[city_id]])
	return region_ids
