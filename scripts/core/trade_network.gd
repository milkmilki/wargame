class_name TradeNetwork
extends RefCounted
## 当前世界状态的纯派生贸易网络。
##
## 本类不持有缓存、不修改 GameState，也不依赖 Simulation。build() 的结果可直接
## 用于月度经济结算、AI 报告或 UI；相同输入始终得到相同路线、分配和 signature。

enum RouteStatus {
	ACTIVE,
	REROUTED,
	BLOCKED,
}

enum Policy {
	BALANCED,
	GOLD,
	FOOD,
	ISOLATION,
}

const STATUS_ACTIVE: int = RouteStatus.ACTIVE
const STATUS_REROUTED: int = RouteStatus.REROUTED
const STATUS_BLOCKED: int = RouteStatus.BLOCKED
const POLICY_BALANCED: int = Policy.BALANCED
const POLICY_GOLD: int = Policy.GOLD
const POLICY_FOOD: int = Policy.FOOD
const POLICY_ISOLATION: int = Policy.ISOLATION
## 简写别名供 UI / 测试直接使用 TradeNetwork.ACTIVE / BALANCED。
const ACTIVE: int = RouteStatus.ACTIVE
const REROUTED: int = RouteStatus.REROUTED
const BLOCKED: int = RouteStatus.BLOCKED
const BALANCED: int = Policy.BALANCED
const GOLD: int = Policy.GOLD
const FOOD: int = Policy.FOOD
const ISOLATION: int = Policy.ISOLATION

## 40 国地图上的硬上限。国际候选按可达性、运输成本和市场价值排序，
## 再以双方都未达到上限为条件贪心选取，因此任何国家都不会超过此值。
const MAX_INTERNATIONAL_ROUTES_PER_NATION: int = 3
const MAX_DOMESTIC_ROUTES_PER_NATION: int = 4
const INTERNATIONAL_HUBS_PER_NATION: int = 3
## 国际商路不是相邻小国之间的逐边集市。端点至少跨过三条交通边；每国只把
## 拓扑上最近的有限数量远程市场送入昂贵的路径/战时连通性评估。最终路线仍受
## MAX_INTERNATIONAL_ROUTES_PER_NATION 双边上限约束。这样国家数量增加时，
## 候选从 O(N²) 收敛为 O(N*K)，同时保留足够冗余供贪心匹配。
const MIN_INTERNATIONAL_ROUTE_HOPS: int = 3
const MAX_INTERNATIONAL_PARTNERS_PER_NATION: int = 8
## 战争不拆除、封锁或改道既有贸易网络，只降低参战国实际取得的贸易金。
## 与城市战乱减产使用同一 50% 口径；多场战争不会重复叠乘。
const WARTIME_TRADE_GOLD_MULTIPLIER: float = 0.50

## 与现有模型匹配的本地常量。刻意不引用 Simulation，避免 core 层循环依赖。
const FOOD_PER_CAPITA_MONTH: float = 0.0025
const BALANCED_FOOD_RESERVE_MONTHS: int = 6
const GOLD_FOOD_RESERVE_MONTHS: int = 3
const FOOD_POLICY_RESERVE_MONTHS: int = 12
const ISOLATION_FOOD_RESERVE_MONTHS: int = 9
const FOOD_UNITS_PER_GOLD: int = 25
const TRADE_CAPACITY_UNIT: int = 10000
const FOOD_CAPACITY_DIVISOR: int = 100
const MAX_ROUTE_GOLD: int = 64
## 简化版 EU4 贸易：固定的贸易节点城市（路线端点）派生「贸易竞争力」，
## 竞争力先转成金钱（路线税）；国家再用当月贸易金「凭空」买粮、买人，
## 不再与他国互相转移库存。以下是买入转换率。
## 1 金 → FOOD_UNITS_PER_GOLD 粮；1 金 → MANPOWER_UNITS_PER_GOLD 人。
const MANPOWER_UNITS_PER_GOLD: int = 50
## 贸易金买人的目标储备月数：仅在人力库低于「约一年月产人力」时补充，
## 让暴兵抽干人力后能靠贸易恢复到可满编攻势的水平，但不无限灌满。
const MANPOWER_PURCHASE_RESERVE_MONTHS: int = 12

const EDGE_KIND_LAND: int = 0
const EDGE_KIND_LANDING: int = 1
const EDGE_KIND_RIVER: int = 2
const EDGE_KIND_SEA: int = 3
const MATCHED_LOW_CAPACITY: int = 10000
const MATCHED_STANDARD_CAPACITY: int = 20000

const COST_SCALE: int = 1000
const INF_COST_UNITS: int = 0x3fffffffffffffff
const SORT_SCALE: float = 1000000.0
const UNREACHABLE_COST: float = -1.0
const DOMESTIC_IDEAL_SHARED_CACHE_MAX_ENTRIES: int = 256
const INTERNATIONAL_IDEAL_SHARED_CACHE_MAX_ENTRIES: int = 256
const OPERATIONAL_SHARED_CACHE_MAX_ENTRIES: int = 2048

## 仅用于性能等价测试/微基准，不写入 build()/build_structure() 返回值。
## build_structure 当前在主线程串行执行；这些静态计数不做并发同步。
static var _candidate_dijkstra_field_builds: int = 0
static var _candidate_connectivity_queries: int = 0
static var _candidate_connectivity_searches: int = 0
static var _candidate_connectivity_union_graph_builds: int = 0
static var _candidate_connectivity_rejections: int = 0
static var _connectivity_prefilter_union_cache_enabled: bool = true
static var _connectivity_gate_context_enabled: bool = true
static var _connectivity_gate_build_contexts: int = 0
static var _connectivity_gate_signature_context_builds: int = 0
static var _domestic_shared_field_context_enabled: bool = true
static var _domestic_ideal_shared_cache_enabled: bool = true
static var _domestic_context_builds: int = 0
static var _domestic_field_builds: int = 0
static var _domestic_route_queries: int = 0
static var _domestic_legacy_derive_calls: int = 0
static var _domestic_ideal_shared_cache_hits: int = 0
static var _domestic_ideal_shared_cache_misses: int = 0
static var _domestic_ideal_shared_cache_builds: int = 0
static var _domestic_ideal_shared_cache_clears: int = 0
static var _domestic_ideal_shared_cache_evictions: int = 0


static func reset_connectivity_prefilter_counters() -> void:
	_candidate_dijkstra_field_builds = 0
	_candidate_connectivity_queries = 0
	_candidate_connectivity_searches = 0
	_candidate_connectivity_union_graph_builds = 0
	_candidate_connectivity_rejections = 0
	_connectivity_gate_build_contexts = 0
	_connectivity_gate_signature_context_builds = 0
	_domestic_context_builds = 0
	_domestic_field_builds = 0
	_domestic_route_queries = 0
	_domestic_legacy_derive_calls = 0
	_domestic_ideal_shared_cache_hits = 0
	_domestic_ideal_shared_cache_misses = 0
	_domestic_ideal_shared_cache_builds = 0
	_domestic_ideal_shared_cache_clears = 0
	_domestic_ideal_shared_cache_evictions = 0


static func connectivity_prefilter_counters() -> Dictionary:
	return {
		"candidate_dijkstra_field_builds": _candidate_dijkstra_field_builds,
		"candidate_connectivity_queries": _candidate_connectivity_queries,
		"candidate_connectivity_searches": _candidate_connectivity_searches,
		"candidate_connectivity_legacy_bfs_searches": (
			_candidate_connectivity_searches
		),
		"candidate_connectivity_union_graph_builds": (
			_candidate_connectivity_union_graph_builds
		),
		"candidate_connectivity_rejections": (
			_candidate_connectivity_rejections
		),
		"connectivity_gate_context_enabled": (
			_connectivity_gate_context_enabled_now()
		),
		"connectivity_gate_build_contexts": (
			_connectivity_gate_build_contexts
		),
		"connectivity_gate_signature_context_builds": (
			_connectivity_gate_signature_context_builds
		),
		"domestic_context_builds": _domestic_context_builds,
		"domestic_field_builds": _domestic_field_builds,
		"domestic_route_queries": _domestic_route_queries,
		"domestic_legacy_derive_calls": _domestic_legacy_derive_calls,
		"domestic_shared_field_context_enabled": (
			_domestic_shared_field_context_enabled_now()
		),
		"domestic_ideal_shared_cache_enabled": (
			_domestic_ideal_shared_cache_enabled_now()
		),
		"domestic_ideal_shared_cache_hits": (
			_domestic_ideal_shared_cache_hits
		),
		"domestic_ideal_shared_cache_misses": (
			_domestic_ideal_shared_cache_misses
		),
		"domestic_ideal_shared_cache_builds": (
			_domestic_ideal_shared_cache_builds
		),
		"domestic_ideal_shared_cache_clears": (
			_domestic_ideal_shared_cache_clears
		),
		"domestic_ideal_shared_cache_evictions": (
			_domestic_ideal_shared_cache_evictions
		),
	}


static func set_connectivity_prefilter_union_cache_enabled(
	enabled: bool
) -> void:
	_connectivity_prefilter_union_cache_enabled = enabled


static func set_connectivity_gate_context_enabled(
	enabled: bool
) -> void:
	_connectivity_gate_context_enabled = enabled


static func set_domestic_shared_field_context_enabled(
	enabled: bool
) -> void:
	_domestic_shared_field_context_enabled = enabled


static func set_domestic_ideal_shared_cache_enabled(
	enabled: bool
) -> void:
	_domestic_ideal_shared_cache_enabled = enabled


static func _union_connectivity_prefilter_enabled() -> bool:
	var env_override := OS.get_environment(
		"TRADE_LEGACY_CONNECTIVITY_PREFILTER"
	)
	if env_override == "1":
		return false
	if env_override == "0":
		return true
	return _connectivity_prefilter_union_cache_enabled


static func _connectivity_gate_context_enabled_now() -> bool:
	var env_override := OS.get_environment(
		"TRADE_LEGACY_CONNECTIVITY_GATE_CONTEXT"
	)
	if env_override == "1":
		return false
	if env_override == "0":
		return true
	return _connectivity_gate_context_enabled


static func _domestic_shared_field_context_enabled_now() -> bool:
	var env_override := OS.get_environment(
		"TRADE_LEGACY_DOMESTIC_CONTEXT"
	)
	if env_override == "1":
		return false
	if env_override == "0":
		return true
	return _domestic_shared_field_context_enabled


static func _domestic_ideal_shared_cache_enabled_now() -> bool:
	if OS.get_environment("TRADE_DISABLE_DOMESTIC_IDEAL_CACHE") == "1":
		return false
	return _domestic_ideal_shared_cache_enabled


## 权威入口。结构派生与动态粮食结算分层后仍保持原返回结构逐字段等价。
## 返回的整数数组均以 city_id / nation_id 为下标。
static func build(
	state: GameState, use_connectivity_prefilter: bool = true
) -> Dictionary:
	return settle(state, build_structure(state, use_connectivity_prefilter))


## 可跨多次预测复用的昂贵结构层：图搜索、路线选择与路线税均只依赖
## structure_fingerprint() 覆盖的字段，不读取库存、国库或粮食需求。
## domestic ideal shared cache 的正确性在此函数内自包含：exact graph
## fingerprint 每次 build 只在入口计算一次，且 shared key 显式包含
## valid_sources + ideal_allowed_key + exact graph fingerprint，不依赖
## Simulation generation 是否正确；generation 仅用于粗粒度清理。
static func build_structure(
	state: GameState,
	use_connectivity_prefilter: bool = true,
	build_profile: Dictionary = {},
	shared_caches: Dictionary = {}
) -> Dictionary:
	if state == null:
		return _empty_structure(0, 0, structure_fingerprint(null))
	var city_count := state.cities.size()
	var nation_count := state.nations.size()
	var fingerprint := structure_fingerprint(state)
	if not _state_ids_indexable(state):
		return _empty_structure(city_count, nation_count, fingerprint)
	var city_gold_bonus := _zero_int_array(city_count)
	var nation_trade_gold := _zero_int_array(nation_count)
	var nation_trade_tax := _zero_int_array(nation_count)
	if city_count <= 0 or nation_count <= 0:
		return _make_structure(
			fingerprint, city_count, nation_count,
			[] as Array[Dictionary], city_gold_bonus,
			nation_trade_gold, nation_trade_tax, [] as Array[int]
		)

	var profile_enabled: bool = bool(build_profile.get("enabled", false))
	var stage_started: int = (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	var policies := _collect_policies(state)
	# 商路只由地图、道路、领土和贸易政策决定。围城、宣战与在途军队
	# 都不再参与建网；战争影响统一留到 settle() 的收益层处理。
	var besieged := {}
	var occupied_edges: Array[Dictionary] = []
	if profile_enabled:
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_inputs",
			Time.get_ticks_usec() - stage_started
		)
		stage_started = Time.get_ticks_usec()
	var graph := _build_graph(state)
	if profile_enabled:
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_graph",
			Time.get_ticks_usec() - stage_started
		)
		stage_started = Time.get_ticks_usec()
	var party_context := _build_trade_party_context(
		state, occupied_edges
	)
	var domestic_ideal_graph_fingerprint := PackedByteArray()
	var domestic_ideal_allowed := _ideal_city_mask(state)
	var domestic_ideal_allowed_key := _byte_mask_key(domestic_ideal_allowed)
	var shared_ideal_cache_enabled := (
		_domestic_ideal_shared_cache_enabled_now()
		and shared_caches.has("domestic_ideal_fields")
	)
	if shared_ideal_cache_enabled:
		var fingerprint_started := (
			Time.get_ticks_usec() if profile_enabled else 0
		)
		domestic_ideal_graph_fingerprint = (
			domestic_ideal_graph_fingerprint_exact(state)
		)
		if profile_enabled:
			_accumulate_build_profile(
				build_profile,
				"ai_snapshot_forecast_structure_domestic_ideal_graph_fingerprint",
				Time.get_ticks_usec() - fingerprint_started
			)
	var field_cache := {}
	var connectivity_cache := {}
	var routes: Array[Dictionary] = []
	routes.append_array(_build_domestic_routes(
		state, graph, policies, besieged, occupied_edges, field_cache,
		shared_caches, domestic_ideal_graph_fingerprint,
		domestic_ideal_allowed, domestic_ideal_allowed_key, build_profile,
		party_context
	))
	if profile_enabled:
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic",
			Time.get_ticks_usec() - stage_started
		)
	var international_shared_caches := (
		shared_caches
		if _domestic_ideal_shared_cache_enabled_now()
		else {}
	)
	routes.append_array(_build_international_routes(
		state, graph, policies, besieged, occupied_edges, field_cache,
		connectivity_cache, use_connectivity_prefilter, build_profile,
		international_shared_caches, domestic_ideal_graph_fingerprint,
		domestic_ideal_allowed_key, party_context
	))

	stage_started = Time.get_ticks_usec() if profile_enabled else 0
	routes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var international_a := bool(a["international"])
		var international_b := bool(b["international"])
		if international_a != international_b:
			return not international_a
		for key in ["nation_a", "nation_b", "source", "destination"]:
			var value_a := int(a[key])
			var value_b := int(b[key])
			if value_a != value_b:
				return value_a < value_b
		return int(a["status"]) < int(b["status"])
	)
	for route_id in range(routes.size()):
		routes[route_id]["id"] = route_id

	_apply_trade_taxes(
		state, routes, policies, city_gold_bonus,
		nation_trade_gold, nation_trade_tax
	)
	if profile_enabled:
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_result",
			Time.get_ticks_usec() - stage_started
		)
	return _make_structure(
		fingerprint, city_count, nation_count, routes, city_gold_bonus,
		nation_trade_gold, nation_trade_tax, policies
	)


static func _accumulate_build_profile(
	build_profile: Dictionary,
	stage: String,
	elapsed_usec: int
) -> void:
	if not bool(build_profile.get("enabled", false)):
		return
	build_profile[stage] = (
		int(build_profile.get(stage, 0))
		+ elapsed_usec
	)


static func _accumulate_build_profile_count(
	build_profile: Dictionary,
	stage: String,
	count: int
) -> void:
	if count <= 0:
		return
	build_profile[stage] = int(build_profile.get(stage, 0)) + count


## 在可缓存结构的深副本上执行库存/国库/需求/战争收益相关的动态结算。返回值中的
## routes、嵌套路径/分配字典和所有统计数组都不与 structure 共享可变容器。
## 调用方负责先比较 structure_fingerprint()；这里仅检查尺寸，避免缓存命中时
## 为新鲜度重复扫描全部城市、道路、战争和占边军队。
static func settle(state: GameState, structure: Dictionary) -> Dictionary:
	if state == null:
		return _empty_result(0, 0)
	var city_count := state.cities.size()
	var nation_count := state.nations.size()
	if not _state_ids_indexable(state) or city_count <= 0 or nation_count <= 0:
		return _empty_result(city_count, nation_count)
	if (
		int(structure.get("city_count", -1)) != city_count
		or int(structure.get("nation_count", -1)) != nation_count
	):
		# 尺寸变化时旧数组不可能安全复用；公开 API 保守地重建一次。
		return settle(state, build_structure(state))
	var routes := _copy_routes(structure.get(
		"routes", [] as Array[Dictionary]
	))
	var city_gold_bonus := _copy_int_array(
		structure.get("city_gold_bonus", []), city_count
	)
	var nation_trade_gold := _copy_int_array(
		structure.get("nation_trade_gold", []), nation_count
	)
	var nation_trade_tax := _copy_int_array(
		structure.get("nation_trade_tax", []), nation_count
	)
	var policies := _copy_int_array(
		structure.get("policies", []), nation_count
	)
	_apply_wartime_trade_gold(
		state, routes, city_gold_bonus, nation_trade_gold, nation_trade_tax,
		true
	)
	var nation_food_import := _zero_int_array(nation_count)
	var nation_food_export := _zero_int_array(nation_count)
	var nation_food_cost := _zero_int_array(nation_count)
	var nation_food_sale_income := _zero_int_array(nation_count)
	var nation_manpower_import := _zero_int_array(nation_count)
	var nation_manpower_cost := _zero_int_array(nation_count)
	_plan_trade_purchases(
		state, policies,
		nation_trade_gold, nation_food_import, nation_food_cost,
		nation_manpower_import, nation_manpower_cost
	)
	return _finish_result(
		routes, city_gold_bonus, nation_trade_gold, nation_trade_tax,
		nation_food_import, nation_food_export, nation_food_cost,
		nation_food_sale_income,
		nation_manpower_import, nation_manpower_cost,
		policies
	)


## AI/外交只读摘要结算。动态采购只依赖并写入国家级数组，不修改路线；
## 因此这里直接共享结构层 routes，跳过数百条路线及其路径字典的深复制，也
## 不计算只供月结发布/前端刷新使用的完整结果签名。调用方不得修改 routes。
static func settle_nation_summary(
	state: GameState, structure: Dictionary
) -> Dictionary:
	if state == null:
		return _empty_nation_summary(0)
	var city_count := state.cities.size()
	var nation_count := state.nations.size()
	if not _state_ids_indexable(state) or city_count <= 0 or nation_count <= 0:
		return _empty_nation_summary(nation_count)
	if (
		int(structure.get("city_count", -1)) != city_count
		or int(structure.get("nation_count", -1)) != nation_count
	):
		return settle_nation_summary(state, build_structure(state))
	var nation_trade_gold := _copy_int_array(
		structure.get("nation_trade_gold", []), nation_count
	)
	var nation_trade_tax := _copy_int_array(
		structure.get("nation_trade_tax", []), nation_count
	)
	var policies := _copy_int_array(
		structure.get("policies", []), nation_count
	)
	# 摘要结果共享只读 routes，不得改写结构缓存；这里只从同一份路线分配
	# 重新汇总战时实收国家数组，保证与完整 settle() 完全一致。
	_apply_wartime_trade_gold(
		state, structure.get("routes", []), [] as Array[int],
		nation_trade_gold, nation_trade_tax, false
	)
	var nation_food_import := _zero_int_array(nation_count)
	var nation_food_export := _zero_int_array(nation_count)
	var nation_food_cost := _zero_int_array(nation_count)
	var nation_food_sale_income := _zero_int_array(nation_count)
	var nation_manpower_import := _zero_int_array(nation_count)
	var nation_manpower_cost := _zero_int_array(nation_count)
	_plan_trade_purchases(
		state, policies,
		nation_trade_gold, nation_food_import, nation_food_cost,
		nation_manpower_import, nation_manpower_cost
	)
	return {
		"routes": structure.get("routes", []),
		"nation_trade_gold": nation_trade_gold,
		"nation_trade_tax": nation_trade_tax,
		"nation_food_import": nation_food_import,
		"nation_food_export": nation_food_export,
		"nation_food_cost": nation_food_cost,
		"nation_food_sale_income": nation_food_sale_income,
		"nation_manpower_import": nation_manpower_import,
		"nation_manpower_cost": nation_manpower_cost,
	}


static func _empty_nation_summary(nation_count: int) -> Dictionary:
	return {
		"routes": [] as Array[Dictionary],
		"nation_trade_gold": _zero_int_array(nation_count),
		"nation_trade_tax": _zero_int_array(nation_count),
		"nation_food_import": _zero_int_array(nation_count),
		"nation_food_export": _zero_int_array(nation_count),
		"nation_food_cost": _zero_int_array(nation_count),
		"nation_food_sale_income": _zero_int_array(nation_count),
		"nation_manpower_import": _zero_int_array(nation_count),
		"nation_manpower_cost": _zero_int_array(nation_count),
	}


static func _make_structure(
	fingerprint: PackedByteArray,
	city_count: int,
	nation_count: int,
	routes: Array[Dictionary],
	city_gold_bonus: Array[int],
	nation_trade_gold: Array[int],
	nation_trade_tax: Array[int],
	policies: Array[int]
) -> Dictionary:
	return {
		"fingerprint": fingerprint,
		"city_count": city_count,
		"nation_count": nation_count,
		"routes": routes,
		"city_gold_bonus": city_gold_bonus,
		"nation_trade_gold": nation_trade_gold,
		"nation_trade_tax": nation_trade_tax,
		"policies": policies,
	}


static func _empty_structure(
	city_count: int, nation_count: int, fingerprint: PackedByteArray
) -> Dictionary:
	return _make_structure(
		fingerprint, city_count, nation_count, [] as Array[Dictionary],
		_zero_int_array(city_count), _zero_int_array(nation_count),
		_zero_int_array(nation_count), [] as Array[int]
	)


static func _copy_routes(source: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not source is Array:
		return result
	for route_value in source as Array:
		if route_value is Dictionary:
			result.append((route_value as Dictionary).duplicate(true))
	return result


static func _copy_int_array(source: Variant, expected_size: int) -> Array[int]:
	var result := _zero_int_array(expected_size)
	if not source is Array:
		return result
	var values: Array = source
	for index in range(mini(result.size(), values.size())):
		result[index] = int(values[index])
	return result


## 结构层的无碰撞 token。把所有实际结构依赖写成有标签的 Variant 数组后
## 序列化成完整字节；不使用 hash，因而不会因哈希碰撞误复用。
## 战争、围城、军队位置、库存、国库、需求与日期都不属于路线结构。
static func structure_fingerprint(state: GameState) -> PackedByteArray:
	if state == null:
		return var_to_bytes(["trade_structure_v2", null])
	var fields: Array = [
		"trade_structure_v2",
		["counts", state.cities.size(), state.nations.size()],
		["map_aspect_ratio", state.map_aspect_ratio],
	]
	for city in state.cities:
		fields.append([
			"city", city.id, city.owner_nation, city.is_dock,
			city.map_position, city.gold_per_month, city.food_per_half_year,
			city.is_capital, city.has_warehouse, city.is_port_market,
			city.is_crossroads, city.is_food_hub,
		])
	for nation in state.nations:
		fields.append([
			"nation", nation.id, nation.alive, nation.capital_city_id,
			_policy_of(nation), _ruler_trade_multiplier(nation),
		])

	# edges 的数组顺序也保留：重复端点时 _build_graph() 采用第一条边。
	for edge in state.edges:
		fields.append([
			"edge", edge.city_a, edge.city_b, edge.kind,
			edge.max_manpower, edge.base_max_manpower, edge.distance,
			edge.travel_time_multiplier, edge.danger,
			edge.supply_loss_multiplier,
		])
	return var_to_bytes(fields)


static func domestic_ideal_graph_fingerprint_exact(
	state: GameState
) -> PackedByteArray:
	if state == null:
		return var_to_bytes(["trade_domestic_ideal_graph_v1", null])
	var fields: Array = [
		"trade_domestic_ideal_graph_v1",
		["counts", state.cities.size(), state.edges.size()],
	]
	for edge in state.edges:
		fields.append([
			"edge", edge.city_a, edge.city_b, edge.kind,
			edge.max_manpower, edge.base_max_manpower, edge.distance,
			edge.travel_time_multiplier, edge.danger,
			edge.supply_loss_multiplier,
		])
	return var_to_bytes(fields)


static func _possible_trade_parties(state: GameState) -> Array[int]:
	var owned_all := _zero_int_array(state.nations.size())
	var owned_land := _zero_int_array(state.nations.size())
	for city in state.cities:
		if city.owner_nation < 0 or city.owner_nation >= state.nations.size():
			continue
		owned_all[city.owner_nation] += 1
		if not city.is_dock:
			owned_land[city.owner_nation] += 1
	var result: Array[int] = []
	for nation in state.nations:
		if (
			nation.id >= 0 and nation.id < state.nations.size()
			and nation.alive
			and (
				owned_all[nation.id] >= 2
				or (owned_land[nation.id] > 0
					and _policy_of(nation) != Policy.ISOLATION)
			)
		):
			result.append(nation.id)
	result.sort()
	return result


static func _state_ids_indexable(state: GameState) -> bool:
	for city_index in range(state.cities.size()):
		if state.cities[city_index].id != city_index:
			return false
	for nation_index in range(state.nations.size()):
		if state.nations[nation_index].id != nation_index:
			return false
	return true


## 兼容调用名；所有实现都收敛到 build()。
static func compute(state: GameState) -> Dictionary:
	return build(state)


static func derive(state: GameState) -> Dictionary:
	return build(state)


static func _empty_result(city_count: int, nation_count: int) -> Dictionary:
	return _finish_result(
		[] as Array[Dictionary],
		_zero_int_array(city_count), _zero_int_array(nation_count),
		_zero_int_array(nation_count),
		_zero_int_array(nation_count), _zero_int_array(nation_count),
		_zero_int_array(nation_count), _zero_int_array(nation_count),
		_zero_int_array(nation_count), _zero_int_array(nation_count),
		[] as Array[int]
	)


static func _finish_result(
	routes: Array[Dictionary],
	city_gold_bonus: Array[int],
	nation_trade_gold: Array[int],
	nation_trade_tax: Array[int],
	nation_food_import: Array[int],
	nation_food_export: Array[int],
	nation_food_cost: Array[int],
	nation_food_sale_income: Array[int],
	nation_manpower_import: Array[int],
	nation_manpower_cost: Array[int],
	policies: Array[int]
) -> Dictionary:
	var signature := _result_signature(
		routes, city_gold_bonus, nation_trade_gold, nation_trade_tax,
		nation_food_import, nation_food_export, nation_food_cost,
		nation_food_sale_income,
		nation_manpower_import, nation_manpower_cost,
		policies
	)
	return {
		"routes": routes,
		"city_gold_bonus": city_gold_bonus,
		"nation_trade_gold": nation_trade_gold,
		"nation_trade_tax": nation_trade_tax,
		"nation_food_import": nation_food_import,
		"nation_food_export": nation_food_export,
		"nation_food_cost": nation_food_cost,
		"nation_food_sale_income": nation_food_sale_income,
		"nation_manpower_import": nation_manpower_import,
		"nation_manpower_cost": nation_manpower_cost,
		"signature": signature,
	}


static func _zero_int_array(size: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(maxi(size, 0))
	result.fill(0)
	return result


static func _collect_policies(state: GameState) -> Array[int]:
	var result: Array[int] = []
	result.resize(state.nations.size())
	result.fill(Policy.BALANCED)
	for nation in state.nations:
		if nation.id < 0 or nation.id >= result.size():
			continue
		result[nation.id] = _policy_of(nation)
	return result


static func _policy_of(nation: Object) -> int:
	var raw: Variant = nation.get(&"trade_policy")
	if raw is String or raw is StringName:
		var normalized := str(raw).strip_edges().to_upper()
		if normalized.begins_with("POLICY_"):
			normalized = normalized.trim_prefix("POLICY_")
		match normalized:
			"GOLD":
				return Policy.GOLD
			"FOOD":
				return Policy.FOOD
			"ISOLATION":
				return Policy.ISOLATION
			_:
				return Policy.BALANCED
	return clampi(int(raw), Policy.BALANCED, Policy.ISOLATION)


## 自建只读邻接快照，避免依赖测试夹具是否手工同步了 GameState.adjacency。
static func _build_graph(state: GameState) -> Dictionary:
	var adjacency: Array = []
	adjacency.resize(state.cities.size())
	for city_id in range(adjacency.size()):
		adjacency[city_id] = [] as Array[int]
	var edge_lookup := {}
	for edge in state.edges:
		var a := int(edge.city_a)
		var b := int(edge.city_b)
		if (
			a < 0 or b < 0 or a >= adjacency.size()
			or b >= adjacency.size() or a == b
		):
			continue
		var key := _edge_key(a, b)
		if edge_lookup.has(key):
			continue
		edge_lookup[key] = edge
		(adjacency[a] as Array[int]).append(b)
		(adjacency[b] as Array[int]).append(a)
	for neighbors_value in adjacency:
		(neighbors_value as Array[int]).sort()
	return {
		"adjacency": adjacency,
		"edge_lookup": edge_lookup,
	}


static func _edge_key(a: int, b: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return (lo << 32) | hi


## 每条实际占用记录只保留 edge 与 owner。是否为敌军取决于具体贸易双方，
## 因而留到派生单条路线时判断。
static func _enemy_occupancy_records(state: GameState) -> Array[Dictionary]:
	var unique := {}
	for army in state.armies:
		if (
			army.size <= 0 or not army.on_edge
			or army.move_from < 0 or army.move_to < 0
			or army.owner_nation < 0
		):
			continue
		var edge_key := _edge_key(army.move_from, army.move_to)
		var record_key := "%d:%d" % [edge_key, army.owner_nation]
		unique[record_key] = {
			"edge_key": edge_key,
			"owner": army.owner_nation,
		}
	var keys := unique.keys()
	keys.sort()
	var result: Array[Dictionary] = []
	for key in keys:
		result.append(unique[key] as Dictionary)
	return result


static func _blocked_edges_for_parties(
	state: GameState,
	nation_a: int,
	nation_b: int,
	occupied_edges: Array[Dictionary]
) -> Dictionary:
	var result := {}
	for record in occupied_edges:
		var owner := int(record["owner"])
		if (
			state.is_enemy(owner, nation_a)
			or state.is_enemy(owner, nation_b)
		):
			result[int(record["edge_key"])] = true
	return result


static func _allowed_city_mask(
	state: GameState,
	_nation_a: int,
	_nation_b: int
) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(state.cities.size())
	result.fill(0)
	for city in state.cities:
		if city.id < 0 or city.id >= result.size():
			continue
		var owner := city.owner_nation
		if (
			owner >= 0 and owner < state.nations.size()
		):
			result[city.id] = 1
	return result


## 一次贸易结构构建内按国家预计算固定准入原语。国家身份只用于保留缓存
## 接口；所有贸易方共享同一领土图，战争不会改变允许城市或封锁道路。
static func _build_trade_party_context(
	state: GameState, _occupied_edges: Array[Dictionary]
) -> Dictionary:
	var allowed_masks: Array[PackedByteArray] = []
	var blocked_edges_by_nation: Array[Dictionary] = []
	allowed_masks.resize(state.nations.size())
	blocked_edges_by_nation.resize(state.nations.size())
	for nation in state.nations:
		allowed_masks[nation.id] = _allowed_city_mask(
			state, nation.id, nation.id
		)
		blocked_edges_by_nation[nation.id] = {}
	return {
		"allowed_masks": allowed_masks,
		"blocked_edges_by_nation": blocked_edges_by_nation,
	}


static func _international_allowed_mask(
	party_context: Dictionary, nation_a: int, nation_b: int
) -> PackedByteArray:
	var masks: Array = party_context.get("allowed_masks", [])
	if nation_a < 0 or nation_b < 0 or nation_a >= masks.size() or nation_b >= masks.size():
		return PackedByteArray()
	var mask_a: PackedByteArray = masks[nation_a]
	var mask_b: PackedByteArray = masks[nation_b]
	var result := PackedByteArray()
	result.resize(mini(mask_a.size(), mask_b.size()))
	for city_id in range(result.size()):
		result[city_id] = 1 if mask_a[city_id] != 0 and mask_b[city_id] != 0 else 0
	return result


static func _international_blocked_edges(
	party_context: Dictionary, nation_a: int, nation_b: int
) -> Dictionary:
	var by_nation: Array = party_context.get("blocked_edges_by_nation", [])
	if nation_a < 0 or nation_b < 0 or nation_a >= by_nation.size() or nation_b >= by_nation.size():
		return {}
	var result: Dictionary = (by_nation[nation_a] as Dictionary).duplicate()
	result.merge(by_nation[nation_b] as Dictionary, true)
	return result


static func _ideal_city_mask(state: GameState) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(state.cities.size())
	result.fill(0)
	for city in state.cities:
		if (
			city.id >= 0 and city.id < result.size()
			and city.owner_nation >= 0
			and city.owner_nation < state.nations.size()
		):
			result[city.id] = 1
	return result


static func _build_domestic_routes(
	state: GameState,
	graph: Dictionary,
	policies: Array[int],
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	field_cache: Dictionary,
	shared_caches: Dictionary,
	shared_graph_fingerprint: PackedByteArray,
	ideal_allowed: PackedByteArray,
	ideal_allowed_key: String,
	build_profile: Dictionary = {},
	party_context: Dictionary = {}
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var shared_context_enabled := _domestic_shared_field_context_enabled_now()
	var shared_ideal_cache_enabled := (
		_domestic_ideal_shared_cache_enabled_now()
		and shared_caches.has("domestic_ideal_fields")
	)
	var profile_enabled: bool = bool(build_profile.get("enabled", false))
	var profile_sink := (
		{"enabled": true} if profile_enabled else {}
	)
	var shared_domestic_ideal_fields := {}
	if shared_ideal_cache_enabled:
		var cache_value: Variant = shared_caches.get(
			"domestic_ideal_fields",
			null
		)
		if cache_value is Dictionary:
			shared_domestic_ideal_fields = cache_value as Dictionary
	var shared_operational_fields := {}
	var shared_operational_enabled := shared_caches.has(
		"operational_fields"
	)
	if shared_operational_enabled:
		shared_operational_fields = (
			shared_caches["operational_fields"] as Dictionary
		)
	var domestic_started := (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	for nation in state.nations:
		if not nation.alive:
			continue
		var nation_id := nation.id
		if nation_id < 0 or nation_id >= policies.size():
			continue
		var prep_started := (
			Time.get_ticks_usec() if profile_enabled else 0
		)
		var owned_land := _owned_trade_cities(state, nation_id, false)
		var owned_all := _owned_trade_cities(state, nation_id, true)
		if owned_all.size() < 2:
			continue
		var primary := nation.capital_city_id
		if (
			primary < 0 or primary >= state.cities.size()
			or state.cities[primary].owner_nation != nation_id
			or state.cities[primary].is_dock
		):
			primary = (
				owned_land[0] if not owned_land.is_empty() else owned_all[0]
			)
		var destinations: Array[int] = []
		for city_id in owned_land:
			if city_id != primary:
				destinations.append(city_id)
		_sort_hubs(state, destinations, policies[nation_id])
		if profile_enabled:
			_accumulate_profile_sink(
				profile_sink,
				"domestic_prep",
				Time.get_ticks_usec() - prep_started
			)
		# A one-land-city port state still gets a domestic capital-to-dock route.
		if destinations.is_empty():
			for city_id in owned_all:
				if city_id != primary:
					destinations.append(city_id)
			destinations.sort()
		var limit := mini(
			MAX_DOMESTIC_ROUTES_PER_NATION, destinations.size()
		)
		if shared_context_enabled:
			var context := _build_domestic_route_context(
				state, graph, nation_id, primary, ideal_allowed,
				besieged, occupied_edges, field_cache,
				shared_domestic_ideal_fields, shared_graph_fingerprint,
				ideal_allowed_key, shared_operational_fields,
				shared_operational_enabled,
				profile_sink, party_context
			)
			for index in range(limit):
				result.append(_derive_route_from_precomputed_context(
					state, graph, context, destinations[index], profile_sink
				))
			continue
		for index in range(limit):
			_domestic_legacy_derive_calls += 1
			var route := _derive_route(
				state, graph, [primary] as Array[int],
				[destinations[index]] as Array[int],
				nation_id, nation_id, false, besieged, occupied_edges,
				field_cache, true, profile_sink
			)
			result.append(route)
	if profile_enabled:
		var domestic_total := Time.get_ticks_usec() - domestic_started
		var measured := (
			int(profile_sink.get("domestic_prep", 0))
			+ int(profile_sink.get("domestic_context", 0))
			+ int(profile_sink.get("domestic_route_select", 0))
			+ int(profile_sink.get("domestic_route_explain", 0))
			+ int(profile_sink.get("domestic_route_materialize", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_prep",
			int(profile_sink.get("domestic_prep", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_context",
			int(profile_sink.get("domestic_context", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_context_mask_block_key",
			int(profile_sink.get("domestic_context_mask_block_key", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_context_ideal_field",
			int(profile_sink.get("domestic_context_ideal_field", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_context_operational_field",
			int(profile_sink.get("domestic_context_operational_field", 0))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_context_ideal_field_cache_hits",
			int(profile_sink.get("domestic_context_ideal_field_cache_hits", 0))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_context_ideal_field_cache_misses",
			int(profile_sink.get("domestic_context_ideal_field_cache_misses", 0))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_context_ideal_field_cache_builds",
			int(profile_sink.get("domestic_context_ideal_field_cache_builds", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_route_select",
			int(profile_sink.get("domestic_route_select", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_route_explain",
			int(profile_sink.get("domestic_route_explain", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_route_materialize",
			int(profile_sink.get("domestic_route_materialize", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_domestic_unaccounted",
			maxi(domestic_total - measured, 0)
		)
	return result


static func _build_domestic_route_context(
	state: GameState,
	graph: Dictionary,
	nation_id: int,
	primary: int,
	ideal_allowed: PackedByteArray,
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	field_cache: Dictionary,
	shared_domestic_ideal_fields: Dictionary,
	shared_graph_fingerprint: PackedByteArray,
	ideal_allowed_key: String,
	shared_operational_fields: Dictionary,
	shared_operational_enabled: bool,
	profile_sink: Dictionary = {},
	party_context: Dictionary = {}
) -> Dictionary:
	_domestic_context_builds += 1
	var profile_enabled := bool(profile_sink.get("enabled", false))
	var phase_started := (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	var allowed := (
		(party_context["allowed_masks"] as Array)[nation_id]
		if party_context.has("allowed_masks")
		else _allowed_city_mask(state, nation_id, nation_id)
	) as PackedByteArray
	var blocked_edges := (
		(party_context["blocked_edges_by_nation"] as Array)[nation_id]
		if party_context.has("blocked_edges_by_nation")
		else _blocked_edges_for_parties(
			state, nation_id, nation_id, occupied_edges
		)
	) as Dictionary
	var sources := [primary] as Array[int]
	var mask_block_key_usec := 0
	if profile_enabled:
		mask_block_key_usec = Time.get_ticks_usec() - phase_started
		phase_started = Time.get_ticks_usec()
	var ideal_field_result := _get_shared_domestic_ideal_field(
		state, graph, sources, ideal_allowed, field_cache,
		shared_domestic_ideal_fields, shared_graph_fingerprint,
		ideal_allowed_key
	)
	var ideal_field: Dictionary = ideal_field_result["field"]
	var ideal_field_usec := 0
	if profile_enabled:
		ideal_field_usec = Time.get_ticks_usec() - phase_started
		phase_started = Time.get_ticks_usec()
	var operational_field := _get_shared_operational_endpoint_field(
		state, graph, sources, allowed, besieged, blocked_edges,
		field_cache, shared_operational_fields, shared_graph_fingerprint,
		shared_operational_enabled
	)
	var operational_field_usec := 0
	if profile_enabled:
		operational_field_usec = Time.get_ticks_usec() - phase_started
		_accumulate_profile_sink(
			profile_sink,
			"domestic_context_mask_block_key",
			mask_block_key_usec
		)
		_accumulate_profile_sink(
			profile_sink,
			"domestic_context_ideal_field",
			ideal_field_usec
		)
		_accumulate_profile_sink(
			profile_sink,
			"domestic_context_ideal_field_cache_hits",
			int(ideal_field_result.get("cache_hits", 0))
		)
		_accumulate_profile_sink(
			profile_sink,
			"domestic_context_ideal_field_cache_misses",
			int(ideal_field_result.get("cache_misses", 0))
		)
		_accumulate_profile_sink(
			profile_sink,
			"domestic_context_ideal_field_cache_builds",
			int(ideal_field_result.get("cache_builds", 0))
		)
		_accumulate_profile_sink(
			profile_sink,
			"domestic_context_operational_field",
			operational_field_usec
		)
		_accumulate_profile_sink(
			profile_sink,
			"domestic_context",
			mask_block_key_usec + ideal_field_usec + operational_field_usec
		)
	return {
		"nation_id": nation_id,
		"primary": primary,
		"sources": sources,
		"ideal_allowed": ideal_allowed,
		"allowed": allowed,
		"blocked_edges": blocked_edges,
		"ideal_field": ideal_field,
		"operational_field": operational_field,
		"besieged": besieged,
	}


static func _build_international_routes(
	state: GameState,
	graph: Dictionary,
	policies: Array[int],
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	field_cache: Dictionary,
	connectivity_cache: Dictionary,
	use_connectivity_prefilter: bool,
	build_profile: Dictionary = {},
	shared_caches: Dictionary = {},
	shared_graph_fingerprint: PackedByteArray = PackedByteArray(),
	ideal_allowed_key: String = "",
	party_context: Dictionary = {}
) -> Array[Dictionary]:
	var profile_enabled: bool = bool(build_profile.get("enabled", false))
	var stage_started: int = (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	var phase_started := (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	var pair_loop_started := (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	var candidate_hubs_prep_usec := 0
	var candidate_pair_prefilter_usec := 0
	var candidate_ideal_field_usec := 0
	var candidate_ideal_field_builds := 0
	var candidate_ideal_field_local_hits := 0
	var candidate_ideal_field_source_sets := 0
	var candidate_endpoint_scan_usec := 0
	var candidate_union_gate_usec := 0
	var candidate_value_usec := 0
	var candidate_emit_usec := 0
	var candidate_sort_usec := 0
	var candidate_emitted := 0
	var candidate_pair_loop_total_usec := 0
	var candidate_pair_iteration_total_usec := 0
	var candidate_pair_iteration_count := 0
	var candidate_hub_score_calls := 0
	var candidate_hub_sort_calls := 0
	var candidate_hub_value_calls := 0
	var hubs_by_nation: Array = []
	hubs_by_nation.resize(state.nations.size())
	var international_candidate_nation_ids: Array[int] = []
	var hub_sort_counts := [0, 0]
	for nation_id in range(state.nations.size()):
		hubs_by_nation[nation_id] = _international_hubs(
			state,
			nation_id,
			policies[nation_id],
			{} if not profile_enabled else {"enabled": true},
			hub_sort_counts
		)
		if (
			state.nations[nation_id].alive
			and policies[nation_id] != Policy.ISOLATION
			and not (hubs_by_nation[nation_id] as Array[int]).is_empty()
		):
			international_candidate_nation_ids.append(nation_id)
	if profile_enabled:
		candidate_hub_score_calls += hub_sort_counts[0]
		candidate_hub_sort_calls += hub_sort_counts[1]
	var ideal_allowed := _ideal_city_mask(state)
	var union_connectivity_prefilter := (
		use_connectivity_prefilter
		and _union_connectivity_prefilter_enabled()
	)
	var gate_context_enabled := (
		union_connectivity_prefilter
		and _connectivity_gate_context_enabled_now()
	)
	var gate_build_context := {}
	if profile_enabled:
		candidate_hubs_prep_usec = Time.get_ticks_usec() - phase_started

	# 先以无权拓扑建立稀疏远程市场图：相邻端点不构成国际商路，每国至多
	# K 个候选伙伴。后续昂贵的运输成本与战时连通性只对该图的边求值。
	var candidates: Array[Dictionary] = []
	var candidate_pairs := _international_candidate_pairs(
		graph, hubs_by_nation, international_candidate_nation_ids
	)
	if profile_enabled:
		candidate_pair_prefilter_usec = (
			Time.get_ticks_usec() - pair_loop_started
		)
		pair_loop_started = Time.get_ticks_usec()
	var shared_international_ideal_fields := {}
	if shared_caches.has("international_ideal_fields"):
		shared_international_ideal_fields = (
			shared_caches["international_ideal_fields"] as Dictionary
		)
	var shared_international_enabled := shared_caches.has(
		"international_ideal_fields"
	)
	var shared_operational_fields := {}
	var shared_operational_enabled := shared_caches.has(
		"operational_fields"
	)
	if shared_operational_enabled:
		shared_operational_fields = (
			shared_caches["operational_fields"] as Dictionary
		)
	for pair in candidate_pairs:
		var nation_a := pair.x
		var nation_b := pair.y
		var source_hubs: Array[int] = hubs_by_nation[nation_a]
		var destination_hubs: Array[int] = hubs_by_nation[nation_b]
		var pair_iteration_started := (
			Time.get_ticks_usec() if profile_enabled else 0
		)
		var pair_phase_started := (
			Time.get_ticks_usec() if profile_enabled else 0
		)
		var preferred_field_result := (
			_get_shared_international_ideal_field(
				state, graph, source_hubs, ideal_allowed,
				field_cache, shared_international_ideal_fields,
				shared_graph_fingerprint, ideal_allowed_key,
				shared_international_enabled
			)
		)
		if profile_enabled:
			candidate_ideal_field_usec += (
				Time.get_ticks_usec() - pair_phase_started
			)
			candidate_ideal_field_builds += int(
				preferred_field_result.get("builds", 0)
			)
			candidate_ideal_field_local_hits += int(
				preferred_field_result.get("local_hits", 0)
			)
			candidate_ideal_field_source_sets += int(
				preferred_field_result.get("source_sets", 0)
			)
			pair_phase_started = Time.get_ticks_usec()
		var preferred := _select_preferred_endpoints_from_field(
			state, source_hubs, destination_hubs,
			preferred_field_result["field"], false
		)
		if profile_enabled:
			candidate_endpoint_scan_usec += (
				Time.get_ticks_usec() - pair_phase_started
			)
			pair_phase_started = Time.get_ticks_usec()
		# No ideal path means there is no trade corridor to retain as BLOCKED.
		if float(preferred["cost"]) < 0.0:
			if profile_enabled:
				candidate_pair_iteration_total_usec += (
					Time.get_ticks_usec() - pair_iteration_started
				)
				candidate_pair_iteration_count += 1
			continue
		var is_operational: bool
		if use_connectivity_prefilter:
			var gate_started := (
				Time.get_ticks_usec() if profile_enabled else 0
			)
			if union_connectivity_prefilter:
				if gate_context_enabled and gate_build_context.is_empty():
					gate_build_context = _build_connectivity_gate_build_context(
						state,
						connectivity_cache,
						international_candidate_nation_ids
					)
				is_operational = _has_operational_connection_union(
					state, graph, source_hubs, destination_hubs,
					nation_a, nation_b, besieged, occupied_edges,
					connectivity_cache, gate_build_context
				)
			else:
				var allowed := _allowed_city_mask(
					state, nation_a, nation_b
				)
				var blocked_edges := _blocked_edges_for_parties(
					state, nation_a, nation_b, occupied_edges
				)
				is_operational = _has_operational_connection(
					state, graph, source_hubs, destination_hubs,
					allowed, besieged, blocked_edges,
					connectivity_cache
				)
			if profile_enabled:
				candidate_union_gate_usec += (
					Time.get_ticks_usec() - gate_started
				)
				pair_phase_started = Time.get_ticks_usec()
		else:
			var allowed := _allowed_city_mask(state, nation_a, nation_b)
			var blocked_edges := _blocked_edges_for_parties(
				state, nation_a, nation_b, occupied_edges
			)
			var operational_field_result := (
				_get_preferred_endpoint_field_with_stats(
					state, graph, source_hubs, allowed,
					true, besieged, blocked_edges, field_cache,
					true
				)
			)
			var operational := _select_preferred_endpoints_from_field(
				state, source_hubs, destination_hubs,
				operational_field_result["field"], false
			)
			is_operational = float(operational["cost"]) >= 0.0
			if profile_enabled:
				candidate_union_gate_usec += (
					Time.get_ticks_usec() - pair_phase_started
				)
				pair_phase_started = Time.get_ticks_usec()
		if profile_enabled:
			candidate_hub_score_calls += 2
			candidate_hub_value_calls += 2
		var value_started := (
			Time.get_ticks_usec() if profile_enabled else 0
		)
		var candidate_value := _international_candidate_value(
			state, int(preferred["source"]),
			int(preferred["destination"]),
			float(preferred["cost"]),
			policies[nation_a], policies[nation_b]
		)
		if profile_enabled:
			candidate_value_usec += (
				Time.get_ticks_usec() - value_started
			)
			pair_phase_started = Time.get_ticks_usec()
		candidates.append({
			"nation_a": nation_a,
			"nation_b": nation_b,
			"operational": is_operational,
			"preferred_transport_cost": float(preferred["cost"]),
			"candidate_value": candidate_value,
		})
		if profile_enabled:
			candidate_emit_usec += (
				Time.get_ticks_usec() - pair_phase_started
			)
			candidate_emitted += 1
			candidate_pair_iteration_total_usec += (
				Time.get_ticks_usec() - pair_iteration_started
			)
			candidate_pair_iteration_count += 1
	if profile_enabled:
		candidate_pair_loop_total_usec = (
			Time.get_ticks_usec() - pair_loop_started
		)
		phase_started = Time.get_ticks_usec()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var operational_a := bool(a["operational"])
		var operational_b := bool(b["operational"])
		if operational_a != operational_b:
			return operational_a
		var value_a := _sort_units(float(a["candidate_value"]))
		var value_b := _sort_units(float(b["candidate_value"]))
		if value_a != value_b:
			return value_a > value_b
		var cost_a := _sort_units(float(a["preferred_transport_cost"]))
		var cost_b := _sort_units(float(b["preferred_transport_cost"]))
		if cost_a != cost_b:
			return cost_a < cost_b
		if int(a["nation_a"]) != int(b["nation_a"]):
			return int(a["nation_a"]) < int(b["nation_a"])
		return int(a["nation_b"]) < int(b["nation_b"])
	)
	if profile_enabled:
		candidate_sort_usec = Time.get_ticks_usec() - phase_started
		var candidate_total := Time.get_ticks_usec() - stage_started
		var candidate_measured := (
			candidate_hubs_prep_usec
			+ candidate_pair_prefilter_usec
			+ candidate_ideal_field_usec
			+ candidate_endpoint_scan_usec
			+ candidate_union_gate_usec
			+ candidate_value_usec
			+ candidate_emit_usec
			+ candidate_sort_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates",
			candidate_total
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_hubs_prep",
			candidate_hubs_prep_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_pair_prefilter",
			candidate_pair_prefilter_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_ideal_field",
			candidate_ideal_field_usec
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_ideal_field_builds",
			candidate_ideal_field_builds
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_ideal_field_local_hits",
			candidate_ideal_field_local_hits
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_ideal_field_source_sets",
			candidate_ideal_field_source_sets
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_endpoint_scan",
			candidate_endpoint_scan_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_union_gate",
			candidate_union_gate_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_score",
			candidate_value_usec + candidate_emit_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_value",
			candidate_value_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_emit",
			candidate_emit_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_sort",
			candidate_sort_usec
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_emitted",
			candidate_emitted
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_pair_loop_total",
			candidate_pair_loop_total_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_pair_iteration_total",
			candidate_pair_iteration_total_usec
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_pair_iteration_count",
			candidate_pair_iteration_count
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_hub_score_calls",
			candidate_hub_score_calls
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_hub_sort_calls",
			candidate_hub_sort_calls
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_hub_value_calls",
			candidate_hub_value_calls
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_candidates_unaccounted",
			maxi(candidate_total - candidate_measured, 0)
		)

	stage_started = Time.get_ticks_usec() if profile_enabled else 0
	var route_profile_sink := (
		{"enabled": true} if profile_enabled else {}
	)
	var counts := _zero_int_array(state.nations.size())
	var result: Array[Dictionary] = []
	for candidate in candidates:
		var nation_a := int(candidate["nation_a"])
		var nation_b := int(candidate["nation_b"])
		if (
			counts[nation_a] >= MAX_INTERNATIONAL_ROUTES_PER_NATION
			or counts[nation_b] >= MAX_INTERNATIONAL_ROUTES_PER_NATION
		):
			continue
		var route := _derive_route(
			state, graph, hubs_by_nation[nation_a],
			hubs_by_nation[nation_b], nation_a, nation_b, true,
			besieged, occupied_edges, field_cache, true, route_profile_sink,
			shared_operational_fields, shared_graph_fingerprint,
			shared_operational_enabled, party_context
		)
		result.append(route)
		counts[nation_a] += 1
		counts[nation_b] += 1
	if profile_enabled:
		var route_total := Time.get_ticks_usec() - stage_started
		var route_measured := (
			int(route_profile_sink.get("international_route_ideal_lookup", 0))
			+ int(route_profile_sink.get("international_route_endpoint_select", 0))
			+ int(route_profile_sink.get(
				"international_route_operational_field", 0
			))
			+ int(route_profile_sink.get(
				"international_route_explain_details", 0
			))
			+ int(route_profile_sink.get(
				"international_route_materialize", 0
			))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes",
			route_total
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_ideal_lookup",
			int(route_profile_sink.get("international_route_ideal_lookup", 0))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_ideal_lookup_builds",
			int(route_profile_sink.get(
				"international_route_ideal_lookup_builds", 0
			))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_ideal_lookup_local_hits",
			int(route_profile_sink.get(
				"international_route_ideal_lookup_local_hits", 0
			))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_ideal_lookup_source_sets",
			int(route_profile_sink.get(
				"international_route_ideal_lookup_source_sets", 0
			))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_endpoint_select",
			int(route_profile_sink.get("international_route_endpoint_select", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_operational_field",
			int(route_profile_sink.get(
				"international_route_operational_field", 0
			))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_operational_field_builds",
			int(route_profile_sink.get(
				"international_route_operational_field_builds", 0
			))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_operational_field_local_hits",
			int(route_profile_sink.get(
				"international_route_operational_field_local_hits", 0
			))
		)
		_accumulate_build_profile_count(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_operational_field_source_sets",
			int(route_profile_sink.get(
				"international_route_operational_field_source_sets", 0
			))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_explain_details",
			int(route_profile_sink.get(
				"international_route_explain_details", 0
			))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_materialize",
			int(route_profile_sink.get("international_route_materialize", 0))
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_forecast_structure_international_routes_unaccounted",
			maxi(route_total - route_measured, 0)
		)
	return result


## 从各国国际 hub 同时做无权 BFS，按“最近 hub 的跳数”选择伙伴。任何一对
## 只要有端点少于最小跳数就被视为本地贸易，不进入国际路线；双向候选取并集，
## 避免单向 K 近邻让高 id 国家失去公平配额。
static func _international_candidate_pairs(
	graph: Dictionary,
	hubs_by_nation: Array,
	candidate_nation_ids: Array[int]
) -> Array[Vector2i]:
	var eligible := {}
	var hubs_by_city := {}
	for nation_id in candidate_nation_ids:
		eligible[nation_id] = true
		for city_id in hubs_by_nation[nation_id] as Array[int]:
			if not hubs_by_city.has(city_id):
				hubs_by_city[city_id] = [] as Array[int]
			(hubs_by_city[city_id] as Array[int]).append(nation_id)
	var adjacency: Array = graph.get("adjacency", [])
	var pair_keys := {}
	for nation_id in candidate_nation_ids:
		var distances := PackedInt32Array()
		distances.resize(adjacency.size())
		distances.fill(-1)
		var queue: Array[int] = []
		for source in hubs_by_nation[nation_id] as Array[int]:
			if source < 0 or source >= distances.size():
				continue
			distances[source] = 0
			queue.append(source)
		var nearest_hops := {}
		var far_partner_count := 0
		var cutoff_hops := 2147483647
		var cursor := 0
		while cursor < queue.size():
			var city_id := queue[cursor]
			cursor += 1
			var hops := distances[city_id]
			if hops > cutoff_hops:
				break
			if hubs_by_city.has(city_id):
				for partner_value in hubs_by_city[city_id] as Array[int]:
					var partner := int(partner_value)
					if (
						partner != nation_id
						and not nearest_hops.has(partner)
					):
						nearest_hops[partner] = hops
						if hops >= MIN_INTERNATIONAL_ROUTE_HOPS:
							far_partner_count += 1
							if far_partner_count >= MAX_INTERNATIONAL_PARTNERS_PER_NATION:
								cutoff_hops = hops
			if hops >= cutoff_hops:
				continue
			for neighbor in adjacency[city_id] as Array[int]:
				if neighbor < 0 or neighbor >= distances.size():
					continue
				if distances[neighbor] >= 0:
					continue
				distances[neighbor] = hops + 1
				queue.append(neighbor)
		var ranked: Array[Dictionary] = []
		for partner_value in nearest_hops:
			var partner := int(partner_value)
			var hops := int(nearest_hops[partner_value])
			if (
				not eligible.has(partner)
				or hops < MIN_INTERNATIONAL_ROUTE_HOPS
			):
				continue
			ranked.append({"nation": partner, "hops": hops})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["hops"]) != int(b["hops"]):
				return int(a["hops"]) < int(b["hops"])
			return int(a["nation"]) < int(b["nation"])
		)
		for index in range(mini(
			MAX_INTERNATIONAL_PARTNERS_PER_NATION, ranked.size()
		)):
			var partner := int(ranked[index]["nation"])
			var nation_a := mini(nation_id, partner)
			var nation_b := maxi(nation_id, partner)
			pair_keys[_edge_key(nation_a, nation_b)] = Vector2i(
				nation_a, nation_b
			)
	var keys := pair_keys.keys()
	keys.sort()
	var result: Array[Vector2i] = []
	for key in keys:
		result.append(pair_keys[key] as Vector2i)
	return result


## 候选排序只需要“任一源点能否到达任一不同终点”。这里严格复用
## operational Dijkstra 的准入条件，但不计算成本、前驱或具体路径。
static func _has_operational_connection_union(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	destinations: Array[int],
	nation_a: int,
	nation_b: int,
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	connectivity_cache: Dictionary,
	gate_build_context: Dictionary = {}
) -> bool:
	_candidate_connectivity_queries += 1
	var union_context := _connectivity_union_context(
		state, graph, nation_a, nation_b, besieged,
		occupied_edges, connectivity_cache, gate_build_context
	)
	var allowed: PackedByteArray = union_context["allowed"]
	var component_ids: PackedInt32Array = union_context["component_ids"]
	var active_sources := {}
	var active_components := {}
	for source in sources:
		if (
			source < 0 or source >= component_ids.size()
			or active_sources.has(source)
			or source >= allowed.size() or allowed[source] == 0
			or besieged.has(source)
		):
			continue
		var component_id := int(component_ids[source])
		if component_id < 0:
			continue
		active_sources[source] = true
		active_components[component_id] = true
	for destination in destinations:
		if (
			destination < 0
			or destination >= component_ids.size()
			or active_sources.has(destination)
		):
			continue
		if active_components.has(int(component_ids[destination])):
			return true
	_candidate_connectivity_rejections += 1
	return false


static func _build_connectivity_gate_build_context(
	state: GameState,
	connectivity_cache: Dictionary,
	candidate_nation_ids: Array[int] = []
) -> Dictionary:
	if connectivity_cache.has("__gate_build_context"):
		return connectivity_cache["__gate_build_context"] as Dictionary
	_connectivity_gate_build_contexts += 1
	var nation_enemy_ids: Array = []
	var nation_enemy_signatures: Array = []
	var nation_enemy_sets: Array = []
	nation_enemy_ids.resize(state.nations.size())
	nation_enemy_signatures.resize(state.nations.size())
	nation_enemy_sets.resize(state.nations.size())
	if candidate_nation_ids.is_empty():
		for nation_id in range(state.nations.size()):
			candidate_nation_ids.append(nation_id)
	for nation_id in candidate_nation_ids:
		var enemy_ids: Array[int] = []
		var enemy_set := {}
		nation_enemy_ids[nation_id] = enemy_ids
		nation_enemy_signatures[nation_id] = _int_array_key(enemy_ids)
		nation_enemy_sets[nation_id] = enemy_set
	var context := {
		"nation_enemy_ids": nation_enemy_ids,
		"nation_enemy_signatures": nation_enemy_signatures,
		"nation_enemy_sets": nation_enemy_sets,
	}
	connectivity_cache["__gate_build_context"] = context
	return context


static func _merge_sorted_unique_int_arrays(
	left: Array,
	right: Array
) -> Array[int]:
	var result: Array[int] = []
	var left_index := 0
	var right_index := 0
	while left_index < left.size() and right_index < right.size():
		var left_value := int(left[left_index])
		var right_value := int(right[right_index])
		if left_value == right_value:
			result.append(left_value)
			left_index += 1
			right_index += 1
		elif left_value < right_value:
			result.append(left_value)
			left_index += 1
		else:
			result.append(right_value)
			right_index += 1
	while left_index < left.size():
		result.append(int(left[left_index]))
		left_index += 1
	while right_index < right.size():
		result.append(int(right[right_index]))
		right_index += 1
	return result


static func _connectivity_union_context(
	state: GameState,
	graph: Dictionary,
	nation_a: int,
	nation_b: int,
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	connectivity_cache: Dictionary,
	gate_build_context: Dictionary = {}
) -> Dictionary:
	if not gate_build_context.is_empty():
		var union_contexts := (
			connectivity_cache.get("__union_contexts", {}) as Dictionary
		)
		if not connectivity_cache.has("__union_contexts"):
			connectivity_cache["__union_contexts"] = union_contexts
		var nation_enemy_ids: Array = gate_build_context["nation_enemy_ids"]
		var nation_enemy_signatures: Array = (
			gate_build_context["nation_enemy_signatures"]
		)
		var nation_enemy_sets: Array = gate_build_context["nation_enemy_sets"]
		var signature_a := str(nation_enemy_signatures[nation_a])
		var signature_b := str(nation_enemy_signatures[nation_b])
		var enemy_set := {}
		var signature := ""
		if signature_a == signature_b:
			signature = signature_a
			enemy_set = (nation_enemy_sets[nation_a] as Dictionary).duplicate()
		elif signature_a.is_empty():
			signature = signature_b
			enemy_set = (nation_enemy_sets[nation_b] as Dictionary).duplicate()
		elif signature_b.is_empty():
			signature = signature_a
			enemy_set = (nation_enemy_sets[nation_a] as Dictionary).duplicate()
		else:
			var enemy_ids := _merge_sorted_unique_int_arrays(
				nation_enemy_ids[nation_a] as Array,
				nation_enemy_ids[nation_b] as Array
			)
			signature = _int_array_key(enemy_ids)
			for enemy_id in enemy_ids:
				enemy_set[enemy_id] = true
		if union_contexts.has(signature):
			return union_contexts[signature] as Dictionary
		_connectivity_gate_signature_context_builds += 1
		_candidate_connectivity_union_graph_builds += 1
		var allowed := _allowed_city_mask_for_enemy_union(state, enemy_set)
		var blocked_edges := _blocked_edges_for_enemy_union(
			enemy_set, occupied_edges
		)
		var component_ids := _build_connectivity_components(
			state, graph, allowed, besieged, blocked_edges
		)
		var signature_context := {
			"allowed": allowed,
			"blocked_edges": blocked_edges,
			"component_ids": component_ids,
		}
		union_contexts[signature] = signature_context
		return signature_context
	var union_contexts := (
		connectivity_cache.get("__union_contexts", {}) as Dictionary
	)
	if not connectivity_cache.has("__union_contexts"):
		connectivity_cache["__union_contexts"] = union_contexts
	var signature_info := _enemy_union_signature_info(
		state, nation_a, nation_b
	)
	var signature := str(signature_info["signature"])
	if union_contexts.has(signature):
		return union_contexts[signature] as Dictionary
	_candidate_connectivity_union_graph_builds += 1
	var enemy_set: Dictionary = signature_info["enemy_set"]
	var allowed := _allowed_city_mask_for_enemy_union(state, enemy_set)
	var blocked_edges := _blocked_edges_for_enemy_union(
		enemy_set, occupied_edges
	)
	var component_ids := _build_connectivity_components(
		state, graph, allowed, besieged, blocked_edges
	)
	var context := {
		"allowed": allowed,
		"blocked_edges": blocked_edges,
		"component_ids": component_ids,
	}
	union_contexts[signature] = context
	return context


static func _enemy_union_signature_info(
	_state: GameState, _nation_a: int, _nation_b: int
) -> Dictionary:
	var enemy_ids: Array[int] = []
	var enemy_set := {}
	return {
		"signature": _int_array_key(enemy_ids),
		"enemy_set": enemy_set,
	}


static func _allowed_city_mask_for_enemy_union(
	state: GameState, _enemy_set: Dictionary
) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(state.cities.size())
	result.fill(0)
	for city in state.cities:
		if city.id < 0 or city.id >= result.size():
			continue
		var owner := city.owner_nation
		if (
			owner >= 0 and owner < state.nations.size()
		):
			result[city.id] = 1
	return result


static func _blocked_edges_for_enemy_union(
	enemy_set: Dictionary,
	occupied_edges: Array[Dictionary]
) -> Dictionary:
	var result := {}
	for record in occupied_edges:
		var owner := int(record["owner"])
		if enemy_set.has(owner):
			result[int(record["edge_key"])] = true
	return result


static func _build_connectivity_components(
	state: GameState,
	graph: Dictionary,
	allowed: PackedByteArray,
	besieged: Dictionary,
	blocked_edges: Dictionary
) -> PackedInt32Array:
	var component_ids := PackedInt32Array()
	component_ids.resize(state.cities.size())
	for city_id in range(component_ids.size()):
		component_ids[city_id] = -1
	var adjacency: Array = graph["adjacency"]
	var edge_lookup: Dictionary = graph["edge_lookup"]
	var queue: Array[int] = []
	var next_component_id := 0
	for city_id in range(state.cities.size()):
		if (
			city_id >= allowed.size() or allowed[city_id] == 0
			or besieged.has(city_id)
			or component_ids[city_id] >= 0
		):
			continue
		queue.clear()
		queue.append(city_id)
		component_ids[city_id] = next_component_id
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			var neighbors: Array[int] = adjacency[current]
			for neighbor in neighbors:
				if (
					neighbor < 0 or neighbor >= component_ids.size()
					or component_ids[neighbor] >= 0
					or neighbor >= allowed.size() or allowed[neighbor] == 0
					or besieged.has(neighbor)
				):
					continue
				var edge_key := _edge_key(current, neighbor)
				var edge: Edge = edge_lookup.get(edge_key, null)
				if (
					edge == null or edge.max_manpower <= 0
					or blocked_edges.has(edge_key)
				):
					continue
				component_ids[neighbor] = next_component_id
				queue.append(neighbor)
		next_component_id += 1
	return component_ids


static func _has_operational_connection(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	destinations: Array[int],
	allowed: PackedByteArray,
	besieged: Dictionary,
	blocked_edges: Dictionary,
	connectivity_cache: Dictionary
) -> bool:
	_candidate_connectivity_queries += 1
	var valid_sources: Array[int] = []
	for source in sources:
		if (
			source >= 0 and source < state.cities.size()
			and not valid_sources.has(source)
		):
			valid_sources.append(source)
	valid_sources.sort()
	var cache_key := "%s:%s:%s" % [
		_int_array_key(valid_sources), _byte_mask_key(allowed),
		_operational_block_key(besieged, blocked_edges, allowed),
	]
	var reachable: PackedByteArray
	var active_sources := {}
	if connectivity_cache.has(cache_key):
		var cached: Dictionary = connectivity_cache[cache_key]
		reachable = cached["reachable"]
		active_sources = cached["active_sources"]
	else:
		_candidate_connectivity_searches += 1
		reachable = PackedByteArray()
		reachable.resize(state.cities.size())
		reachable.fill(0)
		var queue: Array[int] = []
		for source in valid_sources:
			if (
				source >= allowed.size() or allowed[source] == 0
				or besieged.has(source)
			):
				continue
			reachable[source] = 1
			queue.append(source)
			active_sources[source] = true
		var adjacency: Array = graph["adjacency"]
		var edge_lookup: Dictionary = graph["edge_lookup"]
		var head := 0
		while head < queue.size():
			var city_id := queue[head]
			head += 1
			var neighbors: Array[int] = adjacency[city_id]
			for neighbor in neighbors:
				if (
					reachable[neighbor] != 0
					or neighbor >= allowed.size() or allowed[neighbor] == 0
					or besieged.has(neighbor)
				):
					continue
				var edge_key := _edge_key(city_id, neighbor)
				var edge: Edge = edge_lookup.get(edge_key, null)
				if (
					edge == null or edge.max_manpower <= 0
					or blocked_edges.has(edge_key)
				):
					continue
				reachable[neighbor] = 1
				queue.append(neighbor)
		connectivity_cache[cache_key] = {
			"reachable": reachable,
			"active_sources": active_sources,
		}
	for destination in destinations:
		if (
			destination >= 0 and destination < reachable.size()
			and reachable[destination] != 0
			and not active_sources.has(destination)
		):
			return true
	_candidate_connectivity_rejections += 1
	return false


static func _owned_trade_cities(
	state: GameState, nation_id: int, include_docks: bool
) -> Array[int]:
	var result: Array[int] = []
	for city in state.cities:
		if (
			city.owner_nation == nation_id
			and (include_docks or not city.is_dock)
		):
			result.append(city.id)
	result.sort()
	return result


static func _international_hubs(
	state: GameState,
	nation_id: int,
	policy: int,
	profile_sink: Dictionary = {},
	hub_sort_counts: Array = []
) -> Array[int]:
	if (
		nation_id < 0 or nation_id >= state.nations.size()
		or not state.nations[nation_id].alive
	):
		return [] as Array[int]
	var candidates := _owned_trade_cities(state, nation_id, false)
	_sort_hubs(state, candidates, policy, profile_sink, hub_sort_counts)
	var capital := state.nations[nation_id].capital_city_id
	if capital in candidates:
		candidates.erase(capital)
		candidates.push_front(capital)
	if candidates.size() > INTERNATIONAL_HUBS_PER_NATION:
		candidates.resize(INTERNATIONAL_HUBS_PER_NATION)
	return candidates


static func _sort_hubs(
	state: GameState,
	city_ids: Array[int],
	policy: int,
	profile_sink: Dictionary = {},
	hub_sort_counts: Array = []
) -> void:
	var profile_enabled := bool(profile_sink.get("enabled", false))
	if not profile_enabled:
		city_ids.sort_custom(func(a: int, b: int) -> bool:
			var score_a := _sort_units(_hub_score(state.cities[a], policy))
			var score_b := _sort_units(_hub_score(state.cities[b], policy))
			if score_a != score_b:
				return score_a > score_b
			return a < b
		)
		return
	city_ids.sort_custom(func(a: int, b: int) -> bool:
		if profile_enabled and hub_sort_counts.size() >= 2:
			hub_sort_counts[0] += 2
			hub_sort_counts[1] += 2
		var score_a := _sort_units(_hub_score(state.cities[a], policy))
		var score_b := _sort_units(_hub_score(state.cities[b], policy))
		if score_a != score_b:
			return score_a > score_b
		return a < b
	)


static func _hub_score(city: City, policy: int) -> float:
	var gold_weight := 3.0 if policy == Policy.GOLD else 1.5
	var food_weight := 0.020 if policy == Policy.FOOD else 0.008
	var score := (
		float(maxi(city.gold_per_month, 0)) * gold_weight
		+ float(maxi(city.food_per_half_year, 0)) * food_weight
	)
	if city.is_capital:
		score += 12.0
	if city.has_warehouse:
		score += 8.0
	if city.is_port_market:
		score += 7.0
	if city.is_crossroads:
		score += 5.0
	if city.is_food_hub:
		score += 8.0 if policy == Policy.FOOD else 3.0
	return score


static func _derive_route(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	destinations: Array[int],
	nation_a: int,
	nation_b: int,
	international: bool,
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	field_cache: Dictionary,
	derive_operational: bool = true,
	profile_sink: Dictionary = {},
	shared_operational_fields: Dictionary = {},
	shared_graph_fingerprint: PackedByteArray = PackedByteArray(),
	shared_operational_enabled: bool = false,
	party_context: Dictionary = {}
) -> Dictionary:
	var domestic_profile_enabled := (
		not international and bool(profile_sink.get("enabled", false))
	)
	var international_profile_enabled := (
		international and bool(profile_sink.get("enabled", false))
	)
	var phase_started := (
		Time.get_ticks_usec() if (
			domestic_profile_enabled or international_profile_enabled
		) else 0
	)
	var allowed := (
		_international_allowed_mask(party_context, nation_a, nation_b)
		if international and not party_context.is_empty()
		else _allowed_city_mask(state, nation_a, nation_b)
	)
	var ideal_allowed := _ideal_city_mask(state)
	var blocked_edges := (
		_international_blocked_edges(party_context, nation_a, nation_b)
		if international and not party_context.is_empty()
		else _blocked_edges_for_parties(
			state, nation_a, nation_b, occupied_edges
		)
	)
	var selection: Dictionary
	if not international:
		var ideal_field := _get_domestic_preferred_endpoint_field(
			state, graph, sources, ideal_allowed, false, {}, {}, field_cache
		)
		selection = _select_preferred_endpoints_from_field(
			state, sources, destinations, ideal_field
		)
	else:
		var ideal_field_result := _get_preferred_endpoint_field_with_stats(
			state, graph, sources, ideal_allowed, false, {}, {},
			field_cache
		)
		if international_profile_enabled:
			_accumulate_profile_sink(
				profile_sink,
				"international_route_ideal_lookup",
				Time.get_ticks_usec() - phase_started
			)
			_accumulate_profile_sink(
				profile_sink,
				"international_route_ideal_lookup_builds",
				int(ideal_field_result.get("builds", 0))
			)
			_accumulate_profile_sink(
				profile_sink,
				"international_route_ideal_lookup_local_hits",
				int(ideal_field_result.get("local_hits", 0))
			)
			_accumulate_profile_sink(
				profile_sink,
				"international_route_ideal_lookup_source_sets",
				int(ideal_field_result.get("source_sets", 0))
			)
			phase_started = Time.get_ticks_usec()
		selection = _select_preferred_endpoints_from_field(
			state, sources, destinations, ideal_field_result["field"]
		)
	if domestic_profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"domestic_context",
			Time.get_ticks_usec() - phase_started
		)
		phase_started = Time.get_ticks_usec()
	elif international_profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"international_route_endpoint_select",
			Time.get_ticks_usec() - phase_started
		)
		phase_started = Time.get_ticks_usec()
	var source := int(selection["source"])
	var destination := int(selection["destination"])
	var preferred_path: Array[int] = selection["path"]
	var preferred_cost := float(selection["cost"])
	var operational := {
		"source": source, "destination": destination,
		"path": [] as Array[int], "cost": UNREACHABLE_COST,
	}
	if derive_operational:
		if not international:
			var operational_field := _get_domestic_preferred_endpoint_field(
				state, graph, sources, allowed, true, besieged, blocked_edges,
				field_cache
			)
			operational = _select_preferred_endpoints_from_field(
				state, sources, destinations, operational_field
			)
		else:
			var operational_field_result := (
				_get_shared_operational_endpoint_field_with_stats(
					state, graph, sources, allowed, true,
					besieged, blocked_edges, field_cache,
					shared_operational_fields, shared_graph_fingerprint,
					shared_operational_enabled
				)
			)
			if international_profile_enabled:
				_accumulate_profile_sink(
					profile_sink,
					"international_route_operational_field",
					Time.get_ticks_usec() - phase_started
				)
				_accumulate_profile_sink(
					profile_sink,
					"international_route_operational_field_builds",
					int(operational_field_result.get("builds", 0))
				)
				_accumulate_profile_sink(
					profile_sink,
					"international_route_operational_field_local_hits",
					int(operational_field_result.get("local_hits", 0))
				)
				_accumulate_profile_sink(
					profile_sink,
					"international_route_operational_field_source_sets",
					int(operational_field_result.get("source_sets", 0))
				)
				phase_started = Time.get_ticks_usec()
			operational = _select_preferred_endpoints_from_field(
				state, sources, destinations,
				operational_field_result["field"]
			)
	if domestic_profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"domestic_route_select",
			Time.get_ticks_usec() - phase_started
		)
	elif international_profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"international_route_endpoint_select",
			Time.get_ticks_usec() - phase_started
		)
	var operational_source := int(operational["source"])
	var operational_destination := int(operational["destination"])
	var operational_path: Array[int] = operational["path"]
	var operational_cost := float(operational["cost"])

	var status := RouteStatus.BLOCKED
	var city_path: Array[int] = []
	if not operational_path.is_empty():
		source = operational_source
		destination = operational_destination
		city_path = operational_path
		status = (
			RouteStatus.ACTIVE
			if (
				preferred_path.is_empty()
				or (operational_source == int(selection["source"])
				and operational_destination == int(selection["destination"])
				and operational_path == preferred_path)
			)
			else RouteStatus.REROUTED
		)
	elif not preferred_path.is_empty():
		city_path = preferred_path

	if domestic_profile_enabled or international_profile_enabled:
		phase_started = Time.get_ticks_usec()
	var obstruction := _first_obstruction(
		state, graph, preferred_path, allowed, besieged, blocked_edges
	)
	if (
		status == RouteStatus.BLOCKED
		and str(obstruction["reason"]).is_empty()
	):
		obstruction["reason"] = "unreachable"
	var route_cost := (
		operational_cost
		if operational_cost >= 0.0 else preferred_cost
	)
	if route_cost >= 0.0:
		route_cost = _quantize_cost(route_cost)
	var details := _path_details(state, graph, city_path, status)
	var preferred_details := _path_details(
		state, graph, preferred_path
	)
	if domestic_profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"domestic_route_explain",
			Time.get_ticks_usec() - phase_started
		)
		phase_started = Time.get_ticks_usec()
	elif international_profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"international_route_explain_details",
			Time.get_ticks_usec() - phase_started
		)
		phase_started = Time.get_ticks_usec()
	var route := {
		"id": -1,
		"international": international,
		"kind": "international" if international else "domestic",
		"nation_a": nation_a,
		"nation_b": nation_b,
		"source": source,
		"destination": destination,
		"source_city": source,
		"destination_city": destination,
		"city_path": city_path,
		"preferred_city_path": preferred_path,
		"preferred_transport_cost": (
			_quantize_cost(preferred_cost)
			if preferred_cost >= 0.0 else UNREACHABLE_COST
		),
		"edge_keys": details["edge_keys"],
		"bottleneck": details["bottleneck"],
		"bottleneck_capacity": details["bottleneck"],
		"transport_cost": route_cost,
		"status": status,
		"blocked_reason": obstruction["reason"],
		"blocked_city": obstruction["city"],
		"blocked_edge_key": obstruction["edge_key"],
		"uses_water": details["uses_water"],
		"preferred_uses_water": preferred_details["uses_water"],
		"dock_count": details["dock_count"],
		"gold": 0,
		"gold_tax": 0,
		"gold_to_a": 0,
		"gold_to_b": 0,
		"gold_a": 0,
		"gold_b": 0,
		"transit_gold": 0,
		"city_gold_bonus": {},
		"food": 0,
		"food_transfer": 0,
		"food_exporter": -1,
		"food_importer": -1,
		"food_source_city": -1,
		"food_destination_city": -1,
		"food_cost": 0,
		"food_cost_gold": 0,
	}
	if domestic_profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"domestic_route_materialize",
			Time.get_ticks_usec() - phase_started
		)
	elif international_profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"international_route_materialize",
			Time.get_ticks_usec() - phase_started
		)
	return route


static func _derive_route_from_precomputed_context(
	state: GameState,
	graph: Dictionary,
	context: Dictionary,
	destination: int,
	profile_sink: Dictionary = {}
) -> Dictionary:
	_domestic_route_queries += 1
	var nation_id := int(context["nation_id"])
	var sources: Array[int] = context["sources"]
	var profile_enabled := bool(profile_sink.get("enabled", false))
	var phase_started := (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	var selection := _select_preferred_endpoints_from_field(
		state, sources, [destination] as Array[int], context["ideal_field"]
	)
	var source := int(selection["source"])
	var preferred_destination := int(selection["destination"])
	var preferred_path: Array[int] = selection["path"]
	var preferred_cost := float(selection["cost"])
	var operational := _select_preferred_endpoints_from_field(
		state, sources, [destination] as Array[int],
		context["operational_field"]
	)
	if profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"domestic_route_select",
			Time.get_ticks_usec() - phase_started
		)
	var operational_source := int(operational["source"])
	var operational_destination := int(operational["destination"])
	var operational_path: Array[int] = operational["path"]
	var operational_cost := float(operational["cost"])

	var status := RouteStatus.BLOCKED
	var city_path: Array[int] = []
	if not operational_path.is_empty():
		source = operational_source
		preferred_destination = operational_destination
		city_path = operational_path
		status = (
			RouteStatus.ACTIVE
			if (
				preferred_path.is_empty()
				or (operational_source == int(selection["source"])
				and operational_destination == int(selection["destination"])
				and operational_path == preferred_path)
			)
			else RouteStatus.REROUTED
		)
	elif not preferred_path.is_empty():
		city_path = preferred_path

	var allowed: PackedByteArray = context["allowed"]
	var blocked_edges: Dictionary = context["blocked_edges"]
	var besieged: Dictionary = context["besieged"]
	if profile_enabled:
		phase_started = Time.get_ticks_usec()
	var obstruction := _first_obstruction(
		state, graph, preferred_path, allowed, besieged, blocked_edges
	)
	if (
		status == RouteStatus.BLOCKED
		and str(obstruction["reason"]).is_empty()
	):
		obstruction["reason"] = "unreachable"
	var route_cost := (
		operational_cost
		if operational_cost >= 0.0 else preferred_cost
	)
	if route_cost >= 0.0:
		route_cost = _quantize_cost(route_cost)
	var details := _path_details(state, graph, city_path, status)
	var preferred_details := _path_details(
		state, graph, preferred_path
	)
	if profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"domestic_route_explain",
			Time.get_ticks_usec() - phase_started
		)
		phase_started = Time.get_ticks_usec()
	var route := {
		"id": -1,
		"international": false,
		"kind": "domestic",
		"nation_a": nation_id,
		"nation_b": nation_id,
		"source": source,
		"destination": preferred_destination,
		"source_city": source,
		"destination_city": preferred_destination,
		"city_path": city_path,
		"preferred_city_path": preferred_path,
		"preferred_transport_cost": (
			_quantize_cost(preferred_cost)
			if preferred_cost >= 0.0 else UNREACHABLE_COST
		),
		"edge_keys": details["edge_keys"],
		"bottleneck": details["bottleneck"],
		"bottleneck_capacity": details["bottleneck"],
		"transport_cost": route_cost,
		"status": status,
		"blocked_reason": obstruction["reason"],
		"blocked_city": obstruction["city"],
		"blocked_edge_key": obstruction["edge_key"],
		"uses_water": details["uses_water"],
		"preferred_uses_water": preferred_details["uses_water"],
		"dock_count": details["dock_count"],
		"gold": 0,
		"gold_tax": 0,
		"gold_to_a": 0,
		"gold_to_b": 0,
		"gold_a": 0,
		"gold_b": 0,
		"transit_gold": 0,
		"city_gold_bonus": {},
		"food": 0,
		"food_transfer": 0,
		"food_exporter": -1,
		"food_importer": -1,
		"food_source_city": -1,
		"food_destination_city": -1,
		"food_cost": 0,
		"food_cost_gold": 0,
	}
	if profile_enabled:
		_accumulate_profile_sink(
			profile_sink,
			"domestic_route_materialize",
			Time.get_ticks_usec() - phase_started
		)
	return route


static func _accumulate_profile_sink(
	profile_sink: Dictionary,
	key: String,
	elapsed_usec: int
) -> void:
	if elapsed_usec <= 0:
		return
	profile_sink[key] = int(profile_sink.get(key, 0)) + elapsed_usec


static func _select_preferred_endpoints_from_field(
	state: GameState,
	sources: Array[int],
	destinations: Array[int],
	field: Dictionary,
	reconstruct_path: bool = true
) -> Dictionary:
	var best_source := -1
	var best_destination := -1
	var best_cost_units := INF_COST_UNITS
	var best_path: Array[int] = []
	var distances: PackedInt64Array = field["dist"]
	var origins: PackedInt32Array = field["origin"]
	var prev: PackedInt32Array = field["prev"]
	for destination in destinations:
		if (
			destination < 0 or destination >= distances.size()
			or distances[destination] >= INF_COST_UNITS
			or origins[destination] < 0
			or origins[destination] == destination
		):
			continue
		var source := origins[destination]
		var cost_units := distances[destination]
		if (
			cost_units < best_cost_units
			or (cost_units == best_cost_units and (
				best_source < 0 or source < best_source
				or (source == best_source and destination < best_destination)
			))
		):
			best_source = source
			best_destination = destination
			best_cost_units = cost_units
			if reconstruct_path:
				best_path = _reconstruct_path(
					prev, source, destination
				)
	if best_source < 0:
		var fallback := _closest_endpoint_pair(state, sources, destinations)
		best_source = fallback.x
		best_destination = fallback.y
	return {
		"source": best_source,
		"destination": best_destination,
		"path": best_path,
		"cost": (
			float(best_cost_units) / float(COST_SCALE)
			if best_cost_units < INF_COST_UNITS else UNREACHABLE_COST
		),
	}


static func _select_preferred_endpoints(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	destinations: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary,
	nation_a: int,
	nation_b: int,
	field_cache: Dictionary,
	reconstruct_path: bool = true,
	count_candidate_dijkstra: bool = false
) -> Dictionary:
	var field := _get_preferred_endpoint_field(
		state, graph, sources, allowed, operational, besieged,
		blocked_edges, field_cache, count_candidate_dijkstra
	)
	return _select_preferred_endpoints_from_field(
		state, sources, destinations, field, reconstruct_path
	)


static func _get_preferred_endpoint_field(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary,
	field_cache: Dictionary,
	count_candidate_dijkstra: bool = false
) -> Dictionary:
	var valid_sources: Array[int] = []
	for source in sources:
		if (
			source >= 0 and source < state.cities.size()
			and not valid_sources.has(source)
		):
			valid_sources.append(source)
	valid_sources.sort()
	var cache_key := _preferred_endpoint_field_cache_key(
		valid_sources, allowed, operational, besieged, blocked_edges
	)
	if field_cache.has(cache_key):
		return field_cache[cache_key]
	if count_candidate_dijkstra:
		_candidate_dijkstra_field_builds += 1
	var field = _dijkstra_field(
		state, graph, valid_sources, allowed, operational,
		besieged, blocked_edges
	)
	field_cache[cache_key] = field
	return field


static func _get_preferred_endpoint_field_with_stats(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary,
	field_cache: Dictionary,
	count_candidate_dijkstra: bool = false
) -> Dictionary:
	var valid_sources: Array[int] = []
	for source in sources:
		if (
			source >= 0 and source < state.cities.size()
			and not valid_sources.has(source)
		):
			valid_sources.append(source)
	valid_sources.sort()
	var cache_key := _preferred_endpoint_field_cache_key(
		valid_sources, allowed, operational, besieged, blocked_edges
	)
	if field_cache.has(cache_key):
		return {
			"field": field_cache[cache_key],
			"builds": 0,
			"local_hits": 1,
			"source_sets": 1,
		}
	if count_candidate_dijkstra:
		_candidate_dijkstra_field_builds += 1
	var field := _dijkstra_field(
		state, graph, valid_sources, allowed, operational,
		besieged, blocked_edges
	)
	field_cache[cache_key] = field
	return {
		"field": field,
		"builds": 1,
		"local_hits": 0,
		"source_sets": 1,
	}


static func _get_domestic_preferred_endpoint_field(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary,
	field_cache: Dictionary
) -> Dictionary:
	var valid_sources: Array[int] = []
	for source in sources:
		if (
			source >= 0 and source < state.cities.size()
			and not valid_sources.has(source)
		):
			valid_sources.append(source)
	valid_sources.sort()
	var cache_key := _preferred_endpoint_field_cache_key(
		valid_sources, allowed, operational, besieged, blocked_edges
	)
	if field_cache.has(cache_key):
		return field_cache[cache_key]
	_domestic_field_builds += 1
	return _get_preferred_endpoint_field(
		state, graph, sources, allowed, operational, besieged,
		blocked_edges, field_cache
	)


static func _get_shared_domestic_ideal_field(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	allowed: PackedByteArray,
	field_cache: Dictionary,
	shared_domestic_ideal_fields: Dictionary,
	shared_graph_fingerprint: PackedByteArray,
	ideal_allowed_key: String
) -> Dictionary:
	var valid_sources: Array[int] = []
	for source in sources:
		if (
			source >= 0 and source < state.cities.size()
			and not valid_sources.has(source)
		):
			valid_sources.append(source)
	valid_sources.sort()
	var local_cache_key := _preferred_endpoint_field_cache_key(
		valid_sources, allowed, false, {}, {}
	)
	if field_cache.has(local_cache_key):
		return {
			"field": field_cache[local_cache_key],
			"cache_hits": 0,
			"cache_misses": 0,
			"cache_builds": 0,
		}
	var shared_cache_enabled := (
		_domestic_ideal_shared_cache_enabled_now()
		and not shared_graph_fingerprint.is_empty()
	)
	if shared_cache_enabled:
		var shared_cache_key := _shared_domestic_ideal_field_cache_key(
			valid_sources, ideal_allowed_key, shared_graph_fingerprint
		)
		if shared_domestic_ideal_fields.has(shared_cache_key):
			var shared_snapshot: Variant = shared_domestic_ideal_fields[
				shared_cache_key
			]
			if shared_snapshot is PackedByteArray:
				var field := _deserialize_preferred_endpoint_field_snapshot(
					shared_snapshot,
					state.cities.size()
				)
				if not field.is_empty():
					_domestic_ideal_shared_cache_hits += 1
					field_cache[local_cache_key] = field
					return {
						"field": field,
						"cache_hits": 1,
						"cache_misses": 0,
						"cache_builds": 0,
					}
			shared_domestic_ideal_fields.erase(shared_cache_key)
		_domestic_ideal_shared_cache_misses += 1
	var field := _get_domestic_preferred_endpoint_field(
		state, graph, sources, allowed, false, {}, {}, field_cache
	)
	if shared_cache_enabled:
		var shared_cache_key := _shared_domestic_ideal_field_cache_key(
			valid_sources, ideal_allowed_key, shared_graph_fingerprint
		)
		if (
			not shared_domestic_ideal_fields.has(shared_cache_key)
			and shared_domestic_ideal_fields.size()
				>= DOMESTIC_IDEAL_SHARED_CACHE_MAX_ENTRIES
		):
			_domestic_ideal_shared_cache_evictions += (
				shared_domestic_ideal_fields.size()
			)
			_domestic_ideal_shared_cache_clears += 1
			shared_domestic_ideal_fields.clear()
		shared_domestic_ideal_fields[shared_cache_key] = (
			_serialize_preferred_endpoint_field_snapshot(field)
		)
		_domestic_ideal_shared_cache_builds += 1
	return {
		"field": field,
		"cache_hits": 0,
		"cache_misses": (1 if shared_cache_enabled else 0),
		"cache_builds": (1 if shared_cache_enabled else 0),
	}


## 国际候选的理想路径只依赖静态路网和本国 hub 集。领土/路网 generation
## 不变时跨 build 复用序列化快照，避免重复执行每国一次全图 Dijkstra。
static func _get_shared_international_ideal_field(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	allowed: PackedByteArray,
	field_cache: Dictionary,
	shared_international_ideal_fields: Dictionary,
	shared_graph_fingerprint: PackedByteArray,
	ideal_allowed_key: String,
	shared_cache_enabled: bool
) -> Dictionary:
	var valid_sources: Array[int] = []
	for source in sources:
		if (
			source >= 0 and source < state.cities.size()
			and not valid_sources.has(source)
		):
			valid_sources.append(source)
	valid_sources.sort()
	var local_cache_key := _preferred_endpoint_field_cache_key(
		valid_sources, allowed, false, {}, {}
	)
	if field_cache.has(local_cache_key):
		return {
			"field": field_cache[local_cache_key],
			"builds": 0, "local_hits": 1, "source_sets": 1,
		}
	# 空缓存也是合法启用态；调用方以 shared_caches 键存在性表达启用。
	var shared_enabled := (
		shared_cache_enabled and not shared_graph_fingerprint.is_empty()
	)
	var shared_key := PackedByteArray()
	if shared_enabled:
		shared_key = var_to_bytes([
			"trade_international_ideal_field_v1",
			valid_sources, ideal_allowed_key, shared_graph_fingerprint,
		])
		if shared_international_ideal_fields.has(shared_key):
			var snapshot: Variant = shared_international_ideal_fields[shared_key]
			# 同一进程内的共享缓存可直接复用已解码字段，避免每个候选伙伴
			# 重复执行 var_to_bytes/bytes_to_var；旧的序列化条目仍兼容读取。
			if snapshot is Dictionary:
				field_cache[local_cache_key] = snapshot
				return {
					"field": snapshot, "builds": 0,
					"local_hits": 1, "source_sets": 1,
				}
			if snapshot is PackedByteArray:
				var cached := _deserialize_preferred_endpoint_field_snapshot(
					snapshot, state.cities.size()
				)
				if not cached.is_empty():
					field_cache[local_cache_key] = cached
					return {
						"field": cached, "builds": 0,
						"local_hits": 1, "source_sets": 1,
					}
			shared_international_ideal_fields.erase(shared_key)
	var field := _get_preferred_endpoint_field(
		state, graph, valid_sources, allowed, false, {}, {}, field_cache
	)
	if shared_enabled:
		if (
			not shared_international_ideal_fields.has(shared_key)
			and shared_international_ideal_fields.size()
				>= INTERNATIONAL_IDEAL_SHARED_CACHE_MAX_ENTRIES
		):
			shared_international_ideal_fields.clear()
		shared_international_ideal_fields[shared_key] = field
	return {
		"field": field, "builds": 1,
		"local_hits": 0, "source_sets": 1,
	}


static func _get_shared_operational_endpoint_field(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	allowed: PackedByteArray,
	besieged: Dictionary,
	blocked_edges: Dictionary,
	field_cache: Dictionary,
	shared_operational_fields: Dictionary,
	shared_graph_fingerprint: PackedByteArray,
	shared_cache_enabled: bool
) -> Dictionary:
	return (
		_get_shared_operational_endpoint_field_with_stats(
			state, graph, sources, allowed, true, besieged, blocked_edges,
			field_cache, shared_operational_fields, shared_graph_fingerprint,
			shared_cache_enabled
		)["field"] as Dictionary
	)


## 跨贸易结构重建复用精确匹配的 operational Dijkstra。正式建网只由静态
## 路网、source 和允许城市 mask 决定；参数仍保留给底层寻路等价门禁。
static func _get_shared_operational_endpoint_field_with_stats(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary,
	field_cache: Dictionary,
	shared_operational_fields: Dictionary,
	shared_graph_fingerprint: PackedByteArray,
	shared_cache_enabled: bool
) -> Dictionary:
	var valid_sources: Array[int] = []
	for source in sources:
		if (
			source >= 0 and source < state.cities.size()
			and not valid_sources.has(source)
		):
			valid_sources.append(source)
	valid_sources.sort()
	var local_key := _preferred_endpoint_field_cache_key(
		valid_sources, allowed, operational, besieged, blocked_edges
	)
	if field_cache.has(local_key):
		return {
			"field": field_cache[local_key],
			"builds": 0, "local_hits": 1, "source_sets": 1,
		}
	var shared_enabled := (
		shared_cache_enabled and not shared_graph_fingerprint.is_empty()
	)
	var shared_key := PackedByteArray()
	if shared_enabled:
		shared_key = var_to_bytes([
			"trade_operational_field_v1", valid_sources,
			_byte_mask_key(allowed),
			_operational_block_key(besieged, blocked_edges, allowed),
			shared_graph_fingerprint,
		])
		if shared_operational_fields.has(shared_key):
			var snapshot: Variant = shared_operational_fields[shared_key]
			if snapshot is PackedByteArray:
				var cached := _deserialize_preferred_endpoint_field_snapshot(
					snapshot, state.cities.size()
				)
				if not cached.is_empty():
					field_cache[local_key] = cached
					return {
						"field": cached, "builds": 0,
						"local_hits": 1, "source_sets": 1,
					}
			shared_operational_fields.erase(shared_key)
	var field := _get_preferred_endpoint_field(
		state, graph, valid_sources, allowed, operational, besieged,
		blocked_edges, field_cache
	)
	if shared_enabled:
		if (
			not shared_operational_fields.has(shared_key)
			and shared_operational_fields.size()
				>= OPERATIONAL_SHARED_CACHE_MAX_ENTRIES
		):
			shared_operational_fields.clear()
		shared_operational_fields[shared_key] = (
			_serialize_preferred_endpoint_field_snapshot(field)
		)
	return {
		"field": field, "builds": 1,
		"local_hits": 0, "source_sets": 1,
	}


static func _preferred_endpoint_field_cache_key(
	valid_sources: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary
) -> String:
	return "%d:%s:%s:%s" % [
		1 if operational else 0, _int_array_key(valid_sources),
		_byte_mask_key(allowed),
		(
			_operational_block_key(besieged, blocked_edges, allowed)
			if operational else ""
		),
	]


static func _shared_domestic_ideal_field_cache_key(
	valid_sources: Array[int],
	ideal_allowed_key: String,
	graph_fingerprint: PackedByteArray
) -> PackedByteArray:
	return var_to_bytes([
		"trade_domestic_ideal_field_v1",
		valid_sources,
		ideal_allowed_key,
		graph_fingerprint,
	])


static func _serialize_preferred_endpoint_field_snapshot(
	field: Dictionary
) -> PackedByteArray:
	return var_to_bytes([
		field.get("dist", PackedInt64Array()),
		field.get("prev", PackedInt32Array()),
		field.get("origin", PackedInt32Array()),
	])


static func _deserialize_preferred_endpoint_field_snapshot(
	snapshot: PackedByteArray,
	expected_city_count: int
) -> Dictionary:
	var payload: Variant = bytes_to_var(snapshot)
	if not payload is Array:
		return {}
	var values: Array = payload
	if values.size() != 3:
		return {}
	var dist_result := _coerce_packed_int64_array(values[0])
	var prev_result := _coerce_packed_int32_array(values[1])
	var origin_result := _coerce_packed_int32_array(values[2])
	if (
		not bool(dist_result.get("ok", false))
		or not bool(prev_result.get("ok", false))
		or not bool(origin_result.get("ok", false))
	):
		return {}
	var dist: PackedInt64Array = dist_result["value"]
	var prev: PackedInt32Array = prev_result["value"]
	var origin: PackedInt32Array = origin_result["value"]
	if (
		dist.size() != expected_city_count
		or prev.size() != expected_city_count
		or origin.size() != expected_city_count
	):
		return {}
	return {
		"dist": dist,
		"prev": prev,
		"origin": origin,
	}


static func _coerce_packed_int64_array(value: Variant) -> Dictionary:
	if value is PackedInt64Array:
		return {
			"ok": true,
			"value": (value as PackedInt64Array).duplicate(),
		}
	if value is PackedInt32Array:
		var widened := PackedInt64Array()
		for item in value as PackedInt32Array:
			widened.append(int(item))
		return {"ok": true, "value": widened}
	if not value is Array:
		return {"ok": false, "value": PackedInt64Array()}
	var result := PackedInt64Array()
	for item in value as Array:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT]:
			return {"ok": false, "value": PackedInt64Array()}
		result.append(int(item))
	return {"ok": true, "value": result}


static func _coerce_packed_int32_array(value: Variant) -> Dictionary:
	if value is PackedInt32Array:
		return {
			"ok": true,
			"value": (value as PackedInt32Array).duplicate(),
		}
	if not value is Array:
		return {"ok": false, "value": PackedInt32Array()}
	var result := PackedInt32Array()
	for item in value as Array:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT]:
			return {"ok": false, "value": PackedInt32Array()}
		result.append(int(item))
	return {"ok": true, "value": result}


static func _int_array_key(values: Array[int]) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return ",".join(parts)


static func _byte_mask_key(values: PackedByteArray) -> String:
	var result := ""
	var accumulator := 0
	var bit := 0
	for value in values:
		if value != 0:
			accumulator |= 1 << bit
		bit += 1
		if bit == 30:
			result += "%x," % accumulator
			accumulator = 0
			bit = 0
	return result + "%x" % accumulator


static func _operational_block_key(
	besieged: Dictionary,
	blocked_edges: Dictionary,
	allowed: PackedByteArray = PackedByteArray()
) -> String:
	var city_ids := besieged.keys()
	city_ids.sort()
	var edge_ids := blocked_edges.keys()
	edge_ids.sort()
	var result := "c"
	for city_id in city_ids:
		var normalized_city := int(city_id)
		if (
			not allowed.is_empty()
			and (
				normalized_city < 0
				or normalized_city >= allowed.size()
				or allowed[normalized_city] == 0
			)
		):
			continue
		result += "%d," % normalized_city
	result += "e"
	for edge_key in edge_ids:
		var normalized_edge := int(edge_key)
		if not allowed.is_empty():
			var city_a := normalized_edge >> 32
			var city_b := normalized_edge & 0xffffffff
			if (
				city_a < 0 or city_a >= allowed.size()
				or city_b < 0 or city_b >= allowed.size()
				or allowed[city_a] == 0 or allowed[city_b] == 0
			):
				continue
		result += "%d," % normalized_edge
	return result


static func _closest_endpoint_pair(
	state: GameState, sources: Array[int], destinations: Array[int]
) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance_units := INF_COST_UNITS
	for source in sources:
		if source < 0 or source >= state.cities.size():
			continue
		for destination in destinations:
			if (
				destination < 0 or destination >= state.cities.size()
				or source == destination
			):
				continue
			var delta := (
				state.cities[source].map_position
				- state.cities[destination].map_position
			)
			delta.x *= maxf(state.map_aspect_ratio, 0.01)
			var distance_units := _sort_units(delta.length_squared())
			if (
				distance_units < best_distance_units
				or (
					distance_units == best_distance_units
					and (
						best.x < 0 or source < best.x
						or (source == best.x and destination < best.y)
					)
				)
			):
				best = Vector2i(source, destination)
				best_distance_units = distance_units
	return best


## operational=false 是“理想商路”：忽略道路容量关闭；operational=true
## 使用当前道路容量。战争、围城和军队位置不会作为正式建网输入。
static func _dijkstra_field(
	state: GameState,
	graph: Dictionary,
	starts: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary
) -> Dictionary:
	var city_count := state.cities.size()
	var dist := PackedInt64Array()
	dist.resize(city_count)
	dist.fill(INF_COST_UNITS)
	var prev := PackedInt32Array()
	prev.resize(city_count)
	prev.fill(-1)
	var origin := PackedInt32Array()
	origin.resize(city_count)
	origin.fill(-1)
	var visited := PackedByteArray()
	visited.resize(city_count)
	visited.fill(0)
	var heap: Array[Vector3i] = []
	for start in starts:
		if (
			start < 0 or start >= city_count
			or start >= allowed.size() or allowed[start] == 0
			or (operational and besieged.has(start))
		):
			continue
		dist[start] = 0
		origin[start] = start
		_heap_push(heap, Vector3i(0, start, start))
	if heap.is_empty():
		return {"dist": dist, "prev": prev, "origin": origin}
	var adjacency: Array = graph["adjacency"]
	var edge_lookup: Dictionary = graph["edge_lookup"]
	while not heap.is_empty():
		var entry := _heap_pop(heap)
		var known_cost := entry.x
		var city_id := entry.z
		if (
			visited[city_id] != 0
			or known_cost != dist[city_id]
			or entry.y != origin[city_id]
		):
			continue
		visited[city_id] = 1
		var neighbors: Array[int] = adjacency[city_id]
		for neighbor in neighbors:
			if (
				visited[neighbor] != 0
				or neighbor >= allowed.size() or allowed[neighbor] == 0
				or (operational and besieged.has(neighbor))
			):
				continue
			var edge_key := _edge_key(city_id, neighbor)
			var edge: Edge = edge_lookup.get(edge_key, null)
			if edge == null:
				continue
			if operational and (
				edge.max_manpower <= 0 or blocked_edges.has(edge_key)
			):
				continue
			var edge_cost := _edge_transport_cost_units(edge, operational)
			var candidate := known_cost + edge_cost
			var candidate_origin := origin[city_id]
			var improves := candidate < dist[neighbor]
			var tie_improves := (
				candidate == dist[neighbor]
				and (origin[neighbor] < 0 or candidate_origin < origin[neighbor]
				or (candidate_origin == origin[neighbor]
				and (prev[neighbor] < 0 or city_id < prev[neighbor])))
			)
			if improves or tie_improves:
				dist[neighbor] = candidate
				prev[neighbor] = city_id
				origin[neighbor] = candidate_origin
				_heap_push(
					heap, Vector3i(candidate, candidate_origin, neighbor)
				)
	return {"dist": dist, "prev": prev, "origin": origin}


static func _edge_transport_cost(edge: Edge, operational: bool) -> float:
	var capacity := edge.max_manpower
	if not operational and capacity <= 0:
		capacity = maxi(edge.base_max_manpower, MATCHED_LOW_CAPACITY)
	capacity = maxi(capacity, 1)
	var kind_factor := 1.0
	match edge.kind:
		EDGE_KIND_LANDING:
			kind_factor = 1.10
		EDGE_KIND_RIVER:
			kind_factor = 0.72
		EDGE_KIND_SEA:
			kind_factor = 0.62
		_:
			kind_factor = 1.0
	var capacity_factor := sqrt(
		float(MATCHED_STANDARD_CAPACITY) / float(capacity)
	)
	capacity_factor = clampf(capacity_factor, 0.60, 1.60)
	return (
		float(maxi(edge.distance, 1))
		* maxf(edge.travel_time_multiplier, 0.05)
		* kind_factor
		* capacity_factor
		* (1.0 + clampf(edge.danger, 0.0, 1.0) * 0.50)
		+ maxf(edge.supply_loss_multiplier, 0.0) * 0.10
	)


static func _edge_transport_cost_units(edge: Edge, operational: bool) -> int:
	return maxi(
		int(round(_edge_transport_cost(edge, operational) * float(COST_SCALE))),
		1
	)


static func _heap_entry_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


static func _heap_push(heap: Array[Vector3i], entry: Vector3i) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := int((index - 1) / 2)
		if not _heap_entry_less(heap[index], heap[parent]):
			break
		var swap: Vector3i = heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


static func _heap_pop(heap: Array[Vector3i]) -> Vector3i:
	var result: Vector3i = heap[0]
	var tail: Vector3i = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = tail
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var child := left
		if right < heap.size() and _heap_entry_less(heap[right], heap[left]):
			child = right
		if not _heap_entry_less(heap[child], heap[index]):
			break
		var swap: Vector3i = heap[index]
		heap[index] = heap[child]
		heap[child] = swap
		index = child
	return result


static func _reconstruct_path(
	prev: PackedInt32Array, start: int, destination: int
) -> Array[int]:
	var result: Array[int] = []
	if start < 0 or destination < 0 or destination >= prev.size():
		return result
	if start == destination:
		result.append(start)
		return result
	if prev[destination] < 0:
		return result
	var current := destination
	var guard := 0
	while current != start and guard <= prev.size():
		result.push_front(current)
		current = prev[current]
		if current < 0:
			return [] as Array[int]
		guard += 1
	if current != start:
		return [] as Array[int]
	result.push_front(start)
	return result


static func _first_obstruction(
	state: GameState,
	graph: Dictionary,
	preferred_path: Array[int],
	allowed: PackedByteArray,
	besieged: Dictionary,
	blocked_edges: Dictionary
) -> Dictionary:
	for city_id in preferred_path:
		if besieged.has(city_id):
			return {
				"reason": "siege", "city": city_id, "edge_key": -1,
			}
		if city_id >= allowed.size() or allowed[city_id] == 0:
			return {
				"reason": "hostile_territory",
				"city": city_id, "edge_key": -1,
			}
	var edge_lookup: Dictionary = graph["edge_lookup"]
	for index in range(preferred_path.size() - 1):
		var edge_key := _edge_key(
			preferred_path[index], preferred_path[index + 1]
		)
		var edge: Edge = edge_lookup.get(edge_key, null)
		if edge == null or edge.max_manpower <= 0:
			return {
				"reason": "capacity", "city": -1,
				"edge_key": edge_key,
			}
		if blocked_edges.has(edge_key):
			return {
				"reason": "enemy_occupied_edge", "city": -1,
				"edge_key": edge_key,
			}
	return {"reason": "", "city": -1, "edge_key": -1}


static func _path_details(
	state: GameState,
	graph: Dictionary,
	path: Array[int],
	status: int = RouteStatus.ACTIVE
) -> Dictionary:
	var edge_keys: Array[int] = []
	var bottleneck := 0x7fffffff
	var uses_water := false
	var dock_count := 0
	for city_id in path:
		if (
			city_id >= 0 and city_id < state.cities.size()
			and state.cities[city_id].is_dock
		):
			dock_count += 1
	var edge_lookup: Dictionary = graph["edge_lookup"]
	for index in range(path.size() - 1):
		var key := _edge_key(path[index], path[index + 1])
		edge_keys.append(key)
		var edge: Edge = edge_lookup.get(key, null)
		if edge == null:
			bottleneck = 0
			continue
		var capacity := maxi(edge.max_manpower, 0)
		if status == RouteStatus.BLOCKED and capacity <= 0:
			capacity = maxi(edge.base_max_manpower, MATCHED_LOW_CAPACITY)
		bottleneck = mini(bottleneck, capacity)
		uses_water = uses_water or edge.kind in [EDGE_KIND_RIVER, EDGE_KIND_SEA]
	if edge_keys.is_empty():
		bottleneck = 0
	return {
		"edge_keys": edge_keys,
		"bottleneck": bottleneck,
		"uses_water": uses_water,
		"dock_count": dock_count,
	}


static func _quantize_cost(value: float) -> float:
	return float(round(value * 1000.0)) / 1000.0


static func _sortable_cost(value: float) -> float:
	return value if value >= 0.0 else 1000000000.0


static func _sort_units(value: float) -> int:
	if not is_finite(value):
		return INF_COST_UNITS
	return int(round(value * SORT_SCALE))


static func _international_candidate_value(
	state: GameState,
	source: int,
	destination: int,
	transport_cost: float,
	policy_a: int,
	policy_b: int
) -> float:
	if (
		source < 0 or destination < 0
		or source >= state.cities.size() or destination >= state.cities.size()
	):
		return 0.0
	var value := 0.0
	value = (
		_hub_score(state.cities[source], policy_a)
		+ _hub_score(state.cities[destination], policy_b)
	)
	if transport_cost >= 0.0:
		value /= 1.0 + transport_cost * 0.05
	return value


static func _apply_trade_taxes(
	state: GameState,
	routes: Array[Dictionary],
	policies: Array[int],
	city_gold_bonus: Array[int],
	nation_trade_gold: Array[int],
	nation_trade_tax: Array[int]
) -> void:
	for route_index in range(routes.size()):
		var route: Dictionary = routes[route_index]
		if int(route["status"]) == RouteStatus.BLOCKED:
			continue
		var eligible: Array[int] = []
		for city_id in route["city_path"] as Array[int]:
			if (
				city_id >= 0 and city_id < state.cities.size()
				and not state.cities[city_id].is_dock
				and not eligible.has(city_id)
			):
				eligible.append(city_id)
		if eligible.is_empty():
			continue
		var tax := _route_tax_gold(state, route, policies, eligible.size())
		var allocation := _allocate_route_tax(state, route, eligible, tax)
		var gold_a := 0
		var gold_b := 0
		var transit_gold := 0
		for city_id in eligible:
			var bonus := int(allocation.get(city_id, 0))
			city_gold_bonus[city_id] += bonus
			var owner := state.cities[city_id].owner_nation
			if owner >= 0 and owner < nation_trade_gold.size():
				nation_trade_gold[owner] += bonus
				nation_trade_tax[owner] += bonus
			if owner == int(route["nation_a"]):
				gold_a += bonus
			elif owner == int(route["nation_b"]):
				gold_b += bonus
			else:
				transit_gold += bonus
		if not bool(route["international"]):
			gold_b = 0
		route["gold"] = tax
		route["gold_tax"] = tax
		route["gold_a"] = gold_a
		route["gold_b"] = gold_b
		route["gold_to_a"] = gold_a
		route["gold_to_b"] = gold_b
		route["transit_gold"] = transit_gold
		route["city_gold_bonus"] = allocation
		routes[route_index] = route


## 贸易路线及其和平期基准税收属于结构层；战争只在结算层折算实际到账。
## 按城市逐项取整，保证 route、city 与 nation 三个公开口径始终守恒。
static func _apply_wartime_trade_gold(
	state: GameState,
	routes: Array,
	city_gold_bonus: Array[int],
	nation_trade_gold: Array[int],
	nation_trade_tax: Array[int],
	mutate_routes: bool
) -> void:
	var wartime := wartime_nation_mask(state)
	if not wartime.has(1):
		return
	var base_nation_trade_gold := nation_trade_gold.duplicate()
	var wartime_floor_sum := _zero_int_array(state.nations.size())
	for route_value in routes:
		var base_route: Dictionary = route_value
		for city_value in (base_route.get("city_gold_bonus", {}) as Dictionary):
			var city_id := int(city_value)
			if city_id < 0 or city_id >= state.cities.size():
				continue
			var owner := state.cities[city_id].owner_nation
			if owner < 0 or owner >= wartime.size() or wartime[owner] == 0:
				continue
			wartime_floor_sum[owner] += int(floor(
				float(maxi(int(base_route["city_gold_bonus"][city_value]), 0))
				* WARTIME_TRADE_GOLD_MULTIPLIER
			))
	var wartime_extra_remaining := _zero_int_array(state.nations.size())
	for nation_id in range(state.nations.size()):
		if wartime[nation_id] == 0:
			continue
		wartime_extra_remaining[nation_id] = maxi(
			int(floor(
				float(base_nation_trade_gold[nation_id])
				* WARTIME_TRADE_GOLD_MULTIPLIER
			)) - wartime_floor_sum[nation_id],
			0
		)
	city_gold_bonus.fill(0)
	nation_trade_gold.fill(0)
	nation_trade_tax.fill(0)
	for route_index in range(routes.size()):
		var route: Dictionary = routes[route_index]
		var base_allocation: Dictionary = route.get("city_gold_bonus", {})
		var adjusted_allocation := {}
		var city_ids := base_allocation.keys()
		city_ids.sort()
		var tax := 0
		var gold_a := 0
		var gold_b := 0
		var transit_gold := 0
		var nation_a := int(route.get("nation_a", -1))
		var nation_b := int(route.get("nation_b", -1))
		for city_value in city_ids:
			var city_id := int(city_value)
			if city_id < 0 or city_id >= state.cities.size():
				continue
			var owner := state.cities[city_id].owner_nation
			var bonus := maxi(int(base_allocation[city_value]), 0)
			if owner >= 0 and owner < wartime.size() and wartime[owner] != 0:
				bonus = int(floor(
					float(bonus) * WARTIME_TRADE_GOLD_MULTIPLIER
				))
				if wartime_extra_remaining[owner] > 0:
					bonus += 1
					wartime_extra_remaining[owner] -= 1
			adjusted_allocation[city_id] = bonus
			tax += bonus
			if city_id < city_gold_bonus.size():
				city_gold_bonus[city_id] += bonus
			if owner >= 0 and owner < nation_trade_gold.size():
				nation_trade_gold[owner] += bonus
				nation_trade_tax[owner] += bonus
			if owner == nation_a:
				gold_a += bonus
			elif owner == nation_b:
				gold_b += bonus
			else:
				transit_gold += bonus
		if not mutate_routes:
			continue
		if not bool(route.get("international", false)):
			gold_b = 0
		route["gold"] = tax
		route["gold_tax"] = tax
		route["gold_a"] = gold_a
		route["gold_b"] = gold_b
		route["gold_to_a"] = gold_a
		route["gold_to_b"] = gold_b
		route["transit_gold"] = transit_gold
		route["city_gold_bonus"] = adjusted_allocation
		routes[route_index] = route


## 一国只要参与任意战争就进入战时贸易口径；多线作战仍只折算一次。
static func wartime_nation_mask(state: GameState) -> PackedByteArray:
	var result := PackedByteArray()
	if state == null:
		return result
	result.resize(state.nations.size())
	result.fill(0)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			if (
				not state.nations[nation_a].alive
				or not state.nations[nation_b].alive
				or not state.is_enemy(nation_a, nation_b)
			):
				continue
			result[nation_a] = 1
			result[nation_b] = 1
	return result


static func _route_tax_gold(
	state: GameState,
	route: Dictionary,
	policies: Array[int],
	eligible_city_count: int
) -> int:
	var source := int(route["source"])
	var destination := int(route["destination"])
	var endpoint_gold := 0
	var endpoint_food := 0
	for city_id in [source, destination]:
		if city_id < 0 or city_id >= state.cities.size():
			continue
		endpoint_gold += maxi(state.cities[city_id].gold_per_month, 0)
		endpoint_food += maxi(state.cities[city_id].food_per_half_year, 0)
	var commerce := (
		2.0 + float(endpoint_gold) * 0.50 + float(endpoint_food) / 600.0
	)
	var bottleneck := maxi(int(route["bottleneck"]), 1)
	var capacity_factor := clampf(
		sqrt(float(bottleneck) / float(TRADE_CAPACITY_UNIT)), 0.65, 2.25
	)
	var cost := maxf(float(route["transport_cost"]), 0.0)
	var distance_factor := 1.0 / (1.0 + cost / 18.0)
	var nation_a := int(route["nation_a"])
	var nation_b := int(route["nation_b"])
	var policy_factor := _gold_policy_factor(policies[nation_a])
	var ruler_factor := _ruler_trade_multiplier(
		state.nations[nation_a]
	)
	if nation_b != nation_a:
		policy_factor = (
			policy_factor + _gold_policy_factor(policies[nation_b])
		) * 0.5
		ruler_factor = (
			ruler_factor + _ruler_trade_multiplier(state.nations[nation_b])
		) * 0.5
	var route_factor := 1.45 if bool(route["international"]) else 1.0
	if bool(route["uses_water"]):
		route_factor *= 1.12
	var raw := int(round(
		commerce * capacity_factor * distance_factor
		* policy_factor * ruler_factor * route_factor
	))
	return maxi(mini(raw, MAX_ROUTE_GOLD), eligible_city_count)


static func _gold_policy_factor(policy: int) -> float:
	match policy:
		Policy.GOLD:
			return 1.35
		Policy.FOOD:
			return 0.85
		Policy.ISOLATION:
			return 0.80
		_:
			return 1.0


static func _ruler_trade_multiplier(nation: Nation) -> float:
	return clampf(RulerProfile.trade_multiplier(nation), 0.25, 4.0)


static func _allocate_route_tax(
	state: GameState,
	route: Dictionary,
	city_ids: Array[int],
	total: int
) -> Dictionary:
	var result := {}
	if city_ids.is_empty() or total <= 0:
		return result
	# 每个沿线非码头城市至少得到 1，余量按枢纽/端点权重最大余数分配。
	for city_id in city_ids:
		result[city_id] = 1
	var remaining := maxi(total - city_ids.size(), 0)
	if remaining <= 0:
		return result
	var weights: Array[int] = []
	var total_weight := 0
	for city_id in city_ids:
		var city := state.cities[city_id]
		var weight := 1
		if city_id in [int(route["source"]), int(route["destination"])]:
			weight += 1
		if city.is_port_market:
			weight += 1
		if city.is_crossroads:
			weight += 1
		weights.append(weight)
		total_weight += weight
	var remainders: Array[Dictionary] = []
	var distributed := 0
	for index in range(city_ids.size()):
		var numerator := remaining * weights[index]
		var share := int(numerator / total_weight)
		result[city_ids[index]] = int(result[city_ids[index]]) + share
		distributed += share
		remainders.append({
			"city": city_ids[index],
			"remainder": numerator % total_weight,
		})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["remainder"]) != int(b["remainder"]):
			return int(a["remainder"]) > int(b["remainder"])
		return int(a["city"]) < int(b["city"])
	)
	for index in range(remaining - distributed):
		var city_id := int(remainders[index]["city"])
		result[city_id] = int(result[city_id]) + 1
	return result


static func _plan_trade_purchases(
	state: GameState,
	policies: Array[int],
	nation_trade_gold: Array[int],
	nation_food_import: Array[int],
	nation_food_cost: Array[int],
	nation_manpower_import: Array[int],
	nation_manpower_cost: Array[int]
) -> void:
	# 简化版 EU4 贸易结算：路线税（贸易节点竞争力→金钱）已在 build_structure
	# 阶段累计进 nation_trade_gold / nation_trade_tax。这里把「钱买粮、钱买人」
	# 落到派生数组：每国用当月贸易金作预算，先补粮再补人，两者都凭空产生
	# （import>0，无 export），不再从他国粮仓抽调库存。价格开关关闭时不买。
	var nation_count := state.nations.size()
	if nation_count <= 0 or not state.trade_price_enabled:
		return
	# 1) 按粮池持有者汇总可用库存与月需，得到共享粮仓的储备缺口。口径与
	#    旧的守恒实现一致：藩属并入 holder，避免被误判为零库存。
	var stock := _zero_int_array(nation_count)
	var configured_warehouse_count := _zero_int_array(nation_count)
	var accessible_warehouse_count := _zero_int_array(nation_count)
	var monthly_manpower_income := _zero_int_array(nation_count)
	for city in state.cities:
		if city.owner_nation >= 0 and city.owner_nation < nation_count:
			monthly_manpower_income[city.owner_nation] += maxi(
				city.manpower_per_month, 0
			)
		if (
			city.has_warehouse and city.owner_nation >= 0
			and city.owner_nation < nation_count
		):
			configured_warehouse_count[city.owner_nation] += 1
			stock[city.owner_nation] += maxi(city.food_storage, 0)
			accessible_warehouse_count[city.owner_nation] += 1
	var pool_holder := _zero_int_array(nation_count)
	for nation in state.nations:
		pool_holder[nation.id] = state.food_pool_holder(nation.id)
	var pooled_stock := _zero_int_array(nation_count)
	var pooled_configured := _zero_int_array(nation_count)
	var pooled_accessible := _zero_int_array(nation_count)
	for nation_id in range(nation_count):
		var holder := pool_holder[nation_id]
		if holder < 0 or holder >= nation_count:
			holder = nation_id
		pool_holder[nation_id] = holder
		pooled_stock[holder] += stock[nation_id]
		pooled_configured[holder] += configured_warehouse_count[nation_id]
		pooled_accessible[holder] += accessible_warehouse_count[nation_id]
	stock = pooled_stock
	configured_warehouse_count = pooled_configured
	accessible_warehouse_count = pooled_accessible
	for nation in state.nations:
		if (
			configured_warehouse_count[nation.id] == 0
			and pool_holder[nation.id] == nation.id
		):
			stock[nation.id] = maxi(nation.granary_food, 0)
			accessible_warehouse_count[nation.id] = 1

	var projected_minimum_demand := _zero_int_array(nation_count)
	for army in state.armies:
		if (
			army.size > 0 and army.owner_nation >= 0
			and army.owner_nation < nation_count
		):
			projected_minimum_demand[army.owner_nation] += (
				_projected_army_monthly_food_demand(
					army, state.nations[army.owner_nation]
				)
			)
	var demand := _zero_int_array(nation_count)
	for nation in state.nations:
		demand[nation.id] = _nation_monthly_food_demand(
			nation, projected_minimum_demand[nation.id]
		)
		if nation.alive and demand[nation.id] <= 0:
			demand[nation.id] = 1
	var pool_reserve := _zero_int_array(nation_count)
	for nation in state.nations:
		var holder := pool_holder[nation.id]
		pool_reserve[holder] += (
			demand[nation.id]
			* _food_reserve_months(policies[nation.id], nation)
		)
	# 共享粮仓的剩余采购缺口：由粮池成员按 id 序依次用各自贸易金填补。
	var pool_food_deficit := _zero_int_array(nation_count)
	for holder in range(nation_count):
		if accessible_warehouse_count[holder] <= 0:
			continue
		pool_food_deficit[holder] = maxi(pool_reserve[holder] - stock[holder], 0)

	# 2) 逐国采购：预算 = 当月贸易金（路线税）。先买粮补共享缺口，再买人补
	#    本国人力储备缺口。资源凭空产生，只从国库扣钱，不动他国库存。
	for nation in state.nations:
		var nation_id := nation.id
		if not nation.alive:
			continue
		var budget := maxi(nation_trade_gold[nation_id], 0)
		if budget <= 0:
			continue
		var holder := pool_holder[nation_id]
		var food_deficit := pool_food_deficit[holder]
		if food_deficit > 0:
			var food_gold := mini(
				budget,
				(food_deficit + FOOD_UNITS_PER_GOLD - 1) / FOOD_UNITS_PER_GOLD
			)
			var food_bought := mini(
				food_deficit, food_gold * FOOD_UNITS_PER_GOLD
			)
			if food_bought > 0:
				nation_food_import[nation_id] += food_bought
				nation_food_cost[nation_id] += food_gold
				pool_food_deficit[holder] = maxi(food_deficit - food_bought, 0)
				budget -= food_gold
		if budget <= 0:
			continue
		var manpower_target := (
			monthly_manpower_income[nation_id]
			* MANPOWER_PURCHASE_RESERVE_MONTHS
		)
		var manpower_deficit := maxi(
			manpower_target - maxi(nation.manpower_pool, 0), 0
		)
		if manpower_deficit > 0:
			var manpower_gold := mini(
				budget,
				(manpower_deficit + MANPOWER_UNITS_PER_GOLD - 1)
					/ MANPOWER_UNITS_PER_GOLD
			)
			var manpower_bought := mini(
				manpower_deficit, manpower_gold * MANPOWER_UNITS_PER_GOLD
			)
			if manpower_bought > 0:
				nation_manpower_import[nation_id] += manpower_bought
				nation_manpower_cost[nation_id] += manpower_gold
## ceil(max(ceil(size * FOOD_PER_CAPITA), 1) * route_mult * ruler_mult).
## TradeNetwork has no supply-cache dependency, so its cold-start route_mult is
## exactly 1.0. Once daily settlement exists, last/EMA demand (used above) is
## authoritative and already carries the real route loss.
static func _projected_army_monthly_food_demand(
	army: Army, nation: Nation
) -> int:
	var base := maxi(
		int(ceil(float(army.size) * FOOD_PER_CAPITA_MONTH)),
		1
	)
	return maxi(int(ceil(
		float(base) * _ruler_food_consumption_multiplier(nation)
	)), 1)


static func _nation_monthly_food_demand(
	nation: Nation, projected_demand: int
) -> int:
	var settled_demand := maxi(
		maxi(nation.last_food_demand, 0),
		maxi(int(ceil(nation.food_demand_ema)), 0)
	)
	# Settled values originate in Simulation._finalize_food_demand and already
	# include real route loss plus the ruler multiplier. Never multiply again.
	return settled_demand if settled_demand > 0 else maxi(projected_demand, 0)


## Public cold-start wrapper used by Simulation.setup to seed
## nation.last_food_demand before any real supply resolution has run.
## Reuses _projected_army_monthly_food_demand / _nation_monthly_food_demand
## without adding route loss (consistent with TradeNetwork's own fallback).
static func projected_nation_monthly_food_demand(
	state: GameState, nation_id: int
) -> int:
	if (
		state == null
		or nation_id < 0
		or nation_id >= state.nations.size()
	):
		return 0
	var nation := state.nations[nation_id]
	var projected := 0
	for army in state.armies:
		if (
			army.size > 0
			and army.owner_nation == nation_id
		):
			projected += _projected_army_monthly_food_demand(army, nation)
	return _nation_monthly_food_demand(nation, projected)


static func _ruler_food_consumption_multiplier(nation: Nation) -> float:
	# Keep the clamp identical to Simulation._ruler_food_consumption_multiplier.
	return maxf(RulerProfile.food_consumption_multiplier(nation), 0.1)


static func _food_reserve_months(policy: int, nation: Nation) -> int:
	var base := BALANCED_FOOD_RESERVE_MONTHS
	match policy:
		Policy.GOLD:
			base = GOLD_FOOD_RESERVE_MONTHS
		Policy.FOOD:
			base = FOOD_POLICY_RESERVE_MONTHS
		Policy.ISOLATION:
			base = ISOLATION_FOOD_RESERVE_MONTHS
	return maxi(base + RulerProfile.reserve_months_bonus(nation), 0)


static func _result_signature(
	routes: Array[Dictionary],
	city_gold_bonus: Array[int],
	nation_trade_gold: Array[int],
	nation_trade_tax: Array[int],
	nation_food_import: Array[int],
	nation_food_export: Array[int],
	nation_food_cost: Array[int],
	nation_food_sale_income: Array[int],
	nation_manpower_import: Array[int],
	nation_manpower_cost: Array[int],
	policies: Array[int]
) -> int:
	var signature := 17
	for value in policies:
		signature = _signature_step(signature, value)
	for route in routes:
		for key in [
			"id", "nation_a", "nation_b", "source", "destination",
			"status", "bottleneck", "blocked_city",
			"blocked_edge_key", "gold", "food", "food_exporter",
			"food_importer", "food_cost", "dock_count",
			"food_source_city", "food_destination_city",
			"gold_to_a", "gold_to_b",
		]:
			signature = _signature_step(signature, int(route[key]))
		signature = _signature_step(
			signature, int(round(float(route["transport_cost"]) * 1000.0))
		)
		signature = _signature_step(
			signature,
			int(round(float(route["preferred_transport_cost"]) * 1000.0))
		)
		signature = _signature_step(
			signature, 1 if bool(route["international"]) else 0
		)
		signature = _signature_step(
			signature, 1 if bool(route["uses_water"]) else 0
		)
		for city_id in route["city_path"] as Array[int]:
			signature = _signature_step(signature, city_id)
		signature = _signature_step(signature, -7)
		for city_id in route["preferred_city_path"] as Array[int]:
			signature = _signature_step(signature, city_id)
		signature = _signature_step(signature, -13)
		for edge_key in route["edge_keys"] as Array[int]:
			signature = _signature_step(signature, edge_key & 0x7fffffff)
			signature = _signature_step(signature, edge_key >> 32)
		signature = _signature_step(signature, -17)
		for key in ["gold_a", "gold_b", "transit_gold"]:
			signature = _signature_step(signature, int(route[key]))
		signature = _signature_string(
			signature, str(route["blocked_reason"])
		)
		var bonus: Dictionary = route["city_gold_bonus"]
		var bonus_keys := bonus.keys()
		bonus_keys.sort()
		for city_id in bonus_keys:
			signature = _signature_step(signature, int(city_id))
			signature = _signature_step(signature, int(bonus[city_id]))
		signature = _signature_step(signature, -19)
	for values in [
		city_gold_bonus, nation_trade_gold, nation_trade_tax,
		nation_food_import,
		nation_food_export, nation_food_cost, nation_food_sale_income,
		nation_manpower_import, nation_manpower_cost,
	]:
		for value in values:
			signature = _signature_step(signature, int(value))
		signature = _signature_step(signature, -11)
	return signature


static func _signature_step(current: int, value: int) -> int:
	# current 始终限制在 31 位，乘法不会接近 int64 溢出。
	return int((current * 65599 + value + 1013904223) & 0x7fffffff)


static func _signature_string(current: int, value: String) -> int:
	var result := _signature_step(current, value.length())
	for index in range(value.length()):
		result = _signature_step(result, value.unicode_at(index))
	return result
