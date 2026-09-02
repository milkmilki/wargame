class_name MapHitTesting
extends RefCounted
## Deterministic map picking shared by input handling and renderer wrappers.


static func pick_city_at_pixel(
	state: GameState,
	point: Vector2,
	origin: Vector2,
	map_size: Vector2,
	radius: float
) -> int:
	var best_city := -1
	var best_distance_sq := radius * radius
	for city in state.cities:
		var center := origin + city.map_position * map_size
		var distance_sq := point.distance_squared_to(center)
		if (
			distance_sq < best_distance_sq
			or (
				is_equal_approx(distance_sq, best_distance_sq)
				and (best_city < 0 or city.id < best_city)
			)
		):
			best_city = city.id
			best_distance_sq = distance_sq
	return best_city


static func pick_edge_at_pixel(
	state: GameState,
	point: Vector2,
	origin: Vector2,
	map_size: Vector2,
	tolerance: float
) -> Edge:
	var best: Edge = null
	var best_distance := tolerance
	for edge in state.edges:
		if not is_edge_visible(edge):
			continue
		var distance := INF
		var path := edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		)
		for index in range(path.size() - 1):
			distance = minf(distance, point_to_segment_distance(
				point,
				origin + path[index] * map_size,
				origin + path[index + 1] * map_size
			))
		if (
			distance < best_distance
			or (
				is_equal_approx(distance, best_distance)
				and (
					best == null
					or GameState.edge_key(edge.city_a, edge.city_b)
						< GameState.edge_key(best.city_a, best.city_b)
				)
			)
		):
			best = edge
			best_distance = distance
	return best


static func point_to_segment_distance(
	point: Vector2,
	from: Vector2,
	to: Vector2
) -> float:
	var delta := to - from
	if delta.length_squared() <= 0.000001:
		return point.distance_to(from)
	var t := clampf(
		(point - from).dot(delta) / delta.length_squared(),
		0.0,
		1.0
	)
	return point.distance_to(from + delta * t)


static func is_edge_visible(edge: Edge) -> bool:
	return edge != null and edge.max_manpower > 0
