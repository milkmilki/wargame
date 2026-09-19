extends SceneTree


const WORLD_SEED := 96001
const REQUESTED_NATIONS := 48
const LAND_CITY_COUNT := 48


func _init() -> void:
	var state := GameState.new()
	state.generate_world(
		WORLD_SEED, REQUESTED_NATIONS, LAND_CITY_COUNT
	)
	var repeated := GameState.new()
	repeated.generate_world(
		WORLD_SEED, REQUESTED_NATIONS, LAND_CITY_COUNT
	)
	var valid := (
		state.nations.size() > 0
		and state.nations.size() <= state.administrative_region_count
		and state.nations.size() < REQUESTED_NATIONS
		and state.nations.size() == repeated.nations.size()
		and state.administrative_center_city_ids
			== repeated.administrative_center_city_ids
	)
	var center_owners := PackedInt32Array()
	for center_id in state.administrative_center_city_ids:
		center_owners.append(state.cities[center_id].owner_nation)
	var repeated_center_owners := PackedInt32Array()
	for center_id in repeated.administrative_center_city_ids:
		repeated_center_owners.append(
			repeated.cities[center_id].owner_nation
		)
	valid = valid and center_owners == repeated_center_owners
	for nation_id in range(state.nations.size()):
		valid = (
			valid
			and state.nations[nation_id].id == nation_id
			and _nation_owns_center(state, nation_id)
			and not state.land_cities_of(nation_id).is_empty()
			and state.nations[nation_id].capital_city_id >= 0
			and _nation_is_connected(state, nation_id)
		)
	for city in state.land_cities():
		if not city.politically_active:
			continue
		var center_id := state.administrative_center_of(city.id)
		valid = (
			valid
			and center_id >= 0
			and city.owner_nation
				== state.cities[center_id].owner_nation
		)
	valid = valid and state.territory_structure_valid()
	var ordinary := GameState.new()
	ordinary.generate_world(WORLD_SEED + 1, 4, LAND_CITY_COUNT)
	var ordinary_counts := PackedInt32Array()
	valid = (
		valid
		and ordinary.nations.size() == 4
		and ordinary.territory_structure_valid()
		and _regions_follow_centers(ordinary)
	)
	for nation_id in range(ordinary.nations.size()):
		var owned_count := ordinary.land_cities_of(nation_id).size()
		ordinary_counts.append(owned_count)
		var average_count := (
			float(LAND_CITY_COUNT) / float(ordinary.nations.size())
		)
		valid = (
			valid
			and _nation_owns_center(ordinary, nation_id)
			and _nation_is_connected(ordinary, nation_id)
			and float(owned_count) >= average_count * 0.5
			and float(owned_count) <= average_count * 1.6
		)
	if valid:
		print(
			"INITIAL_NATION_ADMIN_CENTER_OK requested=%d actual=%d regions=%d"
			% [
				REQUESTED_NATIONS,
				state.nations.size(),
				state.administrative_region_count,
			]
		)
		quit(0)
		return
	push_error(
		"INITIAL_NATION_ADMIN_CENTER_FAILED requested=%d actual=%d regions=%d owners=%s ordinary=%s"
		% [
			REQUESTED_NATIONS,
			state.nations.size(),
			state.administrative_region_count,
			str(center_owners),
			str(ordinary_counts),
		]
	)
	quit(1)


func _nation_owns_center(state: GameState, nation_id: int) -> bool:
	for center_id in state.administrative_center_city_ids:
		if state.cities[center_id].owner_nation == nation_id:
			return true
	return false


func _regions_follow_centers(state: GameState) -> bool:
	for city in state.land_cities():
		if not city.politically_active:
			continue
		var center_id := state.administrative_center_of(city.id)
		if (
			center_id < 0
			or city.owner_nation
				!= state.cities[center_id].owner_nation
		):
			return false
	return true


func _nation_is_connected(state: GameState, nation_id: int) -> bool:
	var owned := state.cities_of(nation_id)
	if owned.is_empty():
		return false
	var visited := {owned[0].id: true}
	var queue: Array[int] = [owned[0].id]
	var cursor := 0
	while cursor < queue.size():
		var city_id := queue[cursor]
		cursor += 1
		for neighbor in state.neighbors(city_id):
			var edge := state.edge_of(city_id, neighbor)
			if (
				visited.has(neighbor)
				or state.cities[neighbor].owner_nation != nation_id
				or edge == null
				or edge.max_manpower <= 0
			):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return visited.size() == owned.size()
