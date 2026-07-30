class_name MapRenderer
extends Node2D
## 表现层：只读 GameState，用 _draw() 单一渲染源绘制地图/城市/边/军队/HUD。
## 处理暂停 / 调速 / 重开输入（转发给 Simulation / Main）。

var state: GameState
var sim: Simulation

# 布局基准：实际窗口相对 1280×720 同比缩放，不依赖固定逻辑画布。
const BASE_VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const BASE_SIDE_MARGIN := 40.0
const BASE_BOTTOM_MARGIN := 40.0
const BASE_HUD_TOP := 68.0
const BASE_HUD_ROW_HEIGHT := 22.0
const TERRAIN_BACKGROUND_PATH := GameState.TERRAIN_MAP_PATH
var _cell: float = 64.0
var _origin: Vector2 = Vector2(40.0, 90.0)
var _map_size: Vector2 = Vector2(512.0, 512.0)
var _display_scale: float = 1.0
var _side_margin: float = BASE_SIDE_MARGIN
var _hud_columns: int = 4
var _hud_card_width: float = 300.0

var _font: Font
var _terrain_texture: Texture2D
var _blink: float = 0.0                    ## 饥饿闪烁计时

# tick 间插值：军队逻辑位置每天跳变一次，渲染在两次 tick 之间平滑过渡。
var _prev_pos: Dictionary = {}             ## army.id -> 上一 tick 末的逻辑位置
var _curr_pos: Dictionary = {}             ## army.id -> 当前 tick 末的逻辑位置
var _last_day: int = -1


func setup(game_state: GameState, simulation: Simulation) -> void:
	state = game_state
	sim = simulation
	# Main 重开会复用 Renderer，army id 也会从 0 重排；旧快照不可跨 GameState 复用。
	_prev_pos.clear()
	_curr_pos.clear()
	_last_day = -1


func _ready() -> void:
	_font = create_ui_font()
	_terrain_texture = load(TERRAIN_BACKGROUND_PATH) as Texture2D


static func create_ui_font() -> Font:
	var candidates := PackedStringArray([
		"/System/Library/Fonts/Hiragino Sans GB.ttc",
		"/System/Library/Fonts/STHeiti Medium.ttc",
		"C:/Windows/Fonts/msyh.ttc",
		"C:/Windows/Fonts/simhei.ttf",
		"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
		"/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
	])
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var font_file := FontFile.new()
		if font_file.load_dynamic_font(path) == OK:
			return font_file
	return ThemeDB.fallback_font


func _process(_delta: float) -> void:
	_blink += _delta
	_sync_snapshots()
	queue_redraw()


func _compute_layout() -> void:
	var vp := get_viewport_rect().size
	var nation_count := state.nations.size() if state != null else GameState.NATION_COUNT
	var layout := compute_layout_for_viewport(vp, nation_count)
	var span := float(layout["span"])
	var aspect := clampf(state.map_aspect_ratio if state != null else 1.0, 0.5, 2.5)
	_map_size = (
		Vector2(span, span / aspect)
		if aspect >= 1.0
		else Vector2(span * aspect, span)
	)
	_origin = (layout["origin"] as Vector2) + (Vector2(span, span) - _map_size) * 0.5
	_cell = minf(_map_size.x, _map_size.y) / float(GameState.GRID)
	_display_scale = layout["display_scale"]
	_side_margin = layout["side_margin"]
	_hud_columns = layout["hud_columns"]
	_hud_card_width = layout["hud_card_width"]


static func compute_layout_for_viewport(viewport_size: Vector2, nation_count: int) -> Dictionary:
	var safe_size := Vector2(maxf(viewport_size.x, 1.0), maxf(viewport_size.y, 1.0))
	var display_scale := clampf(
		minf(
			safe_size.x / BASE_VIEWPORT_SIZE.x,
			safe_size.y / BASE_VIEWPORT_SIZE.y
		),
		0.65,
		3.0
	)
	var side_margin := BASE_SIDE_MARGIN * display_scale
	var available_width := maxf(safe_size.x - side_margin * 2.0, 1.0)
	var count := maxi(nation_count, 1)
	var minimum_card_width := 280.0 * display_scale
	var hud_columns := clampi(
		int(floor(available_width / maxf(minimum_card_width, 1.0))),
		1,
		count
	)
	var hud_rows := int(ceil(float(count) / float(hud_columns)))
	var top_margin := (
		BASE_HUD_TOP + BASE_HUD_ROW_HEIGHT * float(hud_rows)
	) * display_scale
	var bottom_margin := BASE_BOTTOM_MARGIN * display_scale
	var span := maxf(minf(
		available_width,
		safe_size.y - top_margin - bottom_margin
	), 1.0)
	return {
		"cell": span / float(GameState.GRID),
		"span": span,
		"origin": Vector2((safe_size.x - span) * 0.5, top_margin),
		"display_scale": display_scale,
		"side_margin": side_margin,
		"hud_columns": hud_columns,
		"hud_card_width": available_width / float(hud_columns),
	}


func _font_size(base_size: float) -> int:
	return maxi(int(round(base_size * _display_scale)), 1)


func _city_center(city: City) -> Vector2:
	return _origin + city.map_position * _map_size


## 每当模拟推进一天，快照全部军队的逻辑位置：上次快照 -> _prev，本次 -> _curr。
## 渲染时在两者间按 day_fraction 插值，使运动连续（消除"一秒一跳"）。
func _sync_snapshots() -> void:
	if state == null:
		return
	if state.day == _last_day:
		return
	_last_day = state.day
	_prev_pos = _curr_pos
	_curr_pos = {}
	for army in state.armies:
		_curr_pos[army.id] = _logical_grid_pos(army)
	# 首帧或新军队无 prev：用 curr 兜底，避免从 (0,0) 飞入
	if _prev_pos.is_empty():
		_prev_pos = _curr_pos.duplicate()

# ================================================================== 绘制

func _draw() -> void:
	if state == null:
		return
	_compute_layout()
	_draw_terrain_background()
	_draw_edges()
	_draw_cities()
	_draw_battles()
	_draw_armies()
	_draw_hud()


func _draw_terrain_background() -> void:
	if not state.uses_heightmap or _terrain_texture == null:
		return
	var texture_size := Vector2(_terrain_texture.get_size())
	var normalized_region := state.map_source_region_normalized
	var source_region := Rect2(
		normalized_region.position * texture_size,
		normalized_region.size * texture_size
	)
	draw_texture_rect_region(
		_terrain_texture,
		Rect2(_origin, _map_size),
		source_region,
		Color(0.38, 0.40, 0.42, 0.62)
	)
	# 暗色罩层压低底图细节，保证道路、国家色和文字仍是视觉主层。
	draw_rect(Rect2(_origin, _map_size), Color(0.02, 0.025, 0.035, 0.34), true)


func _draw_edges() -> void:
	for e in state.edges:
		var pa := _city_center(state.cities[e.city_a])
		var pb := _city_center(state.cities[e.city_b])
		var danger := clampf(e.danger, 0.0, 1.0)
		if e.max_throughput <= 0:
			# 高山或小渡口等战略阻断仍显示地理连接，但不属于军事道路网络。
			var blocked_col := Color(0.20, 0.16, 0.24).lerp(
				Color(0.48, 0.20, 0.30), danger
			)
			draw_line(pa, pb, blocked_col, 2.0 * _display_scale)
			_draw_blocked_edge_marker(pa, pb, blocked_col.lightened(0.28))
			continue
		var road_level := clampi(e.max_throughput, 1, 4)
		var road_colors: Array[Color] = [
			Color(0.34, 0.34, 0.38),
			Color(0.48, 0.46, 0.42),
			Color(0.72, 0.65, 0.48),
			Color(0.96, 0.82, 0.42),
		]
		var road_widths: Array[float] = [1.5, 2.5, 4.0, 6.0]
		var col: Color = road_colors[road_level - 1]
		col = col.lerp(Color(0.72, 0.20, 0.27), danger * 0.38)
		var width: float = road_widths[road_level - 1] * _display_scale
		if road_level >= 3:
			draw_line(
				pa, pb, Color(0.05, 0.04, 0.04, 0.75),
				width + 2.0 * _display_scale
			)
		if e.occupied:
			col = col.lerp(Color(0.95, 0.85, 0.3), 0.55)
			width += 1.5 * _display_scale
		draw_line(pa, pb, col, width)


func _draw_blocked_edge_marker(pa: Vector2, pb: Vector2, color: Color) -> void:
	var midpoint := (pa + pb) * 0.5
	var direction := (pb - pa).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var radius := clampf(
		_cell * 0.09,
		4.0 * _display_scale,
		8.0 * _display_scale
	)
	draw_line(
		midpoint - direction * radius - normal * radius,
		midpoint + direction * radius + normal * radius,
		color,
		2.5 * _display_scale
	)
	draw_line(
		midpoint - direction * radius + normal * radius,
		midpoint + direction * radius - normal * radius,
		color,
		2.5 * _display_scale
	)


func _draw_cities() -> void:
	var half := clampf(
		_cell * 0.18,
		5.0 * _display_scale,
		10.0 * _display_scale
	)
	var contested_cities := contested_city_ids(state)
	for city in state.cities:
		var center := _city_center(city)
		var rect := Rect2(center - Vector2(half, half), Vector2(half * 2, half * 2))
		var base := state.nations[city.owner_nation].color
		draw_rect(rect, base, true)
		# 红框只表示本城正在发生守城战或围城，不再复述全局战争状态。
		var border := (
			Color(0.9, 0.1, 0.1)
			if contested_cities.has(city.id)
			else Color(0, 0, 0, 0.5)
		)
		draw_rect(rect, border, false, 2.0 * _display_scale)
		# 普通城市只显示城防；首都粮仓额外显示 C/W 与库存。
		var label := "D%d" % city.defense
		if city.has_warehouse:
			label += " %sF%d" % ["C" if city.is_capital else "W", city.food_storage]
		draw_string(
			_font,
			rect.position + Vector2(2, 9) * _display_scale,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_font_size(8),
			Color(0, 0, 0, 0.8)
		)


static func contested_city_ids(game_state: GameState) -> Dictionary:
	var result := {}
	for battle in game_state.battles:
		if not battle.finished and battle.city != null:
			result[battle.city.id] = true
	return result


func _draw_armies() -> void:
	var blink_on := fmod(_blink, 0.6) < 0.3
	var pulse := 0.5 + 0.5 * sin(_blink * 6.0)   # 0..1 脉动
	for army in state.armies:
		if army.size <= 0:
			continue
		var pos := _army_position(army)
		var col := state.nations[army.owner_nation].color.lightened(0.25)
		var radius := (
			clampf(4.0 + army.size / 300.0, 4.0, 12.0)
			* _display_scale
		)
		# 饥饿闪烁
		if army.starving and blink_on:
			col = Color(1, 1, 1)
		draw_circle(pos, radius, col)
		# 交战军队：脉动红圈描边（一眼区分“正在打仗”）
		if army.state == Army.State.FIGHTING:
			var rr := radius + (2.0 + pulse * 3.0) * _display_scale
			draw_arc(
				pos, rr, 0, TAU, 20,
				Color(1.0, 0.3, 0.2, 0.5 + 0.4 * pulse),
				2.0 * _display_scale
			)
		elif army.state == Army.State.RECOVERING:
			# 驻城恢复：稳定蓝圈，区别于交战红圈和断粮白闪。
			draw_arc(
				pos, radius + 3.0 * _display_scale, 0, TAU, 20,
				Color(0.25, 0.75, 1.0, 0.9),
				2.0 * _display_scale
			)
		elif army.state == Army.State.HOLDING:
			var h := radius + 3.0 * _display_scale
			draw_polyline(PackedVector2Array([
				pos + Vector2(0, -h), pos + Vector2(h, 0), pos + Vector2(0, h),
				pos + Vector2(-h, 0), pos + Vector2(0, -h),
			]), Color(0.2, 1.0, 0.85, 0.95), 2.0 * _display_scale)
			draw_string(
				_font,
				pos + Vector2(radius + 4.0 * _display_scale, radius + 4.0 * _display_scale),
				"H%d" % army.holding_days,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				_font_size(9),
				Color(0.5, 1.0, 0.9)
			)
		draw_arc(
			pos, radius, 0, TAU, 16,
			Color(0, 0, 0, 0.7),
			1.5 * _display_scale
		)
		_draw_morale_bar(pos, radius, army.morale)
		draw_string(
			_font,
			pos + Vector2(-10.0 * _display_scale, -radius - 4.0 * _display_scale),
			str(army.size),
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			_font_size(9),
			Color.WHITE
		)


## 军队士气条：位于军队圆下方，红(0)→黄(0.5)→绿(1) 映射，直观展示疲劳/濒溃。
func _draw_morale_bar(pos: Vector2, radius: float, morale: float) -> void:
	var w := 20.0 * _display_scale
	var h := 3.0 * _display_scale
	var top_left := pos + Vector2(-w * 0.5, radius + 3.0 * _display_scale)
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0, 0, 0, 0.55), true)
	var m := clampf(morale, 0.0, 1.0)
	var fill := Color(1.0 - m, m, 0.15) if m > 0.5 else Color(1.0, m * 2.0, 0.15)
	draw_rect(Rect2(top_left, Vector2(w * m, h)), fill, true)


## 战斗爆发标记：在每场活跃战斗的交战点画脉动星芒 + 扩散环 + 回合数。
func _draw_battles() -> void:
	if state.battles.is_empty():
		return
	var pulse := 0.5 + 0.5 * sin(_blink * 6.0)
	for b in state.battles:
		if b.finished:
			continue
		var p := _battle_pixel(b)
		# 扩散环（回合越多环越大，体现“持续多回合”的拉锯）
		var ring := (
			10.0 + minf(float(b.round_no), 12.0) * 1.5 + pulse * 5.0
		) * _display_scale
		draw_arc(
			p, ring, 0, TAU, 28,
			Color(1.0, 0.55, 0.1, 0.35 + 0.35 * pulse),
			2.0 * _display_scale
		)
		# 星芒（8 道，脉动）
		var spikes := 8
		var r_in := 4.0 * _display_scale
		var r_out := (9.0 + pulse * 4.0) * _display_scale
		for i in range(spikes):
			var ang := TAU * float(i) / float(spikes)
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(
				p + dir * r_in, p + dir * r_out,
				Color(1.0, 0.85, 0.2, 0.9),
				2.0 * _display_scale
			)
		draw_circle(p, r_in, Color(1.0, 0.95, 0.6, 0.9))
		# 回合数
		draw_string(
			_font,
			p + Vector2(6, -8) * _display_scale,
			"R%d" % b.round_no,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_font_size(11),
			Color(1, 1, 1)
		)
		# 攻城进度弧（纯围城阶段：siege_progress / REQUIRED）
		if b.kind == Battle.Kind.SIEGE and b.siege_progress > 0.0:
			var frac := clampf(b.siege_progress / Combat.SIEGE_PROGRESS_REQUIRED, 0.0, 1.0)
			draw_arc(
				p,
				ring + 4.0 * _display_scale,
				-PI / 2.0,
				-PI / 2.0 + TAU * frac,
				32,
				Color(0.4, 0.9, 1.0, 0.95),
				3.0 * _display_scale
			)


## 战斗交战点像素坐标：野战取边上 contact_dist_a 处，攻城取目标城。
func _battle_pixel(b: Battle) -> Vector2:
	if b.kind == Battle.Kind.SIEGE and b.city != null:
		return _city_center(b.city)
	if b.edge != null:
		var length := float(maxi(b.edge.distance, 1))
		var a := _city_grid(state.cities[b.edge.city_a])
		var c := _city_grid(state.cities[b.edge.city_b])
		return _grid_to_pixel(a.lerp(c, clampf(b.contact_dist_a / length, 0.0, 1.0)))
	# 兜底：任一参战军队位置
	if not b.side_a.is_empty():
		return _army_position(b.side_a[0])
	return _origin


## 军队渲染位置：在上/本月快照（网格坐标）间按当月已流逝比例插值，再转像素。
func _army_position(army: Army) -> Vector2:
	var curr: Vector2 = _curr_pos.get(army.id, _logical_grid_pos(army))
	var g: Vector2 = curr
	if _prev_pos.has(army.id):
		g = (_prev_pos[army.id] as Vector2).lerp(curr, sim.day_fraction())
	return _grid_to_pixel(g)


## 军队逻辑位置使用归一化地图坐标，与像素布局无关（便于跨帧/缩放插值）。
func _logical_grid_pos(army: Army) -> Vector2:
	# MOVING / HOLDING / RETREATING / FIGHTING 均可定位在边上。
	if army.state in [
		Army.State.MOVING,
		Army.State.HOLDING,
		Army.State.RETREATING,
		Army.State.FIGHTING,
	] and army.move_to != -1:
		var a := _city_grid(state.cities[army.move_from])
		var b := _city_grid(state.cities[army.move_to])
		return a.lerp(b, clampf(army.move_progress, 0.0, 1.0))
	var cid := army.location_city if army.location_city != -1 else army.move_from
	return _city_grid(state.cities[cid])


func _city_grid(city: City) -> Vector2:
	return city.map_position


func _grid_to_pixel(g: Vector2) -> Vector2:
	return _origin + g * _map_size


func _draw_hud() -> void:
	var header_y := 20.0 * _display_scale
	var status := "PAUSED" if sim.paused else "RUN"
	if state.winner != -1:
		status = "WINNER: 国%d" % state.winner
	var header := "Day %d (M%d)   [%s]   Speed x%.2f   (Space:暂停  +/-:调速  R:重开)" % [
		state.day, state.month, status, sim.speed_multiplier()
	]
	draw_string(
		_font,
		Vector2(_side_margin, header_y),
		header,
		HORIZONTAL_ALIGNMENT_LEFT,
		get_viewport_rect().size.x - _side_margin * 2.0,
		_font_size(16),
		Color.WHITE
	)

	# 各国概览
	var overview_y := 46.0 * _display_scale
	for nation_index in range(state.nations.size()):
		var n := state.nations[nation_index]
		var city_count := state.cities_of(n.id).size()
		var troops := 0
		for army in state.armies:
			if army.owner_nation == n.id:
				troops += army.size
		var line := "国%d 城%d 金%d 粮%d 人%d 兵%d%s" % [
			n.id, city_count, n.treasury_gold, n.granary_food, n.manpower_pool, troops,
			"" if n.alive else " (灭)"
		]
		var column := nation_index % _hud_columns
		var row := int(nation_index / _hud_columns)
		var position := Vector2(
			_side_margin + float(column) * _hud_card_width,
			overview_y + float(row) * BASE_HUD_ROW_HEIGHT * _display_scale
		)
		draw_string(
			_font,
			position,
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			_hud_card_width - 8.0 * _display_scale,
			_font_size(13),
			n.color.lightened(0.2)
		)
