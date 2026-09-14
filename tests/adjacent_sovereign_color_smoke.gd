extends SceneTree

const MIN_HUE_DISTANCE := 15.0 / 360.0
const EPSILON := 0.00001

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	print("=== ADJACENT_SOVEREIGN_COLOR_SMOKE ===")
	_test_circular_hue_conflict_is_resolved()
	_test_same_suzerainty_root_is_exempt()
	_test_vassal_border_constrains_sovereign_roots()
	_test_territory_transaction_reconciles_new_border()
	_test_formal_world_all_sovereign_borders_are_separated()
	if _failures.is_empty():
		print("ADJACENT_SOVEREIGN_COLOR_SMOKE_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("ADJACENT_SOVEREIGN_COLOR_SMOKE_FAIL: " + failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _hue_distance(a: Color, b: Color) -> float:
	var direct := absf(a.h - b.h)
	return minf(direct, 1.0 - direct)


func _set_color(state: GameState, nation_id: int, hue: float) -> void:
	state.nations[nation_id].color = Color.from_hsv(hue, 0.70, 0.68)


func _test_circular_hue_conflict_is_resolved() -> void:
	var state := GameState.new()
	state.generate_grid_world(93001)
	_set_color(state, 0, 359.0 / 360.0)
	_set_color(state, 1, 1.0 / 360.0)
	_set_color(state, 2, 0.45)
	_set_color(state, 3, 0.70)
	var changed: bool = state.reconcile_adjacent_sovereign_colors()
	_check(changed, "跨越色环零点的 2 度接壤色差必须被识别为冲突")
	_check(
		_hue_distance(state.nations[0].color, state.nations[1].color)
			>= MIN_HUE_DISTANCE - EPSILON,
		"相邻宗主国的环形色相距离必须至少为 15 度"
	)
	var colors_after_first_pass: Array[Color] = []
	for nation in state.nations:
		colors_after_first_pass.append(nation.color)
	var colors_stable := not state.reconcile_adjacent_sovereign_colors()
	for nation in state.nations:
		colors_stable = (
			colors_stable
			and nation.color.is_equal_approx(
				colors_after_first_pass[nation.id]
			)
		)
	_check(
		colors_stable,
		"已经满足色差时重复协调不得造成颜色漂移"
	)


func _test_same_suzerainty_root_is_exempt() -> void:
	var state := GameState.new()
	state.generate_grid_world(93002)
	_set_color(state, 0, 0.20)
	_set_color(state, 1, 0.205)
	_set_color(state, 2, 0.50)
	_set_color(state, 3, 0.75)
	state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": 0,
		"civil_war": false,
	}
	var root_color_before: Color = state.nations[0].color
	var subject_color_before: Color = state.nations[1].color
	state.reconcile_adjacent_sovereign_colors()
	_check(
		state.nations[0].color.is_equal_approx(root_color_before),
		"同宗藩体系内部接壤不得推动宗主改色"
	)
	_check(
		state.nations[1].color.is_equal_approx(subject_color_before),
		"协调器不得直接修改藩王的存储颜色"
	)


func _test_vassal_border_constrains_sovereign_roots() -> void:
	var state := GameState.new()
	state.generate_grid_world(93004)
	_set_color(state, 0, 0.20)
	_set_color(state, 1, 0.60)
	_set_color(state, 2, 0.48)
	_set_color(state, 3, 0.205)
	state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": 0,
		"civil_war": false,
	}
	var subject_color_before: Color = state.nations[1].color
	state.reconcile_adjacent_sovereign_colors()
	_check(
		_hue_distance(state.nations[0].color, state.nations[3].color)
			>= MIN_HUE_DISTANCE - EPSILON,
		"藩王与外国接壤时必须约束双方宗主根的颜色"
	)
	_check(
		state.nations[1].color.is_equal_approx(subject_color_before),
		"跨宗藩边界协调不得直接改写藩王颜色"
	)


func _test_territory_transaction_reconciles_new_border() -> void:
	var state := GameState.new()
	state.generate_grid_world(93003)
	_set_color(state, 0, 0.10)
	_set_color(state, 1, 0.35)
	_set_color(state, 2, 0.60)
	_set_color(state, 3, 0.105)
	var before_saturation: float = state.nations[3].color.s
	var before_value: float = state.nations[3].color.v
	# 网格城 28 原属右上国家；转给右下国家后，它会首次与左上国家共享省界。
	var result := state.transfer_city_sovereignty(28, 3, "color_border_test")
	_check(bool(result.get("ok", false)), "测试用领土事务必须成功")
	_check(
		_hue_distance(state.nations[0].color, state.nations[3].color)
			>= MIN_HUE_DISTANCE - EPSILON,
		"领土事务产生新边界后必须自动协调宗主色相"
	)
	_check(
		is_equal_approx(state.nations[3].color.s, before_saturation)
			and is_equal_approx(state.nations[3].color.v, before_value),
		"协调宗主色相时必须保留原饱和度和明度"
	)


func _test_formal_world_all_sovereign_borders_are_separated() -> void:
	var state := GameState.new()
	state.generate_world(93005, 40, GameState.TERRAIN_CITY_COUNT)
	var all_borders_valid := true
	var sovereign_border_count := 0
	var width := state.province_map_size.x
	var height := state.province_map_size.y
	for y in range(height):
		for x in range(width):
			var city_a := state.province_ids[y * width + x]
			if city_a < 0:
				continue
			var neighbors: Array[int] = []
			if x + 1 < width:
				neighbors.append(state.province_ids[y * width + x + 1])
			if y + 1 < height:
				neighbors.append(state.province_ids[(y + 1) * width + x])
			for city_b in neighbors:
				if city_b < 0 or city_b == city_a:
					continue
				var root_a := state.suzerainty_root(
					state.cities[city_a].owner_nation
				)
				var root_b := state.suzerainty_root(
					state.cities[city_b].owner_nation
				)
				if root_a == root_b:
					continue
				sovereign_border_count += 1
				all_borders_valid = (
					all_borders_valid
					and _hue_distance(
						state.nations[root_a].color,
						state.nations[root_b].color
					) >= MIN_HUE_DISTANCE - EPSILON
				)
	_check(sovereign_border_count > 0, "正式地图必须生成宗主国省界样本")
	_check(all_borders_valid, "40 国正式地图的全部相邻宗主色差必须至少为 15 度")
