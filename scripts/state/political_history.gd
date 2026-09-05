class_name PoliticalHistory
extends RefCounted
## 内存中的只读政治史。只保存重建版图和外交视图所需的数据。

const DEFAULT_INTERVAL_DAYS: int = Simulation.DAYS_PER_MONTH

var _interval_days: int = DEFAULT_INTERVAL_DAYS
var _snapshots: Array[Dictionary] = []
var _view_state: GameState
var _view_source_instance_id: int = 0
var _view_naming_revision: int = -1


func reset(game_state: GameState, interval_days: int = DEFAULT_INTERVAL_DAYS) -> void:
	_interval_days = maxi(interval_days, 1)
	_snapshots.clear()
	_view_state = null
	_view_source_instance_id = 0
	_view_naming_revision = -1
	_capture(game_state)


func maybe_capture(game_state: GameState) -> bool:
	if game_state == null or game_state.day % _interval_days != 0:
		return false
	if not _snapshots.is_empty() and snapshot_day(_snapshots.size() - 1) == game_state.day:
		return false
	_capture(game_state)
	return true


func snapshot_count() -> int:
	return _snapshots.size()


func snapshot_day(index: int) -> int:
	if index < 0 or index >= _snapshots.size():
		return -1
	return int(_snapshots[index].get("day", -1))


func snapshot_days() -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(_snapshots.size())
	for index in range(_snapshots.size()):
		result[index] = snapshot_day(index)
	return result


func build_view_state(live_state: GameState, index: int) -> GameState:
	if live_state == null or index < 0 or index >= _snapshots.size():
		return null
	if (
		_view_state == null
		or _view_source_instance_id != live_state.get_instance_id()
		or _view_naming_revision != live_state.naming_revision
		or _view_state.cities.size() != live_state.cities.size()
		or _view_state.nations.size() != live_state.nations.size()
	):
		_view_state = _create_view_state(live_state)
		_view_source_instance_id = live_state.get_instance_id()
		_view_naming_revision = live_state.naming_revision
	var snapshot: Dictionary = _snapshots[index]
	_view_state.day = int(snapshot["day"])
	_view_state.month = int(snapshot["month"])
	_view_state.ownership_revision = int(snapshot["ownership_revision"])
	_view_state.diplomacy_revision = int(snapshot["diplomacy_revision"])
	_view_state.diplomatic_relations = (
		(snapshot["diplomatic_relations"] as Dictionary).duplicate(true)
	)
	_view_state.diplomatic_since_day = (
		(snapshot["diplomatic_since_day"] as Dictionary).duplicate(true)
	)
	_view_state.truce_until_day = (
		(snapshot["truce_until_day"] as Dictionary).duplicate(true)
	)
	_view_state.war_objectives = (
		(snapshot["war_objectives"] as Dictionary).duplicate(true)
	)
	_view_state.suzerainty = (
		(snapshot["suzerainty"] as Dictionary).duplicate(true)
	)
	_view_state.rebellions = (
		(snapshot["rebellions"] as Dictionary).duplicate(true)
	)
	_view_state.recognized_city_owners = (
		(snapshot["recognized_city_owners"] as PackedInt32Array).duplicate()
	)
	_view_state.winner = int(snapshot["winner"])

	var owners: PackedInt32Array = snapshot["city_owners"]
	for city_id in range(_view_state.cities.size()):
		_view_state.cities[city_id].owner_nation = owners[city_id]

	var alive: PackedByteArray = snapshot["nation_alive"]
	for nation_id in range(_view_state.nations.size()):
		_view_state.nations[nation_id].alive = (
			nation_id < alive.size() and alive[nation_id] != 0
		)
	return _view_state


func _create_view_state(live_state: GameState) -> GameState:
	var view := GameState.new()
	view.world_seed = live_state.world_seed
	view.uses_heightmap = live_state.uses_heightmap
	view.map_aspect_ratio = live_state.map_aspect_ratio
	view.map_source_region_normalized = live_state.map_source_region_normalized
	view.city_generation_mask_path = live_state.city_generation_mask_path
	view.political_mask_path = live_state.political_mask_path
	view.city_density_settings = live_state.city_density_settings.duplicate(true)
	view.province_map_size = live_state.province_map_size
	view.province_ids = live_state.province_ids
	view.river_features = (
		live_state.river_features.duplicate(true)
		if not live_state.river_features.is_empty()
		else MapFeatureContract.from_legacy_river_paths(
			live_state.river_paths
		)
	)
	view.river_paths = MapFeatureContract.authoritative_paths(
		view.river_features
	)
	view.edges = live_state.edges
	view.adjacency = live_state.adjacency
	view.edge_lookup = live_state.edge_lookup
	view.road_network_revision = live_state.road_network_revision
	view.naming_revision = live_state.naming_revision
	var view_cities: Array[City] = []
	for source_city in live_state.cities:
		view_cities.append(_copy_script_object(source_city) as City)
	view.cities = view_cities
	var view_nations: Array[Nation] = []
	for source_nation in live_state.nations:
		view_nations.append(_copy_script_object(source_nation) as Nation)
	view.nations = view_nations
	# 历史政治视图明确不携带任何实时军事或经济动画集合。
	view.armies = [] as Array[Army]
	view.battles = [] as Array[Battle]
	view.campaign_visual_events = [] as Array[Dictionary]
	view.trade_routes = [] as Array[Dictionary]
	return view


func _capture(game_state: GameState) -> void:
	var owners := PackedInt32Array()
	owners.resize(game_state.cities.size())
	for city_id in range(game_state.cities.size()):
		owners[city_id] = game_state.cities[city_id].owner_nation
	var alive := PackedByteArray()
	alive.resize(game_state.nations.size())
	for nation_id in range(game_state.nations.size()):
		alive[nation_id] = 1 if game_state.nations[nation_id].alive else 0
	_snapshots.append({
		"day": game_state.day,
		"month": game_state.month,
		"ownership_revision": game_state.ownership_revision,
		"diplomacy_revision": game_state.diplomacy_revision,
		"city_owners": owners,
		"recognized_city_owners": game_state.recognized_city_owners.duplicate(),
		"nation_alive": alive,
		"diplomatic_relations": game_state.diplomatic_relations.duplicate(true),
		"diplomatic_since_day": game_state.diplomatic_since_day.duplicate(true),
		"truce_until_day": game_state.truce_until_day.duplicate(true),
		"war_objectives": game_state.war_objectives.duplicate(true),
		"suzerainty": game_state.suzerainty.duplicate(true),
		"rebellions": game_state.rebellions.duplicate(true),
		"winner": game_state.winner,
	})


static func _copy_script_object(source: Object) -> Object:
	var copy: Object = source.get_script().new()
	for property in source.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := StringName(property["name"])
		copy.set(name, source.get(name))
	return copy
