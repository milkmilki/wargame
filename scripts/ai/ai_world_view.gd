class_name AiWorldView
extends RefCounted
## 单个国家的只读 AI 世界视图。当前使用全知信息；未来战争迷雾只需替换本层筛选。

var state: GameState
var nation_id: int
var day: int
var capital_city_id: int
var friendly_cities: Array[City] = []
var enemy_cities: Array[City] = []
var friendly_armies: Array[Army] = []
var enemy_armies: Array[Army] = []
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
		else:
			view.enemy_cities.append(city)
	for army in game_state.armies:
		if army.size <= 0:
			continue
		if army.owner_nation == owner_nation:
			view.friendly_armies.append(army)
		else:
			view.enemy_armies.append(army)
	view.friendly_cities.sort_custom(func(a: City, b: City) -> bool: return a.id < b.id)
	view.enemy_cities.sort_custom(func(a: City, b: City) -> bool: return a.id < b.id)
	view.friendly_armies.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
	view.enemy_armies.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
	return view
