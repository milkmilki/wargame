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
var armies_by_city: Dictionary = {}
var friendly_stationed_power_by_city: Dictionary = {}
var enemy_armies_by_city: Dictionary = {}
var enemy_armies_by_edge: Dictionary = {}
var _path_field_cache: Dictionary = {}
var _supply_city_cache: Dictionary = {}
var _supply_network_cache: Dictionary = {}


static func build(
	game_state: GameState,
	owner_nation: int,
	shared_path_cache: Dictionary = {},
	shared_supply_network_cache: Dictionary = {}
) -> AiWorldView:
	var view := AiWorldView.new()
	view.state = game_state
	view.nation_id = owner_nation
	view.day = game_state.day
	view.capital_city_id = game_state.nations[owner_nation].capital_city_id
	view._path_field_cache = shared_path_cache
	view._supply_network_cache = shared_supply_network_cache
	view.warehouses = game_state.warehouse_cities_of(owner_nation)
	for city in game_state.cities:
		if city.owner_nation == owner_nation:
			view.friendly_cities.append(city)
		elif game_state.is_enemy(owner_nation, city.owner_nation):
			view.enemy_cities.append(city)
		elif game_state.is_allied(owner_nation, city.owner_nation):
			view.allied_cities.append(city)
		else:
			view.neutral_cities.append(city)
	for army in game_state.armies:
		if army.size <= 0:
			continue
		if not army.on_edge and army.location_city >= 0:
			if not view.armies_by_city.has(army.location_city):
				view.armies_by_city[army.location_city] = (
					[] as Array[Army]
				)
			(
				view.armies_by_city[army.location_city]
				as Array[Army]
			).append(army)
		if army.owner_nation == owner_nation:
			view.friendly_armies.append(army)
			if (
				not army.on_edge
				and army.location_city >= 0
				and army.state in [
					Army.State.IDLE,
					Army.State.RECOVERING,
				]
			):
				view.friendly_stationed_power_by_city[
					army.location_city
				] = (
					float(
						view.friendly_stationed_power_by_city.get(
							army.location_city,
							0.0
						)
					)
					+ ArmyPower.effective(army)
				)
		elif game_state.is_enemy(owner_nation, army.owner_nation):
			view.enemy_armies.append(army)
		elif game_state.is_allied(owner_nation, army.owner_nation):
			view.allied_armies.append(army)
	# AI 迭代顺序必须随势力镜像一起变换，不能读取创建顺序 id。
	view.friendly_cities.sort_custom(func(a: City, b: City) -> bool:
		return EquivariantOrder.city_less(game_state, owner_nation, a, b)
	)
	view.enemy_cities.sort_custom(func(a: City, b: City) -> bool:
		return EquivariantOrder.city_less(game_state, owner_nation, a, b)
	)
	view.allied_cities.sort_custom(func(a: City, b: City) -> bool:
		return EquivariantOrder.city_less(game_state, owner_nation, a, b)
	)
	view.neutral_cities.sort_custom(func(a: City, b: City) -> bool:
		return EquivariantOrder.city_less(game_state, owner_nation, a, b)
	)
	view.friendly_armies.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(game_state, owner_nation, a, b)
	)
	view.enemy_armies.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(game_state, owner_nation, a, b)
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
	view.allied_armies.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(game_state, owner_nation, a, b)
	)
	return view


func armies_at_city(city_id: int) -> Array[Army]:
	return armies_by_city.get(city_id, []) as Array[Army]


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
