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
var friendly_cities: Array[City] = []
var enemy_cities: Array[City] = []
var allied_cities: Array[City] = []
var neutral_cities: Array[City] = []
var friendly_armies: Array[Army] = []
var enemy_armies: Array[Army] = []
var allied_armies: Array[Army] = []
var warehouses: Array[City] = []


static func build(game_state: GameState, owner_nation: int) -> AiWorldView:
	var view := AiWorldView.new()
	view.state = game_state
	view.nation_id = owner_nation
	view.day = game_state.day
	view.capital_city_id = game_state.nations[owner_nation].capital_city_id
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
		if army.owner_nation == owner_nation:
			view.friendly_armies.append(army)
		elif game_state.is_enemy(owner_nation, army.owner_nation):
			view.enemy_armies.append(army)
		elif game_state.is_allied(owner_nation, army.owner_nation):
			view.allied_armies.append(army)
	view.friendly_cities.sort_custom(func(a: City, b: City) -> bool: return a.id < b.id)
	view.enemy_cities.sort_custom(func(a: City, b: City) -> bool: return a.id < b.id)
	view.allied_cities.sort_custom(func(a: City, b: City) -> bool: return a.id < b.id)
	view.neutral_cities.sort_custom(func(a: City, b: City) -> bool: return a.id < b.id)
	view.friendly_armies.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
	view.enemy_armies.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
	view.allied_armies.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
	return view
