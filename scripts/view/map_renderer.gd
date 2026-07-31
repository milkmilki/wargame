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
const BASE_HUD_CARD_HEIGHT := 81.0
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
var _province_texture: ImageTexture
var _province_boundary_segments := PackedVector2Array()
var _coast_segments := PackedVector2Array()
var _nation_boundary_segments := PackedVector2Array()
var _alliance_boundary_segments := PackedVector2Array()
var _province_cache_ready: bool = false
var _province_ownership_revision: int = -1
var _province_diplomacy_revision: int = -1
var _campaign_event_seen_at: Dictionary = {}
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
	_province_texture = null
	_province_boundary_segments = PackedVector2Array()
	_coast_segments = PackedVector2Array()
	_nation_boundary_segments = PackedVector2Array()
	_alliance_boundary_segments = PackedVector2Array()
	_province_cache_ready = false
	_province_ownership_revision = -1
	_province_diplomacy_revision = -1
	_campaign_event_seen_at.clear()


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
		BASE_HUD_TOP
		+ BASE_HUD_CARD_HEIGHT * float(hud_rows)
		+ BASE_HUD_ROW_HEIGHT
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
	_ensure_province_visual_cache()
	_draw_province_fills()
	_draw_province_boundaries()
	_draw_edges()
	_draw_national_boundaries()
	_draw_campaign_arrows()
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


func _ensure_province_visual_cache() -> void:
	if (
		state.province_map_size.x <= 0
		or state.province_map_size.y <= 0
		or state.province_ids.is_empty()
	):
		return
	if not _province_cache_ready:
		var geometry := build_province_boundary_segments(state)
		_province_boundary_segments = geometry["province"]
		_coast_segments = geometry["coast"]
		_province_cache_ready = true
	if (
		_province_texture == null
		or _province_ownership_revision != state.ownership_revision
		or _province_diplomacy_revision != state.diplomacy_revision
	):
		var image := build_province_overlay_image(state)
		_province_texture = ImageTexture.create_from_image(image)
		var geometry := build_province_boundary_segments(state)
		_nation_boundary_segments = geometry["nation"]
		_alliance_boundary_segments = geometry["alliance"]
		_province_ownership_revision = state.ownership_revision
		_province_diplomacy_revision = state.diplomacy_revision


static func build_province_overlay_image(game_state: GameState) -> Image:
	var size := game_state.province_map_size
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(size.y):
		for x in range(size.x):
			var province_id := game_state.province_ids[y * size.x + x]
			if province_id < 0 or province_id >= game_state.cities.size():
				continue
			var current_owner := game_state.cities[province_id].owner_nation
			var recognized_owner := game_state.recognized_owner_of(province_id)
			if recognized_owner < 0:
				recognized_owner = current_owner
			var base := game_state.nations[recognized_owner].color
			base.a = 0.30
			if current_owner != recognized_owner and (x + y) % 9 < 3:
				var occupation := game_state.nations[current_owner].color.lightened(0.18)
				occupation.a = 0.72
				base = occupation
			image.set_pixel(x, y, base)
	return image


static func build_province_boundary_segments(
	game_state: GameState
) -> Dictionary:
	var province := PackedVector2Array()
	var nation := PackedVector2Array()
	var alliance := PackedVector2Array()
	var coast := PackedVector2Array()
	var size := game_state.province_map_size
	if size.x <= 0 or size.y <= 0:
		return {
			"province": province,
			"nation": nation,
			"alliance": alliance,
			"coast": coast,
		}
	for y in range(size.y):
		for x in range(size.x):
			var province_id := game_state.province_ids[y * size.x + x]
			if province_id < 0:
				continue
			var left := (
				game_state.province_ids[y * size.x + x - 1]
				if x > 0 else -1
			)
			var top := (
				game_state.province_ids[(y - 1) * size.x + x]
				if y > 0 else -1
			)
			var right := (
				game_state.province_ids[y * size.x + x + 1]
				if x + 1 < size.x else -1
			)
			var bottom := (
				game_state.province_ids[(y + 1) * size.x + x]
				if y + 1 < size.y else -1
			)
			var x0 := float(x) / float(size.x)
			var x1 := float(x + 1) / float(size.x)
			var y0 := float(y) / float(size.y)
			var y1 := float(y + 1) / float(size.y)
			if left < 0:
				_append_segment(coast, Vector2(x0, y0), Vector2(x0, y1))
			if top < 0:
				_append_segment(coast, Vector2(x0, y0), Vector2(x1, y0))
			if right < 0:
				_append_segment(coast, Vector2(x1, y0), Vector2(x1, y1))
			elif right != province_id:
				_append_segment(province, Vector2(x1, y0), Vector2(x1, y1))
				if _province_owners_differ(game_state, province_id, right):
					_append_segment(nation, Vector2(x1, y0), Vector2(x1, y1))
					if _province_owners_allied(
						game_state, province_id, right
					):
						_append_segment(
							alliance, Vector2(x1, y0), Vector2(x1, y1)
						)
			if bottom < 0:
				_append_segment(coast, Vector2(x0, y1), Vector2(x1, y1))
			elif bottom != province_id:
				_append_segment(province, Vector2(x0, y1), Vector2(x1, y1))
				if _province_owners_differ(game_state, province_id, bottom):
					_append_segment(nation, Vector2(x0, y1), Vector2(x1, y1))
					if _province_owners_allied(
						game_state, province_id, bottom
					):
						_append_segment(
							alliance, Vector2(x0, y1), Vector2(x1, y1)
						)
	return {
		"province": province,
		"nation": nation,
		"alliance": alliance,
		"coast": coast,
	}


static func _province_owners_differ(
	game_state: GameState,
	province_a: int,
	province_b: int
) -> bool:
	return (
		province_a >= 0
		and province_b >= 0
		and game_state.cities[province_a].owner_nation
			!= game_state.cities[province_b].owner_nation
	)


static func _province_owners_allied(
	game_state: GameState,
	province_a: int,
	province_b: int
) -> bool:
	if province_a < 0 or province_b < 0:
		return false
	return game_state.is_allied(
		game_state.cities[province_a].owner_nation,
		game_state.cities[province_b].owner_nation
	)


static func _append_segment(
	segments: PackedVector2Array,
	from: Vector2,
	to: Vector2
) -> void:
	segments.append(from)
	segments.append(to)


func _draw_province_fills() -> void:
	if _province_texture == null:
		return
	draw_texture_rect(
		_province_texture,
		Rect2(_origin, _map_size),
		false,
		Color.WHITE
	)


func _normalized_segments_to_pixels(
	segments: PackedVector2Array
) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(segments.size())
	for i in range(segments.size()):
		result[i] = _origin + segments[i] * _map_size
	return result


func _draw_province_boundaries() -> void:
	if not _province_boundary_segments.is_empty():
		draw_multiline(
			_normalized_segments_to_pixels(_province_boundary_segments),
			Color(0.08, 0.09, 0.12, 0.72),
			maxf(1.0 * _display_scale, 1.0),
			true
		)


func _draw_national_boundaries() -> void:
	var coast_pixels := _normalized_segments_to_pixels(_coast_segments)
	if not coast_pixels.is_empty():
		draw_multiline(
			coast_pixels,
			Color(0.02, 0.025, 0.04, 0.90),
			4.0 * _display_scale,
			true
		)
		draw_multiline(
			coast_pixels,
			Color(0.78, 0.78, 0.70, 0.72),
			1.4 * _display_scale,
			true
		)
	if _nation_boundary_segments.is_empty():
		return
	var nation_pixels := _normalized_segments_to_pixels(
		_nation_boundary_segments
	)
	draw_multiline(
		nation_pixels,
		Color(0.025, 0.02, 0.035, 0.96),
		6.0 * _display_scale,
		true
	)
	draw_multiline(
		nation_pixels,
		Color(1.0, 0.88, 0.54, 0.94),
		2.4 * _display_scale,
		true
	)
	if not _alliance_boundary_segments.is_empty():
		draw_multiline(
			_normalized_segments_to_pixels(_alliance_boundary_segments),
			Color(0.25, 0.92, 1.0, 0.96),
			2.8 * _display_scale,
			true
		)


func _draw_campaign_arrows() -> void:
	for event in state.campaign_visual_events:
		var target_city := int(event.get("target_city", -1))
		var nation_id := int(event.get("nation_id", -1))
		if (
			target_city < 0
			or target_city >= state.cities.size()
			or nation_id < 0
			or nation_id >= state.nations.size()
		):
			continue
		var event_key := "%d:%d:%d:%d" % [
			nation_id,
			int(event["start_day"]),
			int(event.get("wave", 0)),
			target_city,
		]
		if not _campaign_event_seen_at.has(event_key):
			_campaign_event_seen_at[event_key] = _blink
		var visual_age := _blink - float(_campaign_event_seen_at[event_key])
		const DISPLAY_SECONDS: float = 3.0
		const FADE_SECONDS: float = 0.65
		if visual_age >= DISPLAY_SECONDS:
			continue
		var alpha := clampf(
			(DISPLAY_SECONDS - visual_age) / FADE_SECONDS,
			0.0,
			1.0
		)
		var origins: Array = event.get("origin_cities", [])
		for index in range(origins.size()):
			var origin_city := int(origins[index])
			if origin_city < 0 or origin_city >= state.cities.size():
				continue
			_draw_campaign_arrow(
				_city_center(state.cities[origin_city]),
				_city_center(state.cities[target_city]),
				state.nations[nation_id].color,
				alpha,
				index
			)


func _draw_campaign_arrow(
	start: Vector2,
	finish: Vector2,
	color: Color,
	alpha: float,
	curve_index: int
) -> void:
	var delta := finish - start
	if delta.length_squared() < 1.0:
		return
	var direction := delta.normalized()
	var normal := Vector2(-direction.y, direction.x)
	var bend_sign := -1.0 if curve_index % 2 == 0 else 1.0
	var control := (
		(start + finish) * 0.5
		+ normal * minf(delta.length() * 0.16, 42.0 * _display_scale) * bend_sign
	)
	var points := PackedVector2Array()
	const SEGMENTS: int = 18
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var inv := 1.0 - t
		points.append(
			start * inv * inv + control * 2.0 * inv * t + finish * t * t
		)
	var arrow_color := color.lightened(0.28)
	arrow_color.a = 0.92 * alpha
	draw_polyline(
		points,
		Color(0.025, 0.02, 0.03, 0.84 * alpha),
		9.0 * _display_scale,
		true
	)
	draw_polyline(points, arrow_color, 5.0 * _display_scale, true)
	var tangent := (finish - control).normalized()
	var arrow_normal := Vector2(-tangent.y, tangent.x)
	var head_length := 18.0 * _display_scale
	var head_width := 10.0 * _display_scale
	var head := PackedVector2Array([
		finish,
		finish - tangent * head_length + arrow_normal * head_width,
		finish - tangent * head_length - arrow_normal * head_width,
	])
	draw_colored_polygon(head, arrow_color)


func _draw_edges() -> void:
	for e in state.edges:
		var pa := _city_center(state.cities[e.city_a])
		var pb := _city_center(state.cities[e.city_b])
		var danger := clampf(e.danger, 0.0, 1.0)
		if e.max_manpower <= 0:
			# 高山或小渡口等战略阻断仍显示地理连接，但不属于军事道路网络。
			var blocked_col := Color(0.20, 0.16, 0.24).lerp(
				Color(0.48, 0.20, 0.30), danger
			)
			draw_line(pa, pb, blocked_col, 2.0 * _display_scale)
			_draw_blocked_edge_marker(pa, pb, blocked_col.lightened(0.28))
			continue
		var road_level := 1
		if e.max_manpower >= 100000:
			road_level = 4
		elif e.max_manpower >= 60000:
			road_level = 3
		elif e.max_manpower >= 15000:
			road_level = 2
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
		if city.is_food_hub:
			label += " 粮"
		if city.is_manpower_hub:
			label += " 人"
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
		if (
			army.offensive_attack_multiplier > 1.0
			and state.day < army.offensive_bonus_until_day
		):
			draw_arc(
				pos,
				radius + 5.0 * _display_scale,
				0,
				TAU,
				20,
				Color(1.0, 0.75, 0.15, 0.95),
				2.5 * _display_scale
			)
			draw_string(
				_font,
				pos + Vector2(
					radius + 5.0 * _display_scale,
					-radius
				),
				"攻x%.2f" % army.offensive_attack_multiplier,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				_font_size(9),
				Color(1.0, 0.85, 0.35)
			)
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

	# 各国独立详情卡。
	var overview_y := 46.0 * _display_scale
	for nation_index in range(state.nations.size()):
		var n := state.nations[nation_index]
		var column := nation_index % _hud_columns
		var row := int(nation_index / _hud_columns)
		var card_position := Vector2(
			_side_margin + float(column) * _hud_card_width,
			overview_y + float(row) * BASE_HUD_CARD_HEIGHT * _display_scale
		)
		var card_rect := Rect2(
			card_position,
			Vector2(
				_hud_card_width - 8.0 * _display_scale,
				(BASE_HUD_CARD_HEIGHT - 6.0) * _display_scale
			)
		)
		_draw_nation_detail_card(n.id, card_rect)
	if not state.diplomatic_history.is_empty():
		var event: Dictionary = state.diplomatic_history[-1]
		var diplomacy_y := (
			overview_y
			+ float(int(ceil(float(state.nations.size()) / float(_hud_columns))))
				* BASE_HUD_CARD_HEIGHT * _display_scale
			+ 2.0 * _display_scale
		)
		var diplomacy_line := "外交 Day%d 国%d→国%d %s：%s" % [
			event["day"],
			event["nation_a"],
			event["nation_b"],
			_diplomatic_action_name(int(event["action"])),
			event["reason"],
		]
		draw_string(
			_font,
			Vector2(_side_margin, diplomacy_y),
			diplomacy_line,
			HORIZONTAL_ALIGNMENT_LEFT,
			get_viewport_rect().size.x - _side_margin * 2.0,
			_font_size(12),
			Color(0.90, 0.90, 0.75)
		)


func _draw_nation_detail_card(nation_id: int, rect: Rect2) -> void:
	var n := state.nations[nation_id]
	var details := nation_detail_lines(state, nation_id)
	var at_war := not state.wars_of(nation_id).is_empty()
	var background := Color(0.035, 0.045, 0.065, 0.92)
	if at_war:
		background = Color(0.12, 0.035, 0.04, 0.94)
	elif not n.alive:
		background = Color(0.035, 0.035, 0.04, 0.82)
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.55), true)
	var inner := rect.grow(-1.0 * _display_scale)
	draw_rect(inner, background, true)
	draw_rect(
		Rect2(inner.position, Vector2(5.0 * _display_scale, inner.size.y)),
		n.color,
		true
	)
	draw_line(
		inner.position + Vector2(8.0, 22.0) * _display_scale,
		inner.position + Vector2(inner.size.x / _display_scale - 8.0, 22.0)
			* _display_scale,
		Color(1.0, 1.0, 1.0, 0.10),
		1.0 * _display_scale
	)
	var text_x := inner.position.x + 11.0 * _display_scale
	var title_color := n.color.lightened(0.32)
	var status := "战争" if at_war else ("和平" if n.alive else "灭亡")
	draw_string(
		_font,
		Vector2(text_x, inner.position.y + 17.0 * _display_scale),
		"国%d  %s" % [nation_id, status],
		HORIZONTAL_ALIGNMENT_LEFT,
		inner.size.x - 18.0 * _display_scale,
		_font_size(13),
		title_color
	)
	for line_index in range(details.size()):
		draw_string(
			_font,
			Vector2(
				text_x,
				inner.position.y
					+ (36.0 + float(line_index) * 15.0) * _display_scale
			),
			details[line_index],
			HORIZONTAL_ALIGNMENT_LEFT,
			inner.size.x - 18.0 * _display_scale,
			_font_size(10),
			Color(0.88, 0.91, 0.96, 0.96)
		)


static func nation_detail_lines(
	game_state: GameState,
	nation_id: int
) -> Array[String]:
	var n := game_state.nations[nation_id]
	var troops := 0
	for army in game_state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			troops += army.size
	var report := DiplomacyAI.resource_report(game_state, nation_id)
	var gold_balance := int(report["monthly_gold_balance"])
	var line_one := "城%d 兵%d 人%d  金%d (%+d/月)" % [
		game_state.cities_of(nation_id).size(),
		troops,
		n.manpower_pool,
		n.treasury_gold,
		gold_balance,
	]
	var line_two := "粮%d 需%d/月  战%s  盟%s" % [
		n.granary_food,
		int(ceil(float(report["monthly_food_demand"]))),
		str(game_state.wars_of(nation_id)),
		str(game_state.allies_of(nation_id)),
	]
	var lines := [line_one, line_two] as Array[String]
	if not n.campaign_attack_assignments.is_empty():
		var assignments: Array[String] = []
		var army_ids := n.campaign_attack_assignments.keys()
		army_ids.sort()
		for army_id_value in army_ids:
			if assignments.size() >= 3:
				break
			var army_id := int(army_id_value)
			assignments.append(
				"军%d>城%d" % [
					army_id,
					int(n.campaign_attack_assignments[army_id]),
				]
			)
		lines.append(
			"计划W%d %s" % [
				n.campaign_plan_wave,
				" ".join(assignments),
			]
		)
	return lines


static func _diplomatic_action_name(action: int) -> String:
	match action:
		DiplomacyAI.Action.MAKE_PEACE:
			return "求和"
		DiplomacyAI.Action.DECLARE_WAR:
			return "宣战"
		DiplomacyAI.Action.FORM_ALLIANCE:
			return "结盟"
		DiplomacyAI.Action.LEAVE_ALLIANCE:
			return "退盟"
		DiplomacyAI.Action.PREPARE_WAR:
			return "备战"
		DiplomacyAI.Action.CANCEL_WAR_PREPARATION:
			return "取消备战"
	return "外交"
