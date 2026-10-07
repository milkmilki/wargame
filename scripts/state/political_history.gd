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
	RegionalStrategy.invalidate_geometry(_view_state)
	_view_state.regional_strategy_revision = int(snapshot["regional_strategy_revision"])
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
	_view_state.war_relation_ids = (
		(snapshot["war_relation_ids"] as Dictionary).duplicate(true)
	)
	_view_state.next_war_id = int(snapshot["next_war_id"])
	_view_state.vassal_conflicts = snapshot.get("vassal_conflicts", {}).duplicate(true)
	_view_state.suzerainty = (
		(snapshot["suzerainty"] as Dictionary).duplicate(true)
	)
	_view_state.suzerainty_low_cohesion_since_day = (
		(snapshot.get(
			"suzerainty_low_cohesion_since_day", {}
		) as Dictionary).duplicate(true)
	)
	_view_state.rebellions = (
		(snapshot["rebellions"] as Dictionary).duplicate(true)
	)
	var chronicle_count := int(snapshot.get("chronicle_event_count", 0))
	var chronicle_source: Array = live_state.chronicle_events
	_view_state.chronicle_events = chronicle_source.slice(0, mini(chronicle_count, chronicle_source.size())).duplicate(true)
	_view_state.war_chronicle_contexts = (snapshot.get("war_chronicle_contexts", {}) as Dictionary).duplicate(true)
	_view_state.chronicle_pending_war_ids = (snapshot.get("chronicle_pending_war_ids", []) as Array).duplicate()
	_view_state.recognized_city_owners = (
		(snapshot["recognized_city_owners"] as PackedInt32Array).duplicate()
	)
	_view_state.winner = int(snapshot["winner"])
	_view_state.family_revision = int(snapshot["family_revision"])
	_view_state.next_family_person_id = int(snapshot["next_family_person_id"])
	_view_state.next_family_tree_id = int(snapshot["next_family_tree_id"])
	_view_state.remove_meta("royal_census")
	_view_state.family_trees = (snapshot["family_trees"] as Dictionary).duplicate(true)
	_view_state.set_meta("historical_prince_reports", (snapshot["prince_reports"] as Dictionary).duplicate(true))

	var owners: PackedInt32Array = snapshot["city_owners"]
	for city_id in range(_view_state.cities.size()):
		_view_state.cities[city_id].owner_nation = owners[city_id]

	var alive: PackedByteArray = snapshot["nation_alive"]
	var strategic_region_anchors: PackedInt32Array = snapshot["strategic_region_anchors"]
	var court_rates: PackedFloat32Array = snapshot["court_expense_rates"]
	var court_due: PackedInt32Array = snapshot["court_expense_due"]
	var court_paid: PackedInt32Array = snapshot["court_expense_paid"]
	var payment_ratios: PackedFloat32Array = snapshot["military_payment_ratios"]
	for nation_id in range(_view_state.nations.size()):
		_view_state.nations[nation_id].alive = (
			nation_id < alive.size() and alive[nation_id] != 0
		)
		# Later-founded nations retain stable ID slots but have no historical objective.
		_view_state.nations[nation_id].strategic_region_anchor_city_id = (
			strategic_region_anchors[nation_id]
			if nation_id < strategic_region_anchors.size() else -1
		)
		var nation := _view_state.nations[nation_id]
		var political: Dictionary = (snapshot["nation_politics"] as Dictionary).get(nation_id, {})
		if political.is_empty():
			nation.state_level = 0
			nation.empire_founder_person_id = -1
			nation.empire_recognized_day = -1
			nation.royal_titles_initialized = false
			nation.royal_generation = 0
			nation.absorbed_into_nation_id = -1
			nation.last_royal_expense_basis_points = 0
			nation.last_royal_title_counts = [0, 0, 0, 0]
			nation.prince_person_ids.clear()
			nation.crown_prince_person_id = -1
			nation.ruler_person_id = -1
			nation.family_tree_id = -1
			nation.capital_city_id = -1
		for key in political:
			var value = political[key]
			nation.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
		nation.military_payment_ratio = payment_ratios[nation_id] if nation_id < payment_ratios.size() else 1.0
		nation.last_court_expense_rate = court_rates[nation_id] if nation_id < court_rates.size() else 0.0
		nation.last_court_expense_due = court_due[nation_id] if nation_id < court_due.size() else 0
		nation.last_court_expense_paid = court_paid[nation_id] if nation_id < court_paid.size() else 0
	return _view_state


func _create_view_state(live_state: GameState) -> GameState:
	var view := GameState.new()
	view.world_seed = live_state.world_seed
	view.uses_heightmap = live_state.uses_heightmap
	view.map_source_manifest = live_state.map_source_manifest
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
	view.region_ids = live_state.region_ids.duplicate()
	view.region_analysis_revision = live_state.region_analysis_revision
	view.administrative_center_by_city = live_state.administrative_center_by_city.duplicate()
	view.administrative_center_city_ids = live_state.administrative_center_city_ids.duplicate()
	view.administrative_region_ids = live_state.administrative_region_ids.duplicate()
	view.administrative_region_revision = live_state.administrative_region_revision
	view.node_betweenness = live_state.node_betweenness.duplicate()
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
	view.trade_routes = [] as Array[Dictionary]
	return view


func _capture(game_state: GameState) -> void:
	var owners := PackedInt32Array()
	owners.resize(game_state.cities.size())
	for city_id in range(game_state.cities.size()):
		owners[city_id] = game_state.cities[city_id].owner_nation
	var alive := PackedByteArray()
	var strategic_region_anchors := PackedInt32Array()
	var court_rates := PackedFloat32Array()
	var court_due := PackedInt32Array()
	var court_paid := PackedInt32Array()
	var payment_ratios := PackedFloat32Array()
	var nation_politics := {}
	var prince_reports := {}
	var military := PrincePolitics.military_index(game_state)
	alive.resize(game_state.nations.size())
	for nation_id in range(game_state.nations.size()):
		alive[nation_id] = 1 if game_state.nations[nation_id].alive else 0
		strategic_region_anchors.append(game_state.nations[nation_id].strategic_region_anchor_city_id)
		court_rates.append(game_state.nations[nation_id].last_court_expense_rate)
		court_due.append(game_state.nations[nation_id].last_court_expense_due)
		court_paid.append(game_state.nations[nation_id].last_court_expense_paid)
		payment_ratios.append(game_state.nations[nation_id].military_payment_ratio)
		var nation := game_state.nations[nation_id]
		var political := {}
		for key in ["name", "short_name", "name_kind", "vassal_single_char", "vassal_title_base", "ruler_name", "ruler_archetype", "ruler_traits", "ruler_person_id", "ruler_revision", "ruler_started_day", "family_tree_id", "prince_person_ids", "crown_prince_person_id", "succession_competition_closed", "succession_identity", "capital_city_id", "state_level", "empire_founder_person_id", "empire_recognized_day", "royal_titles_initialized", "royal_generation", "absorbed_into_nation_id", "last_royal_expense_basis_points", "last_royal_title_counts"]:
			var value = nation.get(key)
			political[key] = value.duplicate(true) if value is Array or value is Dictionary else value
		nation_politics[nation_id] = political
		prince_reports[nation_id] = PrincePolitics.report(game_state, nation_id, military.get(nation_id, {}))
	_snapshots.append({
		"day": game_state.day,
		"family_trees": game_state.family_trees.duplicate(true),
		"family_revision": game_state.family_revision,
		"next_family_person_id": game_state.next_family_person_id,
		"next_family_tree_id": game_state.next_family_tree_id,
		"nation_politics": nation_politics,
		"prince_reports": prince_reports,
		"month": game_state.month,
		"ownership_revision": game_state.ownership_revision,
		"diplomacy_revision": game_state.diplomacy_revision,
		"regional_strategy_revision": game_state.regional_strategy_revision,
		"strategic_region_anchors": strategic_region_anchors,
		"court_expense_rates": court_rates,
		"court_expense_due": court_due,
		"court_expense_paid": court_paid,
		"military_payment_ratios": payment_ratios,
		"city_owners": owners,
		"recognized_city_owners": game_state.recognized_city_owners.duplicate(),
		"nation_alive": alive,
		"diplomatic_relations": game_state.diplomatic_relations.duplicate(true),
		"diplomatic_since_day": game_state.diplomatic_since_day.duplicate(true),
		"truce_until_day": game_state.truce_until_day.duplicate(true),
		"war_objectives": game_state.war_objectives.duplicate(true),
		"war_relation_ids": game_state.war_relation_ids.duplicate(true),
		"vassal_conflicts": game_state.vassal_conflicts.duplicate(true),
		"next_war_id": game_state.next_war_id,
		"suzerainty": game_state.suzerainty.duplicate(true),
		"suzerainty_low_cohesion_since_day": (
			game_state.suzerainty_low_cohesion_since_day.duplicate(true)
		),
		"rebellions": game_state.rebellions.duplicate(true),
		# 编年史是只追加事实；快照只保存前缀长度，避免每月复制完整历史。
		"chronicle_event_count": game_state.chronicle_events.size(),
		"war_chronicle_contexts": game_state.war_chronicle_contexts.duplicate(true),
		"chronicle_pending_war_ids": game_state.chronicle_pending_war_ids.duplicate(),
		"winner": game_state.winner,
	})


static func _copy_script_object(source: Object) -> Object:
	var copy: Object = source.get_script().new()
	for property in source.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := StringName(property["name"])
		var value = source.get(name)
		copy.set(name, value.duplicate(true) if value is Array or value is Dictionary else value)
	return copy
