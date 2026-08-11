class_name AiWorldView
extends RefCounted
## 单个国家的只读 AI 世界视图。当前使用全知信息；未来战争迷雾只需替换本层筛选。

var state: GameState
var nation_id: int
var day: int
var capital_city_id: int
var strategic_planning_enabled: bool = true
var adaptive_garrison_enabled: bool = true
var supply_corridor_defense_enabled: bool = true
var executable_attack_paths_enabled: bool = true
var legacy_id_personality_enabled: bool = false
var friendly_cities: Array[City] = []
var enemy_cities: Array[City] = []
var allied_cities: Array[City] = []
var neutral_cities: Array[City] = []
var friendly_armies: Array[Army] = []
var enemy_armies: Array[Army] = []
var allied_armies: Array[Army] = []
var warehouses: Array[City] = []
var armies_by_nation: Dictionary = {}
var armies_by_city: Dictionary = {}
var armies_by_incident_city: Dictionary = {}
var army_power_by_nation: Dictionary = {}
var friendly_stationed_power_by_city: Dictionary = {}
var enemy_armies_by_city: Dictionary = {}
var enemy_armies_by_edge: Dictionary = {}
var _path_field_cache: Dictionary = {}
var _supply_city_cache: Dictionary = {}
var _supply_network_cache: Dictionary = {}


## 同一 AI 决策 tick 的所有国家共享基础军队索引。索引只保存 Army 引用，
## 国家关系相关的敌我分类仍在各自视图中完成。
static func build_army_index(game_state: GameState) -> Dictionary:
	var armies_by_nation := {}
	var armies_by_city := {}
	var armies_by_incident_city := {}
	var army_power_by_nation := {}
	var stationed_power_by_nation := {}
	for nation in game_state.nations:
		armies_by_nation[nation.id] = [] as Array[Army]
		army_power_by_nation[nation.id] = 0.0
		stationed_power_by_nation[nation.id] = {}
	for army in game_state.armies:
		if army.size <= 0:
			continue
		(
			armies_by_nation[army.owner_nation]
				as Array[Army]
		).append(army)
		army_power_by_nation[army.owner_nation] = (
			float(army_power_by_nation[army.owner_nation])
			+ ArmyPower.effective(army)
		)
		if army.on_edge and army.move_to >= 0:
			var incident_city_ids: Array[int] = [
				army.move_from
			]
			if army.move_to != army.move_from:
				incident_city_ids.append(army.move_to)
			for city_id in incident_city_ids:
				if not armies_by_incident_city.has(city_id):
					armies_by_incident_city[city_id] = (
						[] as Array[Army]
					)
				(
					armies_by_incident_city[city_id]
						as Array[Army]
				).append(army)
		elif army.location_city >= 0:
			if not armies_by_city.has(army.location_city):
				armies_by_city[army.location_city] = (
					[] as Array[Army]
				)
			(
				armies_by_city[army.location_city]
					as Array[Army]
			).append(army)
			if not armies_by_incident_city.has(
				army.location_city
			):
				armies_by_incident_city[army.location_city] = (
					[] as Array[Army]
				)
			(
				armies_by_incident_city[army.location_city]
					as Array[Army]
			).append(army)
			if army.state in [
				Army.State.IDLE,
				Army.State.RECOVERING,
			]:
				var stationed: Dictionary = (
					stationed_power_by_nation[
						army.owner_nation
					]
				)
				stationed[army.location_city] = (
					float(
						stationed.get(
							army.location_city,
							0.0
						)
					)
					+ ArmyPower.effective(army)
				)
	return {
		"armies_by_nation": armies_by_nation,
		"armies_by_city": armies_by_city,
		"armies_by_incident_city": armies_by_incident_city,
		"army_power_by_nation": army_power_by_nation,
		"stationed_power_by_nation":
			stationed_power_by_nation,
	}


static func build(
	game_state: GameState,
	owner_nation: int,
	shared_path_cache: Dictionary = {},
	shared_supply_network_cache: Dictionary = {},
	shared_city_partition_cache: Dictionary = {},
	shared_army_index: Dictionary = {}
) -> AiWorldView:
	var view := AiWorldView.new()
	view.state = game_state
	view.nation_id = owner_nation
	view.day = game_state.day
	view.capital_city_id = game_state.nations[owner_nation].capital_city_id
	view._path_field_cache = shared_path_cache
	view._supply_network_cache = shared_supply_network_cache
	view.warehouses = game_state.warehouse_cities_of(owner_nation)
	var city_partition_key := "%d:%d:%d" % [
		owner_nation,
		game_state.ownership_revision,
		game_state.diplomacy_revision,
	]
	if shared_city_partition_cache.has(city_partition_key):
		var cached: Dictionary = shared_city_partition_cache[
			city_partition_key
		]
		view.friendly_cities = (
			cached["friendly"] as Array[City]
		).duplicate()
		view.enemy_cities = (
			cached["enemy"] as Array[City]
		).duplicate()
		view.allied_cities = (
			cached["allied"] as Array[City]
		).duplicate()
		view.neutral_cities = (
			cached["neutral"] as Array[City]
		).duplicate()
	else:
		for city in game_state.cities:
			if city.owner_nation == owner_nation:
				view.friendly_cities.append(city)
			elif game_state.is_enemy(
				owner_nation,
				city.owner_nation
			):
				view.enemy_cities.append(city)
			elif game_state.is_allied(
				owner_nation,
				city.owner_nation
			):
				view.allied_cities.append(city)
			else:
				view.neutral_cities.append(city)
		EquivariantOrder.sort_cities(
			view.friendly_cities,
			game_state,
			owner_nation
		)
		EquivariantOrder.sort_cities(
			view.enemy_cities,
			game_state,
			owner_nation
		)
		EquivariantOrder.sort_cities(
			view.allied_cities,
			game_state,
			owner_nation
		)
		EquivariantOrder.sort_cities(
			view.neutral_cities,
			game_state,
			owner_nation
		)
		shared_city_partition_cache[city_partition_key] = {
			"friendly": view.friendly_cities.duplicate(),
			"enemy": view.enemy_cities.duplicate(),
			"allied": view.allied_cities.duplicate(),
			"neutral": view.neutral_cities.duplicate(),
		}
	var army_index := (
		shared_army_index
		if not shared_army_index.is_empty()
		else build_army_index(game_state)
	)
	view.armies_by_nation = army_index["armies_by_nation"]
	view.armies_by_city = army_index["armies_by_city"]
	view.armies_by_incident_city = army_index[
		"armies_by_incident_city"
	]
	view.army_power_by_nation = army_index[
		"army_power_by_nation"
	]
	var armies_by_nation: Dictionary = view.armies_by_nation
	view.friendly_armies = (
		armies_by_nation.get(
			owner_nation,
			[] as Array[Army]
		) as Array[Army]
	).duplicate()
	view.friendly_stationed_power_by_city = (
		army_index["stationed_power_by_nation"].get(
			owner_nation,
			{}
		) as Dictionary
	).duplicate()
	for other in game_state.nations:
		if other.id == owner_nation:
			continue
		var other_armies: Array[Army] = (
			armies_by_nation.get(
				other.id,
				[] as Array[Army]
			) as Array[Army]
		)
		if game_state.is_enemy(owner_nation, other.id):
			view.enemy_armies.append_array(other_armies)
		elif game_state.is_allied(owner_nation, other.id):
			view.allied_armies.append_array(other_armies)
	# AI 军队迭代顺序必须随势力镜像一起变换，不能读取创建顺序 id。
	EquivariantOrder.sort_armies(
		view.friendly_armies,
		game_state,
		owner_nation
	)
	EquivariantOrder.sort_armies(
		view.enemy_armies,
		game_state,
		owner_nation
	)
	for enemy in view.enemy_armies:
		if enemy.on_edge and enemy.move_to != -1:
			var edge_key := GameState.edge_key(
				enemy.move_from,
				enemy.move_to
			)
			if not view.enemy_armies_by_edge.has(edge_key):
				view.enemy_armies_by_edge[edge_key] = (
					[] as Array[Army]
				)
			(
				view.enemy_armies_by_edge[edge_key]
					as Array[Army]
			).append(enemy)
		elif (
			not enemy.on_edge
			and enemy.location_city >= 0
		):
			if not view.enemy_armies_by_city.has(
				enemy.location_city
			):
				view.enemy_armies_by_city[
					enemy.location_city
				] = [] as Array[Army]
			(
				view.enemy_armies_by_city[
					enemy.location_city
				] as Array[Army]
			).append(enemy)
	EquivariantOrder.sort_armies(
		view.allied_armies,
		game_state,
		owner_nation
	)
	return view


func armies_at_city(city_id: int) -> Array[Army]:
	return armies_by_city.get(city_id, []) as Array[Army]


func armies_at_or_on_city(city_id: int) -> Array[Army]:
	return armies_by_incident_city.get(
		city_id,
		[]
	) as Array[Army]


func enemy_armies_at_city(city_id: int) -> Array[Army]:
	return enemy_armies_by_city.get(
		city_id,
		[]
	) as Array[Army]


func enemy_armies_on_edge(
	city_a: int,
	city_b: int
) -> Array[Army]:
	return enemy_armies_by_edge.get(
		GameState.edge_key(city_a, city_b),
		[]
	) as Array[Army]


func stationed_power_at(
	city_id: int,
	excluded: Army = null
) -> float:
	var result := float(
		friendly_stationed_power_by_city.get(city_id, 0.0)
	)
	if (
		excluded != null
		and excluded.owner_nation == nation_id
		and not excluded.on_edge
		and excluded.location_city == city_id
		and excluded.state in [
			Army.State.IDLE,
			Army.State.RECOVERING,
		]
	):
		result -= ArmyPower.effective(excluded)
	return maxf(result, 0.0)


func path_field(
	start: int,
	allowed_nation: int = -1,
	block_contested_edges: bool = false,
	use_danger_weight: bool = true,
	allowed_goal: int = -1,
	required_manpower: int = 0
) -> Dictionary:
	var revision_key := (
		"D:%d" % day
		if block_contested_edges
		else "R:%d:%d" % [
			state.ownership_revision,
			state.diplomacy_revision,
		]
	)
	var key := "%s:%d:%d:%d:%d:%d:%d" % [
		revision_key,
		start,
		allowed_nation,
		int(block_contested_edges),
		int(use_danger_weight),
		allowed_goal,
		required_manpower,
	]
	if not _path_field_cache.has(key):
		_path_field_cache[key] = Pathfinding.dijkstra_field(
			state,
			start,
			allowed_nation,
			block_contested_edges,
			use_danger_weight,
			allowed_goal,
			required_manpower
		)
	return _path_field_cache[key]


func nearest_supply_city(army: Army) -> Array:
	var position_key := (
		"E:%d:%d:%d"
		% [
			army.move_from,
			army.move_to,
			int(round(army.move_progress * 10000.0)),
		]
		if army.on_edge and army.move_to != -1
		else "C:%d" % army.location_city
	)
	var key := "%d:%s" % [army.owner_nation, position_key]
	if not _supply_city_cache.has(key):
		if not _supply_network_cache.has(army.owner_nation):
			_supply_network_cache[army.owner_nation] = (
				Pathfinding.build_supply_network(
					state,
					army.owner_nation
				)
			)
		var sources := Pathfinding.supply_sources_from_network(
			state,
			army,
			_supply_network_cache[army.owner_nation]
		)
		_supply_city_cache[key] = (
			[
				int(sources[0]["city_id"]),
				float(sources[0]["loss"]),
			]
			if not sources.is_empty()
			else [-1, INF]
		)
	return _supply_city_cache[key]
