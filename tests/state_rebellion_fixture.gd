extends RefCounted


## A one-city state isolates resource/military transactions from map partitioning.
static func isolate_city_as_state(state: GameState, city_id: int) -> void:
	var by_city := state.administrative_center_by_city.duplicate()
	var retained_center := state.administrative_center_of(
		state.nations[state.cities[city_id].owner_nation].capital_city_id
	)
	for other_id in range(by_city.size()):
		if other_id != city_id and by_city[other_id] == city_id:
			by_city[other_id] = retained_center
	by_city[city_id] = city_id
	state.administrative_center_by_city = by_city
	var centers: Array[int] = []
	for center_id in by_city:
		if center_id >= 0 and not centers.has(center_id):
			centers.append(center_id)
	centers.sort()
	state.administrative_center_city_ids = PackedInt32Array(centers)
	state.administrative_region_count = centers.size()
	state.administrative_region_ids.resize(by_city.size())
	for other_id in range(by_city.size()):
		state.administrative_region_ids[other_id] = centers.find(by_city[other_id])
	state.administrative_region_revision += 1
