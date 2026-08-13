class_name MapRenderer
extends Node2D
## 表现层：只读 GameState，用 _draw() 单一渲染源绘制地图/城市/边/军队/HUD。
## 鼠标选择仅保存在表现层，不进入模拟状态或存档。

var state: GameState
var sim: Simulation

# 地图画布连续适配窗口；图标、字体和线宽只使用四档离散视觉比例。
const BASE_VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const BASE_SIDE_MARGIN := 40.0
const BASE_BOTTOM_MARGIN := 40.0
const BASE_HEADER_ONLY_TOP := 44.0
const NATION_STATS_BUTTON_WIDTH := 104.0
const ARMY_ICON_CONTROL_WIDTH := 320.0
const CITY_NAME_BUTTON_WIDTH := 82.0
const ARMY_ICON_SCALE_MIN: float = 0.10
const ARMY_ICON_SCALE_MAX: float = 1.80
const ARMY_ICON_SCALE_STEP: float = 0.10
const ARMY_ICON_SCALE_DEFAULT: float = 1.00
const MAP_ZOOM_MIN: float = 1.0
const MAP_ZOOM_MAX: float = 4.0
const MAP_ZOOM_WHEEL_FACTOR: float = 1.2
const MAP_PAN_DRAG_THRESHOLD: float = 4.0
const VISUAL_SCALE_COMPACT: float = 0.80
const VISUAL_SCALE_STANDARD: float = 1.00
const VISUAL_SCALE_LARGE: float = 1.25
const VISUAL_SCALE_XL: float = 1.50
const CITY_PICK_RADIUS: float = 14.0
const EDGE_PICK_TOLERANCE: float = 10.0
const DETAIL_PANEL_WIDTH: float = 350.0
const DETAIL_PANEL_MARGIN: float = 18.0
const NATION_WINDOW_WIDTH: float = 1120.0
const NATION_WINDOW_TITLE_HEIGHT: float = 30.0
const NATION_WINDOW_HEADER_HEIGHT: float = 25.0
const NATION_WINDOW_ROW_HEIGHT: float = 31.0
const NATION_WINDOW_FOOTER_HEIGHT: float = 22.0
const NATION_WINDOW_MARGIN: float = 18.0
const NATION_TREE_INDENT: float = 14.0
const NATION_TREE_TOGGLE_SIZE: float = 14.0
const TERRAIN_BACKGROUND_PATH := GameState.TERRAIN_MAP_PATH
const ACTIVE_REDRAW_FPS: float = 30.0
const STATIC_REDRAW_FPS: float = 5.0
const PAPER_COLOR := Color(0.73, 0.61, 0.42)
const PAPER_LIGHT := Color(0.86, 0.76, 0.57)
const PAPER_DARK := Color(0.24, 0.19, 0.12)
const INK_COLOR := Color(0.105, 0.085, 0.055)
const COMMAND_GREEN := Color(0.16, 0.20, 0.14)
const ACCENT_RED := Color(0.55, 0.12, 0.10)
const ACCENT_GOLD := Color(0.88, 0.67, 0.22)

enum FormationIcon {
	INFANTRY,
	ARMOR,
}

var _cell: float = 64.0
var _origin: Vector2 = Vector2(40.0, 90.0)
var _map_size: Vector2 = Vector2(512.0, 512.0)
var _base_map_origin: Vector2 = _origin
var _base_map_size: Vector2 = _map_size
var _map_zoom: float = MAP_ZOOM_MIN
var _map_pan: Vector2 = Vector2.ZERO
var _map_drag_active: bool = false
var _map_drag_moved: bool = false
var _map_drag_start: Vector2 = Vector2.ZERO
var _map_drag_start_pan: Vector2 = Vector2.ZERO
var _display_scale: float = 1.0
var _side_margin: float = BASE_SIDE_MARGIN
var _font: Font
var _terrain_texture: Texture2D
var _province_texture: ImageTexture
var _province_boundary_segments := PackedVector2Array()
var _coast_segments := PackedVector2Array()
var _nation_boundary_segments := PackedVector2Array()
var _alliance_boundary_segments := PackedVector2Array()
var _suzerainty_boundary_segments := PackedVector2Array()
var _province_cache_ready: bool = false
var _province_ownership_revision: int = -1
var _province_diplomacy_revision: int = -1
var _blink: float = 0.0                    ## 饥饿闪烁计时
var _redraw_elapsed: float = 0.0
var _last_viewport_size: Vector2 = Vector2.ZERO
var _layout_viewport_size: Vector2 = Vector2.ZERO
var _layout_nation_count: int = -1
var _layout_map_aspect_ratio: float = -1.0
var _selected_city_id: int = -1
var _selected_edge_a: int = -1
var _selected_edge_b: int = -1
var _nation_stats_open: bool = false
var _nation_stats_window_position := Vector2(-1.0, -1.0)
var _nation_stats_drag_active: bool = false
var _nation_stats_drag_offset := Vector2.ZERO
var _nation_stats_scroll: int = 0
var _nation_stats_collapsed_nations: Dictionary = {}
var _city_names_visible: bool = true
var _army_icon_scale: float = ARMY_ICON_SCALE_DEFAULT
var _nation_list_cache_day: int = -1
var _nation_list_cache_ownership_revision: int = -1
var _nation_list_cache_diplomacy_revision: int = -1
var _nation_list_cache: Array[Dictionary] = []
var _nation_list_alive_count: int = 0
var _city_label_cache: Dictionary = {}
var _contested_city_cache_day: int = -1
var _contested_city_cache: Dictionary = {}
var _visual_animation_active: bool = false
var _army_icon_panel: PanelContainer
var _army_icon_label: Label
var _army_icon_slider: HSlider
var _city_name_button: Button

# tick 间插值：军队逻辑位置每天跳变一次，渲染在两次 tick 之间平滑过渡。
var _prev_pos: Dictionary = {}             ## army.id -> 上一 tick 末的逻辑位置
var _curr_pos: Dictionary = {}             ## army.id -> 当前 tick 末的逻辑位置
var _presented_pos: Dictionary = {}         ## army.id -> 最近一次实际绘制位置
## tick 间线性插值时基：军队按真实经过时间从 _prev_pos 匀速滑向 _curr_pos，
## 与该 tick 的计算实际跨了几帧解耦。_tick_duration 平滑跟踪 tick 的真实提交
## 节奏（详见 _sync_snapshots），避免分帧导致的「冻结数帧再猛跳」顿挫。
var _tick_elapsed: float = 0.0
var _tick_duration: float = 1.0
var _last_commit_usec: int = 0
var _last_day: int = -1


func setup(game_state: GameState, simulation: Simulation) -> void:
	state = game_state
	sim = simulation
	# Main 重开会复用 Renderer，army id 也会从 0 重排；旧快照不可跨 GameState 复用。
	_prev_pos.clear()
	_curr_pos.clear()
	_presented_pos.clear()
	_tick_elapsed = 0.0
	_tick_duration = 1.0
	_last_commit_usec = 0
	_last_day = -1
	if not sim.runtime_day_committed.is_connected(
		_on_runtime_day_committed
	):
		sim.runtime_day_committed.connect(
			_on_runtime_day_committed
		)
	_province_texture = null
	_province_boundary_segments = PackedVector2Array()
	_coast_segments = PackedVector2Array()
	_nation_boundary_segments = PackedVector2Array()
	_alliance_boundary_segments = PackedVector2Array()
	_suzerainty_boundary_segments = PackedVector2Array()
	_province_cache_ready = false
	_province_ownership_revision = -1
	_province_diplomacy_revision = -1
	_selected_city_id = -1
	_selected_edge_a = -1
	_selected_edge_b = -1
	_map_zoom = MAP_ZOOM_MIN
	_map_pan = Vector2.ZERO
	_map_drag_active = false
	_map_drag_moved = false
	_nation_list_cache_day = -1
	_nation_list_cache_ownership_revision = -1
	_nation_list_cache_diplomacy_revision = -1
	_nation_list_cache.clear()
	_nation_list_alive_count = 0
	_nation_stats_drag_active = false
	_nation_stats_scroll = 0
	_nation_stats_collapsed_nations.clear()
	_city_label_cache.clear()
	_contested_city_cache_day = -1
	_contested_city_cache.clear()
	_visual_animation_active = false
	_layout_viewport_size = Vector2.ZERO
	_layout_nation_count = -1
	_layout_map_aspect_ratio = -1.0


func _ready() -> void:
	_font = create_ui_font()
	_terrain_texture = load(TERRAIN_BACKGROUND_PATH) as Texture2D
	_create_army_icon_scale_control()


func _create_army_icon_scale_control() -> void:
	_army_icon_panel = PanelContainer.new()
	_army_icon_panel.name = "ArmyIconScaleControl"
	_army_icon_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.15, 0.10, 0.96)
	panel_style.border_color = ACCENT_GOLD.darkened(0.25)
	panel_style.set_border_width_all(1)
	panel_style.content_margin_left = 6.0
	panel_style.content_margin_right = 6.0
	panel_style.content_margin_top = 2.0
	panel_style.content_margin_bottom = 2.0
	_army_icon_panel.add_theme_stylebox_override(
		"panel",
		panel_style
	)
	add_child(_army_icon_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_army_icon_panel.add_child(row)

	_army_icon_label = Label.new()
	_army_icon_label.custom_minimum_size = Vector2(72.0, 0.0)
	_army_icon_label.add_theme_font_override("font", _font)
	_army_icon_label.add_theme_font_size_override("font_size", 10)
	_army_icon_label.add_theme_color_override(
		"font_color",
		PAPER_LIGHT
	)
	row.add_child(_army_icon_label)

	_army_icon_slider = HSlider.new()
	_army_icon_slider.min_value = ARMY_ICON_SCALE_MIN
	_army_icon_slider.max_value = ARMY_ICON_SCALE_MAX
	_army_icon_slider.step = ARMY_ICON_SCALE_STEP
	_army_icon_slider.custom_minimum_size = Vector2(126.0, 0.0)
	_army_icon_slider.tooltip_text = "调整军队兵牌大小"
	_army_icon_slider.value_changed.connect(
		_on_army_icon_scale_changed
	)
	row.add_child(_army_icon_slider)

	_city_name_button = Button.new()
	_city_name_button.name = "CityNameToggle"
	_city_name_button.toggle_mode = true
	_city_name_button.button_pressed = _city_names_visible
	_city_name_button.custom_minimum_size = Vector2(
		CITY_NAME_BUTTON_WIDTH,
		0.0
	)
	_city_name_button.add_theme_font_override("font", _font)
	_city_name_button.add_theme_font_size_override("font_size", 10)
	_city_name_button.add_theme_color_override(
		"font_color",
		PAPER_LIGHT
	)
	_city_name_button.add_theme_color_override(
		"font_hover_color",
		Color.WHITE
	)
	_city_name_button.add_theme_color_override(
		"font_pressed_color",
		PAPER_LIGHT
	)
	var city_button_normal := StyleBoxFlat.new()
	city_button_normal.bg_color = PAPER_DARK
	city_button_normal.border_color = (
		ACCENT_GOLD.darkened(0.35)
	)
	city_button_normal.set_border_width_all(1)
	city_button_normal.set_corner_radius_all(2)
	var city_button_hover := (
		city_button_normal.duplicate() as StyleBoxFlat
	)
	city_button_hover.bg_color = COMMAND_GREEN.lightened(0.12)
	city_button_hover.border_color = ACCENT_GOLD
	var city_button_pressed := (
		city_button_normal.duplicate() as StyleBoxFlat
	)
	city_button_pressed.bg_color = ACCENT_GOLD.darkened(0.45)
	city_button_pressed.border_color = PAPER_LIGHT
	_city_name_button.add_theme_stylebox_override(
		"normal",
		city_button_normal
	)
	_city_name_button.add_theme_stylebox_override(
		"hover",
		city_button_hover
	)
	_city_name_button.add_theme_stylebox_override(
		"pressed",
		city_button_pressed
	)
	_city_name_button.tooltip_text = "开启或关闭地图城市名称"
	_city_name_button.toggled.connect(
		_on_city_names_toggled
	)
	row.add_child(_city_name_button)
	set_army_icon_scale(_army_icon_scale)
	set_city_names_visible(_city_names_visible)


func _on_army_icon_scale_changed(value: float) -> void:
	set_army_icon_scale(value)


func set_army_icon_scale(value: float) -> void:
	var clamped := clampf(
		value,
		ARMY_ICON_SCALE_MIN,
		ARMY_ICON_SCALE_MAX
	)
	_army_icon_scale = clampf(
		snappedf(clamped, ARMY_ICON_SCALE_STEP),
		ARMY_ICON_SCALE_MIN,
		ARMY_ICON_SCALE_MAX
	)
	if _army_icon_slider != null:
		_army_icon_slider.set_value_no_signal(
			_army_icon_scale
		)
	if _army_icon_label != null:
		_army_icon_label.text = "兵牌 %d%%" % int(round(
			_army_icon_scale * 100.0
		))
	queue_redraw()


func army_icon_scale() -> float:
	return _army_icon_scale


func _on_city_names_toggled(visible: bool) -> void:
	set_city_names_visible(visible)


func set_city_names_visible(visible: bool) -> void:
	_city_names_visible = visible
	if _city_name_button != null:
		_city_name_button.set_pressed_no_signal(visible)
		_city_name_button.text = (
			"城名 开" if visible else "城名 关"
		)
	queue_redraw()


func city_names_visible() -> bool:
	return _city_names_visible


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
	_redraw_elapsed += _delta
	_advance_tick_interpolation(_delta)
	var previous_day := _last_day
	_sync_snapshots()
	var viewport_size := get_viewport_rect().size
	var viewport_changed := viewport_size != _last_viewport_size
	if viewport_changed:
		_last_viewport_size = viewport_size
	var target_fps := target_redraw_fps(
		sim == null or sim.paused,
		_visual_animation_active
	)
	if (
		state != null
		and (
			viewport_changed
			or state.day != previous_day
			or _redraw_elapsed >= 1.0 / target_fps
		)
	):
		_redraw_elapsed = 0.0
		queue_redraw()


static func target_redraw_fps(
	paused: bool,
	animation_active: bool
) -> float:
	return (
		ACTIVE_REDRAW_FPS
		if not paused and animation_active
		else STATIC_REDRAW_FPS
	)


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _nation_stats_drag_active:
			if (
				motion.button_mask
					& MOUSE_BUTTON_MASK_LEFT
			) == 0:
				_nation_stats_drag_active = false
				return
			_nation_stats_window_position = (
				motion.position - _nation_stats_drag_offset
			)
			_clamp_nation_stats_window_position()
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if (
			not _map_drag_active
			or (
				motion.button_mask
					& MOUSE_BUTTON_MASK_LEFT
			) == 0
		):
			return
		if (
			not _map_drag_moved
			and motion.position.distance_to(_map_drag_start)
				>= MAP_PAN_DRAG_THRESHOLD * _display_scale
		):
			_map_drag_moved = true
		if _map_drag_moved:
			_map_pan = _map_drag_start_pan + (
				motion.position - _map_drag_start
			)
			_apply_map_view_transform()
			queue_redraw()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	_compute_layout()
	var stats_rect := _nation_stats_window_rect()
	if (
		_nation_stats_open
		and stats_rect.has_point(mouse_event.position)
		and mouse_event.pressed
		and mouse_event.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN,
		]
	):
		var rows := _nation_list_rows_cached()
		var capacity := nation_stats_visible_row_capacity(
			stats_rect.size,
			_display_scale
		)
		var maximum_scroll := maxi(rows.size() - capacity, 0)
		_nation_stats_scroll = clampi(
			_nation_stats_scroll
				+ (
					-1
					if mouse_event.button_index
						== MOUSE_BUTTON_WHEEL_UP
					else 1
				),
			0,
			maximum_scroll
		)
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if (
		mouse_event.pressed
		and mouse_event.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN,
		]
		and Rect2(_origin, _map_size).has_point(
			mouse_event.position
		)
	):
		var factor := (
			MAP_ZOOM_WHEEL_FACTOR
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP
			else 1.0 / MAP_ZOOM_WHEEL_FACTOR
		)
		_set_map_zoom_at(
			_map_zoom * factor,
			mouse_event.position
		)
		get_viewport().set_input_as_handled()
		return
	if (
		mouse_event.pressed
		and mouse_event.button_index == MOUSE_BUTTON_RIGHT
	):
		if _nation_stats_open and stats_rect.has_point(
			mouse_event.position
		):
			get_viewport().set_input_as_handled()
			return
		_clear_selection()
		get_viewport().set_input_as_handled()
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var point := mouse_event.position
	if mouse_event.pressed:
		if nation_stats_button_rect(
			get_viewport_rect().size,
			_display_scale,
			_side_margin
		).has_point(point):
			_nation_stats_open = not _nation_stats_open
			if _nation_stats_open:
				_ensure_nation_stats_window_position()
				_clamp_nation_stats_scroll()
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if _nation_stats_open and stats_rect.has_point(point):
			if nation_stats_close_rect(
				stats_rect,
				_display_scale
			).has_point(point):
				_nation_stats_open = false
			elif nation_stats_title_rect(
				stats_rect,
				_display_scale
			).has_point(point):
				_nation_stats_drag_active = true
				_nation_stats_drag_offset = (
					point - stats_rect.position
				)
			else:
				_toggle_nation_tree_at_point(
					point,
					stats_rect
				)
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if Rect2(_origin, _map_size).grow(
			CITY_PICK_RADIUS * _display_scale
		).has_point(point):
			_map_drag_active = true
			_map_drag_moved = false
			_map_drag_start = point
			_map_drag_start_pan = _map_pan
			get_viewport().set_input_as_handled()
		return
		_clear_selection()
		return
	if _nation_stats_drag_active:
		_nation_stats_drag_active = false
		get_viewport().set_input_as_handled()
		return
	if not _map_drag_active:
		return
	_map_drag_active = false
	if _map_drag_moved:
		_map_drag_moved = false
		get_viewport().set_input_as_handled()
		return
	_pick_map_feature(point)
	get_viewport().set_input_as_handled()


func _pick_map_feature(point: Vector2) -> void:
	var city_id := pick_city_at_pixel(
		state,
		point,
		_origin,
		_map_size,
		CITY_PICK_RADIUS * _display_scale
	)
	if city_id >= 0:
		_selected_city_id = city_id
		_selected_edge_a = -1
		_selected_edge_b = -1
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	var edge := pick_edge_at_pixel(
		state,
		point,
		_origin,
		_map_size,
		EDGE_PICK_TOLERANCE * _display_scale
	)
	_selected_city_id = -1
	if edge == null:
		_selected_edge_a = -1
		_selected_edge_b = -1
	else:
		_selected_edge_a = edge.city_a
		_selected_edge_b = edge.city_b
	queue_redraw()


func _set_map_zoom_at(value: float, anchor: Vector2) -> void:
	var next_zoom := clampf(
		value,
		MAP_ZOOM_MIN,
		MAP_ZOOM_MAX
	)
	if is_equal_approx(next_zoom, _map_zoom):
		return
	_map_pan = map_pan_for_zoom_anchor(
		_base_map_origin,
		_base_map_size,
		_map_zoom,
		_map_pan,
		next_zoom,
		anchor
	)
	_map_zoom = next_zoom
	_apply_map_view_transform()
	queue_redraw()


func map_zoom() -> float:
	return _map_zoom


func map_pan() -> Vector2:
	return _map_pan


func _clear_selection() -> void:
	_selected_city_id = -1
	_selected_edge_a = -1
	_selected_edge_b = -1
	queue_redraw()


func _compute_layout() -> void:
	var vp := get_viewport_rect().size
	var nation_count := state.nations.size() if state != null else GameState.NATION_COUNT
	var map_aspect_ratio := clampf(
		state.map_aspect_ratio if state != null else 1.0,
		0.5,
		2.5
	)
	if (
		vp == _layout_viewport_size
		and nation_count == _layout_nation_count
		and is_equal_approx(
			map_aspect_ratio,
			_layout_map_aspect_ratio
		)
	):
		_apply_map_view_transform()
		return
	_layout_viewport_size = vp
	_layout_nation_count = nation_count
	_layout_map_aspect_ratio = map_aspect_ratio
	var layout := compute_layout_for_viewport(
		vp,
		nation_count,
		false
	)
	var span := float(layout["span"])
	_base_map_size = (
		Vector2(span, span / map_aspect_ratio)
		if map_aspect_ratio >= 1.0
		else Vector2(span * map_aspect_ratio, span)
	)
	_base_map_origin = (
		(layout["origin"] as Vector2)
		+ (Vector2(span, span) - _base_map_size) * 0.5
	)
	_display_scale = layout["display_scale"]
	_side_margin = layout["side_margin"]
	_apply_map_view_transform()
	_layout_army_icon_scale_control()
	if _nation_stats_open:
		_clamp_nation_stats_window_position()
		_clamp_nation_stats_scroll()


func _apply_map_view_transform() -> void:
	_map_zoom = clampf(
		_map_zoom,
		MAP_ZOOM_MIN,
		MAP_ZOOM_MAX
	)
	_map_pan = clamp_map_pan(
		_map_pan,
		_map_zoom,
		_base_map_size
	)
	_map_size = _base_map_size * _map_zoom
	_origin = map_view_origin(
		_base_map_origin,
		_base_map_size,
		_map_zoom,
		_map_pan
	)
	_cell = minf(_map_size.x, _map_size.y) / float(GameState.GRID)


static func clamp_map_pan(
	pan: Vector2,
	zoom: float,
	base_map_size: Vector2
) -> Vector2:
	var clamped_zoom := maxf(zoom, MAP_ZOOM_MIN)
	var limit := (
		base_map_size * (clamped_zoom - MAP_ZOOM_MIN) * 0.5
	)
	return Vector2(
		clampf(pan.x, -limit.x, limit.x),
		clampf(pan.y, -limit.y, limit.y)
	)


static func map_view_origin(
	base_origin: Vector2,
	base_map_size: Vector2,
	zoom: float,
	pan: Vector2
) -> Vector2:
	var zoomed_size := base_map_size * zoom
	return (
		base_origin
		+ (base_map_size - zoomed_size) * 0.5
		+ clamp_map_pan(pan, zoom, base_map_size)
	)


static func map_pan_for_zoom_anchor(
	base_origin: Vector2,
	base_map_size: Vector2,
	old_zoom: float,
	old_pan: Vector2,
	new_zoom: float,
	anchor: Vector2
) -> Vector2:
	var old_size := base_map_size * old_zoom
	var old_origin := map_view_origin(
		base_origin,
		base_map_size,
		old_zoom,
		old_pan
	)
	var normalized_anchor := Vector2(
		(anchor.x - old_origin.x) / maxf(old_size.x, 0.0001),
		(anchor.y - old_origin.y) / maxf(old_size.y, 0.0001)
	)
	var new_size := base_map_size * new_zoom
	var centered_origin := (
		base_origin + (base_map_size - new_size) * 0.5
	)
	var desired_pan := (
		anchor
		- centered_origin
		- normalized_anchor * new_size
	)
	return clamp_map_pan(
		desired_pan,
		new_zoom,
		base_map_size
	)


static func compute_layout_for_viewport(
	viewport_size: Vector2,
	nation_count: int,
	_nation_stats_open: bool = true
) -> Dictionary:
	var safe_size := Vector2(maxf(viewport_size.x, 1.0), maxf(viewport_size.y, 1.0))
	var display_scale := visual_scale_for_viewport(safe_size)
	var side_margin := BASE_SIDE_MARGIN * display_scale
	var available_width := maxf(safe_size.x - side_margin * 2.0, 1.0)
	var count := maxi(nation_count, 1)
	var minimum_card_width := 280.0 * display_scale
	var hud_columns := clampi(
		int(floor(available_width / maxf(minimum_card_width, 1.0))),
		1,
		count
	)
	var top_margin := BASE_HEADER_ONLY_TOP * display_scale
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


static func nation_stats_button_rect(
	viewport_size: Vector2,
	display_scale: float,
	side_margin: float
) -> Rect2:
	var size := Vector2(
		NATION_STATS_BUTTON_WIDTH * display_scale,
		22.0 * display_scale
	)
	return Rect2(
		Vector2(
			viewport_size.x - side_margin - size.x,
			8.0 * display_scale
		),
		size
	)


static func nation_stats_window_size(
	viewport_size: Vector2,
	display_scale: float,
	alive_nation_count: int
) -> Vector2:
	var margin := NATION_WINDOW_MARGIN * display_scale
	var width := maxf(
		minf(
			NATION_WINDOW_WIDTH * display_scale,
			viewport_size.x - margin * 2.0
		),
		1.0
	)
	var fixed_height := (
		NATION_WINDOW_TITLE_HEIGHT
		+ NATION_WINDOW_HEADER_HEIGHT
		+ NATION_WINDOW_FOOTER_HEIGHT
	) * display_scale
	var available_rows_height := maxf(
		viewport_size.y - margin * 2.0 - fixed_height,
		NATION_WINDOW_ROW_HEIGHT * display_scale
	)
	var capacity := maxi(
		int(floor(
			available_rows_height
				/ (NATION_WINDOW_ROW_HEIGHT * display_scale)
		)),
		1
	)
	var visible_rows := mini(maxi(alive_nation_count, 1), capacity)
	return Vector2(
		width,
		fixed_height
			+ float(visible_rows)
				* NATION_WINDOW_ROW_HEIGHT * display_scale
	)


static func nation_stats_visible_row_capacity(
	window_size: Vector2,
	display_scale: float
) -> int:
	var fixed_height := (
		NATION_WINDOW_TITLE_HEIGHT
		+ NATION_WINDOW_HEADER_HEIGHT
		+ NATION_WINDOW_FOOTER_HEIGHT
	) * display_scale
	return maxi(
		int(floor(
			(window_size.y - fixed_height)
				/ (NATION_WINDOW_ROW_HEIGHT * display_scale)
		)),
		1
	)


static func nation_stats_window_rect(
	viewport_size: Vector2,
	display_scale: float,
	position: Vector2,
	alive_nation_count: int
) -> Rect2:
	var size := nation_stats_window_size(
		viewport_size,
		display_scale,
		alive_nation_count
	)
	var margin := NATION_WINDOW_MARGIN * display_scale
	var maximum := Vector2(
		maxf(viewport_size.x - size.x - margin, margin),
		maxf(viewport_size.y - size.y - margin, margin)
	)
	return Rect2(
		Vector2(
			clampf(position.x, margin, maximum.x),
			clampf(position.y, margin, maximum.y)
		),
		size
	)


static func nation_stats_title_rect(
	window_rect: Rect2,
	display_scale: float
) -> Rect2:
	return Rect2(
		window_rect.position,
		Vector2(
			window_rect.size.x,
			NATION_WINDOW_TITLE_HEIGHT * display_scale
		)
	)


static func nation_stats_close_rect(
	window_rect: Rect2,
	display_scale: float
) -> Rect2:
	var side := 22.0 * display_scale
	return Rect2(
		Vector2(
			window_rect.end.x - side - 4.0 * display_scale,
			window_rect.position.y + 4.0 * display_scale
		),
		Vector2(side, side)
	)


static func nation_stats_row_rect(
	window_rect: Rect2,
	display_scale: float,
	visual_index: int
) -> Rect2:
	return Rect2(
		Vector2(
			window_rect.position.x,
			window_rect.position.y
				+ (
					NATION_WINDOW_TITLE_HEIGHT
					+ NATION_WINDOW_HEADER_HEIGHT
					+ float(maxi(visual_index, 0))
						* NATION_WINDOW_ROW_HEIGHT
				) * display_scale
		),
		Vector2(
			window_rect.size.x,
			NATION_WINDOW_ROW_HEIGHT * display_scale
		)
	)


static func nation_tree_toggle_rect(
	row_rect: Rect2,
	display_scale: float,
	depth: int
) -> Rect2:
	var side := NATION_TREE_TOGGLE_SIZE * display_scale
	return Rect2(
		Vector2(
			row_rect.position.x
				+ row_rect.size.x * 0.02
				+ float(maxi(depth, 0))
					* NATION_TREE_INDENT * display_scale,
			row_rect.position.y
				+ (row_rect.size.y - side) * 0.5
		),
		Vector2(side, side)
	)


func _ensure_nation_stats_window_position() -> void:
	if (
		_nation_stats_window_position.x >= 0.0
		and _nation_stats_window_position.y >= 0.0
	):
		return
	var viewport_size := get_viewport_rect().size
	var size := nation_stats_window_size(
		viewport_size,
		_display_scale,
		_nation_list_rows_cached().size()
	)
	_nation_stats_window_position = Vector2(
		(viewport_size.x - size.x) * 0.5,
		46.0 * _display_scale
	)


func _nation_stats_window_rect() -> Rect2:
	_ensure_nation_stats_window_position()
	return nation_stats_window_rect(
		get_viewport_rect().size,
		_display_scale,
		_nation_stats_window_position,
		_nation_list_rows_cached().size()
	)


func _clamp_nation_stats_window_position() -> void:
	var rect := _nation_stats_window_rect()
	_nation_stats_window_position = rect.position


func _clamp_nation_stats_scroll() -> void:
	var rows := _nation_list_rows_cached()
	var rect := _nation_stats_window_rect()
	var capacity := nation_stats_visible_row_capacity(
		rect.size,
		_display_scale
	)
	_nation_stats_scroll = clampi(
		_nation_stats_scroll,
		0,
		maxi(rows.size() - capacity, 0)
	)


func _toggle_nation_tree_at_point(
	point: Vector2,
	window_rect: Rect2
) -> bool:
	var rows := _nation_list_rows_cached()
	var capacity := nation_stats_visible_row_capacity(
		window_rect.size,
		_display_scale
	)
	for visual_index in range(
		maxi(
			mini(
				capacity,
				rows.size() - _nation_stats_scroll
			),
			0
		)
	):
		var row_index := _nation_stats_scroll + visual_index
		var row_data: Dictionary = rows[row_index]
		if not bool(row_data.get("has_subjects", false)):
			continue
		var toggle_rect := nation_tree_toggle_rect(
			nation_stats_row_rect(
				window_rect,
				_display_scale,
				visual_index
			),
			_display_scale,
			int(row_data.get("depth", 0))
		)
		if not toggle_rect.has_point(point):
			continue
		var nation_id := int(row_data["nation_id"])
		if _nation_stats_collapsed_nations.has(nation_id):
			_nation_stats_collapsed_nations.erase(nation_id)
		else:
			_nation_stats_collapsed_nations[nation_id] = true
		_nation_list_cache_day = -1
		var updated_rows := _nation_list_rows_cached()
		var updated_capacity := (
			nation_stats_visible_row_capacity(
				window_rect.size,
				_display_scale
			)
		)
		_nation_stats_scroll = clampi(
			_nation_stats_scroll,
			0,
			maxi(
				updated_rows.size() - updated_capacity,
				0
			)
		)
		return true
	return false


static func army_icon_scale_control_rect(
	viewport_size: Vector2,
	display_scale: float,
	side_margin: float
) -> Rect2:
	var stats_rect := nation_stats_button_rect(
		viewport_size,
		display_scale,
		side_margin
	)
	var size := Vector2(
		ARMY_ICON_CONTROL_WIDTH * display_scale,
		22.0 * display_scale
	)
	return Rect2(
		Vector2(
			stats_rect.position.x
				- 8.0 * display_scale
				- size.x,
			8.0 * display_scale
		),
		size
	)


func _layout_army_icon_scale_control() -> void:
	if _army_icon_panel == null:
		return
	var rect := army_icon_scale_control_rect(
		get_viewport_rect().size,
		_display_scale,
		_side_margin
	)
	_army_icon_panel.position = rect.position
	_army_icon_panel.size = rect.size
	_army_icon_label.add_theme_font_size_override(
		"font_size",
		_font_size(10)
	)
	_army_icon_label.custom_minimum_size = Vector2(
		72.0 * _display_scale,
		0.0
	)
	_army_icon_slider.custom_minimum_size = Vector2(
		112.0 * _display_scale,
		0.0
	)
	_city_name_button.add_theme_font_size_override(
		"font_size",
		_font_size(10)
	)
	_city_name_button.custom_minimum_size = Vector2(
		CITY_NAME_BUTTON_WIDTH * _display_scale,
		0.0
	)


static func visual_scale_for_viewport(viewport_size: Vector2) -> float:
	var short_side := minf(viewport_size.x, viewport_size.y)
	if short_side < 600.0:
		return VISUAL_SCALE_COMPACT
	if short_side < 900.0:
		return VISUAL_SCALE_STANDARD
	if short_side < 1400.0:
		return VISUAL_SCALE_LARGE
	return VISUAL_SCALE_XL


func _font_size(base_size: float) -> int:
	return maxi(int(round(base_size * _display_scale)), 1)


func _army_font_size(base_size: float) -> int:
	return maxi(int(round(
		base_size * _display_scale * _army_icon_scale
	)), 1)


func _city_center(city: City) -> Vector2:
	return _origin + city.map_position * _map_size


static func pick_city_at_pixel(
	game_state: GameState,
	point: Vector2,
	origin: Vector2,
	map_size: Vector2,
	radius: float
) -> int:
	var best_city := -1
	var best_distance_sq := radius * radius
	for city in game_state.cities:
		var center := origin + city.map_position * map_size
		var distance_sq := point.distance_squared_to(center)
		if (
			distance_sq < best_distance_sq
			or (
				is_equal_approx(distance_sq, best_distance_sq)
				and (best_city < 0 or city.id < best_city)
			)
		):
			best_city = city.id
			best_distance_sq = distance_sq
	return best_city


static func pick_edge_at_pixel(
	game_state: GameState,
	point: Vector2,
	origin: Vector2,
	map_size: Vector2,
	tolerance: float
) -> Edge:
	var best: Edge = null
	var best_distance := tolerance
	for edge in game_state.edges:
		if not is_edge_visible(edge):
			continue
		var from := (
			origin
			+ game_state.cities[edge.city_a].map_position * map_size
		)
		var to := (
			origin
			+ game_state.cities[edge.city_b].map_position * map_size
		)
		var distance := point_to_segment_distance(point, from, to)
		if (
			distance < best_distance
			or (
				is_equal_approx(distance, best_distance)
				and (
					best == null
					or GameState.edge_key(edge.city_a, edge.city_b)
						< GameState.edge_key(best.city_a, best.city_b)
				)
			)
		):
			best = edge
			best_distance = distance
	return best


static func point_to_segment_distance(
	point: Vector2,
	from: Vector2,
	to: Vector2
) -> float:
	var delta := to - from
	if delta.length_squared() <= 0.000001:
		return point.distance_to(from)
	var t := clampf(
		(point - from).dot(delta) / delta.length_squared(),
		0.0,
		1.0
	)
	return point.distance_to(from + delta * t)


func _on_runtime_day_committed(_day: int) -> void:
	_sync_snapshots()


## 每当模拟提交一天，以最后实际显示位置为起点抓取新的逻辑位置。
## 提交信号保证高倍速追赶时也不会跳过中间日快照。
func _sync_snapshots() -> void:
	if state == null:
		return
	if sim != null and sim.runtime_day_in_progress():
		return
	if state.day == _last_day:
		return
	var old_curr: Dictionary = _curr_pos
	var presented_before: Dictionary = _presented_pos.duplicate()
	_last_day = state.day
	# 本 tick 视觉时长跟踪「tick 提交的真实墙钟节奏」：取上一 tick 到本次提交的
	# 间隔，对 _tick_duration 做指数平滑（避免决策日的偶发长间隔突然拉长紧随的
	# 普通日视觉时长而抖动），下限 seconds_per_day。这样无论某个 tick 计算跨了
	# 几帧，军队都在与实际推进节奏相称、且平稳变化的时长内匀速滑完这一步。
	var now_usec := Time.get_ticks_usec()
	var day_seconds := sim.seconds_per_day if sim != null else 1.0
	if _last_commit_usec > 0:
		var measured := maxf(
			float(now_usec - _last_commit_usec) / 1_000_000.0,
			day_seconds
		)
		_tick_duration = lerpf(_tick_duration, measured, 0.35)
	else:
		_tick_duration = day_seconds
	_last_commit_usec = now_usec
	_tick_elapsed = 0.0
	_prev_pos = {}
	_curr_pos = {}
	_visual_animation_active = not state.battles.is_empty()
	for army in state.armies:
		var logical_position := _logical_grid_pos(army)
		_curr_pos[army.id] = logical_position
		_prev_pos[army.id] = presented_before.get(
			army.id,
			old_curr.get(army.id, logical_position)
		)
		if (
			army.size > 0
			and (
				army.state in [
					Army.State.MOVING,
					Army.State.RETREATING,
				]
				or army.starving
			)
		):
			_visual_animation_active = true
# ================================================================== 绘制

func _draw() -> void:
	if state == null:
		return
	_compute_layout()
	_draw_paper_canvas()
	_draw_terrain_background()
	_ensure_province_visual_cache()
	_draw_province_fills()
	_draw_rivers()
	_draw_province_boundaries()
	_draw_edges()
	_draw_selection_highlight()
	_draw_national_boundaries()
	_draw_campaign_arrows()
	_draw_cities()
	_draw_battles()
	_draw_armies()
	_draw_selection_detail()
	_draw_hud()


func _draw_paper_canvas() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(
		Rect2(Vector2.ZERO, viewport_size),
		Color(0.10, 0.085, 0.060),
		true
	)
	var map_rect := Rect2(_origin, _map_size)
	draw_rect(
		map_rect.grow(9.0 * _display_scale),
		Color(0.02, 0.018, 0.014, 0.60),
		true
	)
	draw_rect(map_rect, PAPER_COLOR, true)
	# 低成本确定性纸张纤维；不使用随机数，不影响模拟确定性。
	for fiber in range(42):
		var y_ratio := fmod(float(fiber * 37 + 11), 101.0) / 101.0
		var x_ratio := fmod(float(fiber * 53 + 7), 97.0) / 97.0
		var length_ratio := 0.08 + fmod(float(fiber * 19), 23.0) / 100.0
		var from := _origin + Vector2(
			x_ratio * _map_size.x,
			y_ratio * _map_size.y
		)
		var to := from + Vector2(
			minf(length_ratio * _map_size.x, _origin.x + _map_size.x - from.x),
			(float((fiber % 5) - 2)) * 0.8 * _display_scale
		)
		draw_line(
			from,
			to,
			Color(0.20, 0.13, 0.07, 0.075),
			1.0
		)
	draw_rect(
		map_rect,
		Color(0.08, 0.055, 0.025, 0.92),
		false,
		3.0 * _display_scale
	)


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
		Color(0.62, 0.52, 0.35, 0.52)
	)
	# 赭色罩层把卫星底图统一进战略图纸色域。
	draw_rect(
		Rect2(_origin, _map_size),
		Color(0.30, 0.22, 0.12, 0.22),
		true
	)


func _draw_rivers() -> void:
	for river in state.river_paths:
		if river.size() < 2:
			continue
		var points := PackedVector2Array()
		for normalized_point in river:
			points.append(_origin + normalized_point * _map_size)
		draw_polyline(
			points,
				Color(0.08, 0.16, 0.19, 0.86),
				5.0 * _display_scale,
			true
		)
		draw_polyline(
			points,
				Color(0.24, 0.48, 0.55, 0.90),
				2.0 * _display_scale,
			true
		)


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
		_suzerainty_boundary_segments = geometry["suzerainty"]
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
			var base := paper_nation_color(
				game_state.nations[recognized_owner].color
			)
			base.a = 0.38
			if current_owner != recognized_owner and (x + y) % 9 < 3:
				var occupation := paper_nation_color(
					game_state.nations[current_owner].color
				).darkened(0.08)
				occupation.a = 0.78
				base = occupation
			image.set_pixel(x, y, base)
	return image


static func paper_nation_color(color: Color) -> Color:
	var paper_tint := Color(0.64, 0.52, 0.33)
	var result := color.lerp(paper_tint, 0.48)
	result.s = minf(result.s, 0.58)
	return result


static func build_province_boundary_segments(
	game_state: GameState
) -> Dictionary:
	var province := PackedVector2Array()
	var nation := PackedVector2Array()
	var alliance := PackedVector2Array()
	var suzerainty := PackedVector2Array()
	var coast := PackedVector2Array()
	var size := game_state.province_map_size
	if size.x <= 0 or size.y <= 0:
		return {
			"province": province,
			"nation": nation,
			"alliance": alliance,
			"suzerainty": suzerainty,
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
					if _province_owners_same_peaceful_suzerainty(
						game_state, province_id, right
					):
						_append_segment(
							suzerainty, Vector2(x1, y0), Vector2(x1, y1)
						)
					else:
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
					if _province_owners_same_peaceful_suzerainty(
						game_state, province_id, bottom
					):
						_append_segment(
							suzerainty, Vector2(x0, y1), Vector2(x1, y1)
						)
					else:
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
		"suzerainty": suzerainty,
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


static func _province_owners_same_peaceful_suzerainty(
	game_state: GameState,
	province_a: int,
	province_b: int
) -> bool:
	if province_a < 0 or province_b < 0:
		return false
	var owner_a := game_state.cities[province_a].owner_nation
	var owner_b := game_state.cities[province_b].owner_nation
	return (
		game_state.suzerainty_root(owner_a)
			== game_state.suzerainty_root(owner_b)
		and game_state.is_allied(owner_a, owner_b)
		and not game_state.is_in_civil_war(owner_a)
		and not game_state.is_in_civil_war(owner_b)
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
				Color(0.20, 0.14, 0.08, 0.50),
			maxf(1.0 * _display_scale, 1.0),
			true
		)


func _draw_national_boundaries() -> void:
	var coast_pixels := _normalized_segments_to_pixels(_coast_segments)
	if not coast_pixels.is_empty():
		draw_multiline(
			coast_pixels,
				Color(0.055, 0.040, 0.022, 0.96),
				5.0 * _display_scale,
			true
		)
		draw_multiline(
			coast_pixels,
				Color(0.88, 0.75, 0.50, 0.76),
				1.6 * _display_scale,
			true
		)
	if not _nation_boundary_segments.is_empty():
		var nation_pixels := _normalized_segments_to_pixels(
			_nation_boundary_segments
		)
		draw_multiline(
			nation_pixels,
				Color(0.055, 0.035, 0.018, 0.98),
				7.0 * _display_scale,
			true
		)
		draw_multiline(
			nation_pixels,
				Color(0.91, 0.69, 0.30, 0.92),
				2.2 * _display_scale,
			true
		)
	if not _alliance_boundary_segments.is_empty():
		draw_multiline(
			_normalized_segments_to_pixels(_alliance_boundary_segments),
				Color(0.20, 0.48, 0.50, 0.95),
				3.0 * _display_scale,
			true
		)
	if not _suzerainty_boundary_segments.is_empty():
		draw_multiline(
			_normalized_segments_to_pixels(
				_suzerainty_boundary_segments
			),
			Color(0.0, 0.0, 0.0, 0.92),
			maxf(1.25 * _display_scale, 1.0),
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
		var alpha := campaign_arrow_alpha(state.day, event)
		if alpha <= 0.0:
			continue
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


static func campaign_arrow_alpha(
	game_day: int,
	event: Dictionary
) -> float:
	var start_day := int(event.get("start_day", game_day))
	var end_day := int(event.get("end_day", game_day))
	if game_day < start_day or game_day > end_day:
		return 0.0
	var remaining_days := end_day - game_day
	return clampf(
		(float(remaining_days) + 1.0) / 4.0,
		0.35,
		1.0
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
	arrow_color = paper_nation_color(arrow_color)
	arrow_color.a = 0.96 * alpha
	draw_polyline(
		points,
		Color(0.04, 0.025, 0.012, 0.88 * alpha),
		10.0 * _display_scale,
		true
	)
	draw_polyline(points, arrow_color, 5.5 * _display_scale, true)
	var flow_phase := fmod(_blink * 0.18 + float(curve_index) * 0.07, 0.24)
	for chevron_index in range(4):
		var t := 0.12 + flow_phase + float(chevron_index) * 0.24
		if t >= 0.94:
			continue
		var point := _quadratic_point(start, control, finish, t)
		var next := _quadratic_point(
			start,
			control,
			finish,
			minf(t + 0.02, 1.0)
		)
		var flow_direction := (next - point).normalized()
		var flow_normal := Vector2(-flow_direction.y, flow_direction.x)
		var tail := 5.0 * _display_scale
		draw_line(
			point,
			point - flow_direction * tail + flow_normal * tail * 0.55,
			Color(PAPER_LIGHT, alpha),
			1.6 * _display_scale
		)
		draw_line(
			point,
			point - flow_direction * tail - flow_normal * tail * 0.55,
			Color(PAPER_LIGHT, alpha),
			1.6 * _display_scale
		)
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
	draw_polyline(
		PackedVector2Array([
			head[1],
			head[0],
			head[2],
		]),
		Color(0.04, 0.025, 0.012, 0.90 * alpha),
		1.8 * _display_scale
	)


static func _quadratic_point(
	start: Vector2,
	control: Vector2,
	finish: Vector2,
	t: float
) -> Vector2:
	var inv := 1.0 - t
	return (
		start * inv * inv
		+ control * 2.0 * inv * t
		+ finish * t * t
	)


func _draw_edges() -> void:
	for e in state.edges:
		var pa := _city_center(state.cities[e.city_a])
		var pb := _city_center(state.cities[e.city_b])
		var danger := clampf(e.danger, 0.0, 1.0)
		if not is_edge_visible(e):
			continue
		if e.kind == Edge.Kind.RIVER:
			var river_color := Color(0.20, 0.45, 0.52)
			river_color = river_color.lerp(
				Color(0.42, 0.25, 0.32),
				danger * 0.45
			)
			draw_line(
				pa,
				pb,
				Color(0.04, 0.075, 0.075, 0.90),
				7.0 * _display_scale
			)
			draw_line(
				pa,
				pb,
				river_color,
				4.5 * _display_scale
			)
			continue
		if e.kind == Edge.Kind.LANDING:
			draw_dashed_line(
				pa,
				pb,
					Color(0.62, 0.12, 0.09, 0.96),
				3.0 * _display_scale,
				6.0 * _display_scale
			)
			continue
		var road_level := 1
		if e.max_manpower >= 100000:
			road_level = 4
		elif e.max_manpower >= 60000:
			road_level = 3
		elif e.max_manpower >= Edge.TERRAIN_STANDARD_MANPOWER:
			road_level = 2
		var road_colors: Array[Color] = [
			Color(0.22, 0.17, 0.11),
			Color(0.30, 0.22, 0.13),
			Color(0.43, 0.31, 0.16),
			Color(0.60, 0.42, 0.18),
		]
		var road_widths: Array[float] = [1.5, 2.5, 4.0, 6.0]
		var col: Color = road_colors[road_level - 1]
		col = col.lerp(ACCENT_RED, danger * 0.48)
		var width: float = road_widths[road_level - 1] * _display_scale
		if road_level >= 3:
			draw_line(
				pa, pb, Color(0.04, 0.028, 0.015, 0.82),
				width + 2.0 * _display_scale
			)
		if e.occupied:
			col = col.lerp(ACCENT_GOLD, 0.55)
			width += 1.5 * _display_scale
		draw_line(pa, pb, col, width)
		if danger >= 0.72:
			_draw_edge_danger_ticks(pa, pb, danger)


func _draw_edge_danger_ticks(
	from: Vector2,
	to: Vector2,
	danger: float
) -> void:
	var delta := to - from
	if delta.length_squared() < 16.0:
		return
	var direction := delta.normalized()
	var normal := Vector2(-direction.y, direction.x)
	var count := clampi(int(round(delta.length() / 34.0)), 2, 6)
	for index in range(1, count + 1):
		var t := float(index) / float(count + 1)
		var center := from.lerp(to, t)
		var half := (2.0 + danger * 2.0) * _display_scale
		draw_line(
			center - normal * half,
			center + normal * half,
			Color(0.45, 0.08, 0.055, 0.88),
			1.2 * _display_scale
		)


func _draw_selection_highlight() -> void:
	if _selected_edge_a >= 0 and _selected_edge_b >= 0:
		var edge := state.edge_of(_selected_edge_a, _selected_edge_b)
		if edge != null:
			var from := _city_center(state.cities[edge.city_a])
			var to := _city_center(state.cities[edge.city_b])
			draw_line(
				from,
				to,
				Color(0.04, 0.025, 0.01, 0.95),
				10.0 * _display_scale
			)
			draw_dashed_line(
				from,
				to,
				ACCENT_GOLD,
				4.0 * _display_scale,
				8.0 * _display_scale
			)
	if _selected_city_id >= 0 and _selected_city_id < state.cities.size():
		var center := _city_center(state.cities[_selected_city_id])
		var radius := 15.0 * _display_scale
		draw_arc(
			center,
			radius,
			0.0,
			TAU,
			32,
			Color(0.04, 0.025, 0.01, 0.96),
			5.0 * _display_scale
		)
		draw_arc(
			center,
			radius,
			0.0,
			TAU,
			32,
			ACCENT_GOLD,
			2.0 * _display_scale
		)


static func is_edge_visible(edge: Edge) -> bool:
	return edge != null and edge.max_manpower > 0


func _draw_cities() -> void:
	var half := 7.0 * _display_scale
	var contested_cities := _contested_city_ids_cached()
	for city in state.cities:
		var center := _city_center(city)
		var rect := Rect2(center - Vector2(half, half), Vector2(half * 2, half * 2))
		var base := paper_nation_color(
			state.nations[city.owner_nation].color
		)
		var border := (
			ACCENT_RED
			if contested_cities.has(city.id)
			else INK_COLOR
		)
		if city.is_dock:
			_draw_dock_symbol(center, half, base, border)
		else:
			draw_rect(rect.grow(2.0 * _display_scale), PAPER_LIGHT, true)
			draw_rect(rect, base, true)
			draw_rect(
				rect,
				border,
				false,
				2.0 * _display_scale
			)
			draw_line(
				rect.position,
				rect.end,
				Color(INK_COLOR, 0.42),
				1.0 * _display_scale
			)
			draw_line(
				Vector2(rect.end.x, rect.position.y),
				Vector2(rect.position.x, rect.end.y),
				Color(INK_COLOR, 0.42),
				1.0 * _display_scale
			)
		if city.is_capital:
			_draw_star(
				center + Vector2(0.0, -half - 5.0 * _display_scale),
				4.0 * _display_scale,
				ACCENT_GOLD
			)
		_draw_city_resource_markers(city, center, half)
		if not _city_names_visible:
			continue
		if not _city_label_cache.has(city.id):
			_city_label_cache[city.id] = city_label_text(city)
		var label := str(_city_label_cache[city.id])
		var label_position := center + Vector2(
			half + 4.0 * _display_scale,
			-2.0 * _display_scale
		)
		var label_width := float(label.length() * _font_size(8)) * 0.72
		draw_rect(
			Rect2(
				label_position + Vector2(-2.0, -9.0) * _display_scale,
				Vector2(label_width + 4.0 * _display_scale, 12.0 * _display_scale)
			),
			Color(PAPER_LIGHT, 0.82),
			true
		)
		draw_string(
			_font,
			label_position,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_font_size(8),
			INK_COLOR
		)


static func city_label_text(city: City) -> String:
	if city == null:
		return ""
	var label := ("港%d" if city.is_dock else "城%d") % city.id
	if city.is_food_hub:
		label += " 粮"
	if city.is_manpower_hub:
		label += " 人"
	return label


func _draw_city_resource_markers(
	city: City,
	center: Vector2,
	half: float
) -> void:
	var marker_center := center + Vector2(
		half * 0.78,
		-half * 0.78
	)
	var marker_size := 2.5 * _display_scale
	if city.is_food_hub:
		var food_marker := PackedVector2Array([
			marker_center + Vector2(0.0, -marker_size),
			marker_center + Vector2(marker_size, marker_size),
			marker_center + Vector2(-marker_size, marker_size),
		])
		draw_colored_polygon(
			food_marker,
			Color(0.18, 0.42, 0.16)
		)
		draw_polyline(
			PackedVector2Array([
				food_marker[0],
				food_marker[1],
				food_marker[2],
				food_marker[0],
			]),
			INK_COLOR,
			0.8 * _display_scale
		)
	if city.is_manpower_hub:
		var manpower_center := marker_center + Vector2(
			0.0,
			5.0 * _display_scale if city.is_food_hub else 0.0
		)
		var manpower_marker := PackedVector2Array([
			manpower_center + Vector2(0.0, -marker_size),
			manpower_center + Vector2(marker_size, 0.0),
			manpower_center + Vector2(0.0, marker_size),
			manpower_center + Vector2(-marker_size, 0.0),
		])
		draw_colored_polygon(
			manpower_marker,
			Color(0.56, 0.14, 0.10)
		)
		draw_polyline(
			PackedVector2Array(Array(manpower_marker) + [
				manpower_marker[0],
			]),
			INK_COLOR,
			0.8 * _display_scale
		)


func _draw_dock_symbol(
	center: Vector2,
	half: float,
	fill: Color,
	border: Color
) -> void:
	draw_circle(center, half * 0.92, PAPER_LIGHT)
	draw_circle(center, half * 0.72, fill)
	draw_arc(
		center,
		half * 0.92,
		0.0,
		TAU,
		24,
		border,
		2.0 * _display_scale
	)
	draw_line(
		center + Vector2(0.0, -half * 0.62),
		center + Vector2(0.0, half * 0.70),
		border,
		1.8 * _display_scale
	)
	draw_arc(
		center + Vector2(0.0, half * 0.18),
		half * 0.55,
		0.15,
		PI - 0.15,
		12,
		border,
		1.8 * _display_scale
	)


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(10):
		var angle := -PI / 2.0 + float(index) * PI / 5.0
		var point_radius := radius if index % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * point_radius)
	draw_colored_polygon(points, color)
	draw_polyline(
		PackedVector2Array(Array(points) + [points[0]]),
		INK_COLOR,
		1.0 * _display_scale
	)


static func contested_city_ids(game_state: GameState) -> Dictionary:
	var result := {}
	for battle in game_state.battles:
		if not battle.finished and battle.city != null:
			result[battle.city.id] = true
	return result


func _contested_city_ids_cached() -> Dictionary:
	if _contested_city_cache_day != state.day:
		_contested_city_cache_day = state.day
		_contested_city_cache = contested_city_ids(state)
	return _contested_city_cache


func _draw_armies() -> void:
	var blink_on := fmod(_blink, 0.6) < 0.3
	var pulse := 0.5 + 0.5 * sin(_blink * 6.0)
	var icon_scale := _display_scale * _army_icon_scale
	for army in state.armies:
		if army.size <= 0:
			continue
		var profile := army_counter_profile(army.max_size)
		var is_heavy := (
			int(profile["icon"]) == FormationIcon.ARMOR
		)
		var pos := (
			_army_position(army)
			+ _army_counter_offset(army.id) * icon_scale
		)
		var width := float(profile["width"]) * icon_scale
		var height := float(profile["height"]) * icon_scale
		var rect := Rect2(
			pos - Vector2(width, height) * 0.5,
			Vector2(width, height)
		)
		if army.state == Army.State.HOLDING:
			var h := 18.0 * icon_scale
			draw_polyline(
				PackedVector2Array([
					pos + Vector2(0.0, -h),
					pos + Vector2(h, 0.0),
					pos + Vector2(0.0, h),
					pos + Vector2(-h, 0.0),
					pos + Vector2(0.0, -h),
				]),
				Color(0.12, 0.25, 0.20, 0.88),
				2.0 * icon_scale
			)
		var counter_color := paper_nation_color(
			state.nations[army.owner_nation].color
		).lightened(0.15)
		if army.starving and blink_on:
			counter_color = PAPER_LIGHT
		_draw_army_counter_body(
			rect,
			counter_color,
			paper_nation_color(
				state.nations[army.owner_nation].color
			),
			is_heavy,
			icon_scale
		)
		_draw_army_formation_symbol(
			rect,
			int(profile["icon"]),
			icon_scale
		)
		_draw_formation_marks(
			rect,
			int(profile["marks"]),
			icon_scale
		)
		var state_code := _army_state_code(army.state)
		draw_string(
			_font,
			rect.position + Vector2(2.5, 4.5) * icon_scale,
			state_code,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_army_font_size(6),
			PAPER_LIGHT
		)
		draw_string(
			_font,
			Vector2(
				rect.position.x + 2.0 * icon_scale,
				rect.end.y - 2.5 * icon_scale
			),
			"%dK" % int(round(float(army.size) / 1000.0)),
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 4.0 * icon_scale,
			_army_font_size(7),
			INK_COLOR
		)
		if (
			army.offensive_attack_multiplier > 1.0
			and state.day < army.offensive_bonus_until_day
		):
			var pennant := PackedVector2Array([
				rect.position + Vector2(rect.size.x * 0.55, 0.0),
				rect.position + Vector2(rect.size.x * 0.82, 0.0),
				rect.position + Vector2(rect.size.x * 0.68, -7.0 * icon_scale),
			])
			draw_colored_polygon(pennant, ACCENT_GOLD)
			draw_polyline(
				PackedVector2Array([
					pennant[0],
					pennant[1],
					pennant[2],
					pennant[0],
				]),
				INK_COLOR,
				1.0 * icon_scale
			)
		if army.state == Army.State.FIGHTING:
			draw_rect(
				rect.grow((2.0 + pulse * 2.0) * icon_scale),
				Color(0.70, 0.10, 0.07, 0.55 + 0.35 * pulse),
				false,
				2.2 * icon_scale
			)
		elif army.state == Army.State.RECOVERING:
			draw_rect(
				rect.grow(2.0 * icon_scale),
				Color(0.20, 0.42, 0.45, 0.90),
				false,
				2.0 * icon_scale
			)
		_draw_morale_bar(
			rect,
				army.combat_morale_ratio(),
			icon_scale
		)


static func army_counter_profile(max_size: int) -> Dictionary:
	if max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
		return {
			"icon": FormationIcon.ARMOR,
			"width": 44.0,
			"height": 26.0,
			"marks": 3,
		}
	return {
		"icon": FormationIcon.INFANTRY,
		"width": 34.0,
		"height": 23.0,
		"marks": 1,
	}


func _draw_army_counter_body(
	rect: Rect2,
	fill: Color,
	nation_color: Color,
	is_heavy: bool,
	icon_scale: float
) -> void:
	var shadow_offset := Vector2(2.5, 3.0) * icon_scale
	if not is_heavy:
		draw_rect(
			Rect2(rect.position + shadow_offset, rect.size),
			Color(0.03, 0.02, 0.01, 0.58),
			true
		)
		draw_rect(rect, fill, true)
		draw_rect(
			Rect2(
				rect.position,
				Vector2(rect.size.x, 5.0 * icon_scale)
			),
			nation_color,
			true
		)
		draw_rect(
			rect,
			INK_COLOR,
			false,
			2.0 * icon_scale
		)
		return
	var chamfer := 4.0 * icon_scale
	var shape := _chamfered_counter_points(
		rect,
		chamfer
	)
	var shadow_shape := PackedVector2Array()
	for point in shape:
		shadow_shape.append(point + shadow_offset)
	draw_colored_polygon(
		shadow_shape,
		Color(0.03, 0.02, 0.01, 0.60)
	)
	draw_colored_polygon(shape, fill)
	draw_line(
		Vector2(
			rect.position.x + chamfer,
			rect.position.y + 2.5 * icon_scale
		),
		Vector2(
			rect.end.x - chamfer,
			rect.position.y + 2.5 * icon_scale
		),
		nation_color,
		5.0 * icon_scale
	)
	draw_polyline(
		PackedVector2Array(Array(shape) + [shape[0]]),
		INK_COLOR,
		2.2 * icon_scale
	)


static func _chamfered_counter_points(
	rect: Rect2,
	chamfer: float
) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position + Vector2(chamfer, 0.0),
		Vector2(rect.end.x - chamfer, rect.position.y),
		Vector2(rect.end.x, rect.position.y + chamfer),
		rect.end - Vector2(0.0, chamfer),
		rect.end - Vector2(chamfer, 0.0),
		Vector2(rect.position.x + chamfer, rect.end.y),
		Vector2(rect.position.x, rect.end.y - chamfer),
		rect.position + Vector2(0.0, chamfer),
	])


func _draw_army_formation_symbol(
	rect: Rect2,
	icon: int,
	icon_scale: float
) -> void:
	var center := rect.get_center() + Vector2(
		0.0,
		1.5 * icon_scale
	)
	if icon == FormationIcon.ARMOR:
		var ellipse := PackedVector2Array()
		for index in range(17):
			var angle := TAU * float(index) / 16.0
			ellipse.append(
				center + Vector2(
					cos(angle) * 7.0,
					sin(angle) * 3.6
				) * icon_scale
			)
		draw_polyline(
			ellipse,
			INK_COLOR,
			1.5 * icon_scale
		)
		for track_offset in [-5.0, 5.0]:
			draw_line(
				center + Vector2(
					-8.0,
					track_offset
				) * icon_scale,
				center + Vector2(
					8.0,
					track_offset
				) * icon_scale,
				INK_COLOR,
				1.0 * icon_scale
			)
		return
	draw_line(
		center + Vector2(-8.0, -5.0) * icon_scale,
		center + Vector2(8.0, 5.0) * icon_scale,
		INK_COLOR,
		1.4 * icon_scale
	)
	draw_line(
		center + Vector2(8.0, -5.0) * icon_scale,
		center + Vector2(-8.0, 5.0) * icon_scale,
		INK_COLOR,
		1.4 * icon_scale
	)


func _draw_formation_marks(
	rect: Rect2,
	count: int,
	icon_scale: float
) -> void:
	var mark_width := 1.8 * icon_scale
	var gap := 1.4 * icon_scale
	var total_width := (
		float(count) * mark_width
		+ float(maxi(count - 1, 0)) * gap
	)
	var start_x := rect.end.x - 3.0 * icon_scale - total_width
	for index in range(count):
		draw_rect(
			Rect2(
				Vector2(
					start_x + float(index) * (mark_width + gap),
					rect.position.y + 1.0 * icon_scale
				),
				Vector2(mark_width, 3.0 * icon_scale)
			),
			PAPER_LIGHT,
			true
		)


static func _army_counter_offset(army_id: int) -> Vector2:
	var offsets := [
		Vector2.ZERO,
		Vector2(-3.0, -2.0),
		Vector2(3.0, -2.0),
		Vector2(-3.0, 2.0),
		Vector2(3.0, 2.0),
	]
	return offsets[posmod(army_id, offsets.size())]


static func _army_state_code(state_value: int) -> String:
	match state_value:
		Army.State.MOVING:
			return "M"
		Army.State.FIGHTING:
			return "F"
		Army.State.RETREATING:
			return "R"
		Army.State.RECOVERING:
			return "C"
		Army.State.HOLDING:
			return "H"
	return "I"


## 兵牌下沿士气条：红(0)→黄(0.5)→绿(1)。
func _draw_morale_bar(
	rect: Rect2,
	morale: float,
	icon_scale: float
) -> void:
	var w := rect.size.x
	var h := 3.0 * icon_scale
	var top_left := Vector2(
		rect.position.x,
		rect.end.y + 2.0 * icon_scale
	)
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0, 0, 0, 0.55), true)
	var m := clampf(morale, 0.0, 1.0)
	var fill := (
		Color(0.18, 0.46, 0.22)
		if m > 0.5
		else Color(0.66, 0.15 + m * 0.35, 0.08)
	)
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
				Color(0.66, 0.10, 0.07, 0.35 + 0.35 * pulse),
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
					Color(0.86, 0.63, 0.20, 0.92),
				2.0 * _display_scale
			)
			draw_circle(p, r_in, ACCENT_GOLD)
		# 回合数
		draw_string(
			_font,
			p + Vector2(6, -8) * _display_scale,
			"R%d" % b.round_no,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_font_size(11),
				PAPER_LIGHT
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
					Color(0.22, 0.48, 0.50, 0.95),
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


## 军队渲染位置：按 tick 内真实经过时间，在上一 tick 位置与当前 tick 位置之间
## 匀速插值（smoothstep 收尾更自然）。进度 t 用墙钟时间而非「目标是否更新」驱动，
## 因此 tick 计算横跨多帧（分帧）时军队仍匀速前进，不会冻结再猛跳。
func _army_position(army: Army) -> Vector2:
	var curr: Vector2 = _curr_pos.get(army.id, _logical_grid_pos(army))
	var prev: Vector2 = _prev_pos.get(army.id, curr)
	var t := clampf(_tick_elapsed / maxf(_tick_duration, 0.0001), 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)
	var g := prev.lerp(curr, eased)
	_presented_pos[army.id] = g
	return _grid_to_pixel(g)


## 累积当前 tick 已经过的真实时间。tick 计算进行中（分帧）也照常累积——军队据此
## 持续朝 _curr_pos 匀速滑行；暂停/结束则冻结进度。目标位置的轮转仍由 tick 提交
## 时的 _sync_snapshots 负责。
func _advance_tick_interpolation(delta: float) -> void:
	if (
		sim == null
		or state == null
		or sim.paused
	):
		return
	_tick_elapsed += maxf(delta, 0.0)


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


static func nation_list_rows(
	game_state: GameState,
	collapsed_nations: Dictionary = {}
) -> Array[Dictionary]:
	var city_count_by_nation: Array[int] = []
	var army_count_by_nation: Array[int] = []
	var troops_by_nation: Array[int] = []
	for values in [
		city_count_by_nation,
		army_count_by_nation,
		troops_by_nation,
	]:
		values.resize(game_state.nations.size())
		values.fill(0)
	for city in game_state.cities:
		if (
			city.owner_nation >= 0
			and city.owner_nation < game_state.nations.size()
		):
			city_count_by_nation[city.owner_nation] += 1
	for army in game_state.armies:
		if (
			army.owner_nation < 0
			or army.owner_nation >= game_state.nations.size()
			or army.size <= 0
		):
			continue
		army_count_by_nation[army.owner_nation] += 1
		troops_by_nation[army.owner_nation] += army.size
	var row_by_nation := {}
	var visible_nation_ids: Array[int] = []
	var resource_cache := {}
	for nation in game_state.nations:
		if (
			not nation.alive
			or city_count_by_nation[nation.id] <= 0
		):
			continue
		var report := DiplomacyAI.resource_report(
			game_state,
			nation.id,
			resource_cache
		)
		var wars := game_state.wars_of(nation.id)
		var allies := game_state.allies_of(nation.id)
		row_by_nation[nation.id] = {
			"nation_id": nation.id,
			"color": nation.color,
			"at_war": not wars.is_empty(),
			"identity": "国%d  %s" % [
				nation.id,
				_nation_relation_text(game_state, nation.id),
			],
			"military": "城%d  军%d/%d  人%d" % [
				city_count_by_nation[nation.id],
				army_count_by_nation[nation.id],
				troops_by_nation[nation.id],
				nation.manpower_pool,
			],
			"economy": "金%d  月%+d  贡%+d  粮%d/%d" % [
				nation.treasury_gold,
				int(report["monthly_gold_balance"]),
				int(report["monthly_tribute_income"])
					- int(report["monthly_tribute_expense"]),
				nation.granary_food,
				int(ceil(float(report["monthly_food_demand"]))),
			],
			"diplomacy": "战%s  盟%s" % [
				str(wars),
				str(allies),
			],
			"action": nation_action_summary(game_state, nation.id),
		}
		visible_nation_ids.append(nation.id)
	var children_by_parent := {}
	var root_ids: Array[int] = []
	for nation_id in visible_nation_ids:
		var parent_id := (
			game_state.overlord_of(nation_id)
			if game_state.is_vassal(nation_id)
			else -1
		)
		if (
			parent_id < 0
			or parent_id == nation_id
			or not row_by_nation.has(parent_id)
		):
			(row_by_nation[nation_id] as Dictionary)[
				"parent_nation_id"
			] = -1
			root_ids.append(nation_id)
			continue
		(row_by_nation[nation_id] as Dictionary)[
			"parent_nation_id"
		] = parent_id
		if not children_by_parent.has(parent_id):
			children_by_parent[parent_id] = [] as Array[int]
		(
			children_by_parent[parent_id] as Array[int]
		).append(nation_id)
	root_ids.sort()
	for child_values in children_by_parent.values():
		(child_values as Array[int]).sort()
	var rows: Array[Dictionary] = []
	var visited := {}
	for root_id in root_ids:
		_append_nation_tree_rows(
			rows,
			root_id,
			0,
			row_by_nation,
			children_by_parent,
			collapsed_nations,
			visited
		)
	# 宗藩数据若暂时损坏成环，仍保证每个存活国家显示一次。
	for nation_id in visible_nation_ids:
		if visited.has(nation_id):
			continue
		_append_nation_tree_rows(
			rows,
			nation_id,
			0,
			row_by_nation,
			children_by_parent,
			collapsed_nations,
			visited
		)
	return rows


static func _append_nation_tree_rows(
	rows: Array[Dictionary],
	nation_id: int,
	depth: int,
	row_by_nation: Dictionary,
	children_by_parent: Dictionary,
	collapsed_nations: Dictionary,
	visited: Dictionary
) -> void:
	if visited.has(nation_id) or not row_by_nation.has(nation_id):
		return
	visited[nation_id] = true
	var children: Array[int] = (
		children_by_parent.get(
			nation_id,
			[] as Array[int]
		) as Array[int]
	)
	var row: Dictionary = (
		row_by_nation[nation_id] as Dictionary
	).duplicate()
	row["depth"] = depth
	row["has_subjects"] = not children.is_empty()
	row["expanded"] = (
		not children.is_empty()
		and not collapsed_nations.has(nation_id)
	)
	rows.append(row)
	if collapsed_nations.has(nation_id):
		for child_id in children:
			_mark_nation_tree_hidden(
				child_id,
				children_by_parent,
				visited
			)
		return
	for child_id in children:
		_append_nation_tree_rows(
			rows,
			child_id,
			depth + 1,
			row_by_nation,
			children_by_parent,
			collapsed_nations,
			visited
		)


static func _mark_nation_tree_hidden(
	nation_id: int,
	children_by_parent: Dictionary,
	visited: Dictionary
) -> void:
	if visited.has(nation_id):
		return
	visited[nation_id] = true
	var children: Array[int] = (
		children_by_parent.get(
			nation_id,
			[] as Array[int]
		) as Array[int]
	)
	for child_id in children:
		_mark_nation_tree_hidden(
			child_id,
			children_by_parent,
			visited
		)


static func nation_list_alive_count(game_state: GameState) -> int:
	var nations_with_cities := {}
	for city in game_state.cities:
		nations_with_cities[city.owner_nation] = true
	var result := 0
	for nation in game_state.nations:
		if nation.alive and nations_with_cities.has(nation.id):
			result += 1
	return result


static func _nation_relation_text(
	game_state: GameState,
	nation_id: int
) -> String:
	if game_state.is_vassal(nation_id):
		var overlord_id := game_state.overlord_of(nation_id)
		return (
			"内战藩王→国%d" % overlord_id
			if game_state.is_in_civil_war(nation_id)
			else "藩王→国%d" % overlord_id
		)
	var subjects := game_state.subjects_of(nation_id)
	if not subjects.is_empty():
		return "宗主·%d藩" % subjects.size()
	return "独立"


static func nation_action_summary(
	game_state: GameState,
	nation_id: int
) -> String:
	if nation_id < 0 or nation_id >= game_state.nations.size():
		return ""
	var nation := game_state.nations[nation_id]
	var actions: Array[String] = []
	if nation.war_preparation_target_nation >= 0:
		actions.append(
			"备战→国%d/城%d" % [
				nation.war_preparation_target_nation,
				nation.war_preparation_objective_city,
			]
		)
	elif not nation.campaign_attack_assignments.is_empty():
		var targets := {}
		for target_value in nation.campaign_attack_assignments.values():
			targets[int(target_value)] = true
		actions.append(
			"攻势W%d·%d路" % [
				nation.campaign_plan_wave,
				targets.size(),
			]
		)
	if nation.ai_last_force_day >= 0:
		actions.append(
			"军D%d:%s" % [
				nation.ai_last_force_day,
				_force_action_name(nation.ai_last_force_action),
			]
		)
	if nation.ai_last_diplomatic_day >= 0:
		actions.append(
			"外D%d:%s→国%d" % [
				nation.ai_last_diplomatic_day,
				_diplomatic_action_name(
					nation.ai_last_diplomatic_action
				),
				nation.ai_last_diplomatic_target,
			]
		)
	if actions.is_empty() and nation.last_offensive_gold_day >= 0:
		actions.append(
			"攻势D%d·费%d" % [
				nation.last_offensive_gold_day,
				nation.last_offensive_gold_cost,
			]
		)
	return "；".join(actions) if not actions.is_empty() else "无近期动作"


static func _force_action_name(action: int) -> String:
	match action:
		ActionCandidate.Kind.CREATE_ARMY:
			return "建军"
		ActionCandidate.Kind.DISBAND_ARMY:
			return "裁军"
		ActionCandidate.Kind.SPLIT_ARMY:
			return "拆军"
		ActionCandidate.Kind.REINFORCE:
			return "补员"
	return "整军"


func _nation_list_rows_cached() -> Array[Dictionary]:
	if (
		_nation_list_cache_day != state.day
		or _nation_list_cache_ownership_revision
			!= state.ownership_revision
		or _nation_list_cache_diplomacy_revision
			!= state.diplomacy_revision
	):
		_nation_list_cache_day = state.day
		_nation_list_cache_ownership_revision = state.ownership_revision
		_nation_list_cache_diplomacy_revision = state.diplomacy_revision
		_nation_list_cache = nation_list_rows(
			state,
			_nation_stats_collapsed_nations
		)
		_nation_list_alive_count = nation_list_alive_count(state)
	return _nation_list_cache


func _draw_hud() -> void:
	var header_y := 20.0 * _display_scale
	var status := "暂停" if sim.paused else "推演中"
	if state.winner != -1:
		status = (
			"国%d 已统一 · %s"
			% [
				state.winner,
				"暂停" if sim.paused else "继续推演",
			]
		)
	var header_rect := Rect2(
		Vector2(_side_margin - 10.0 * _display_scale, 5.0 * _display_scale),
		Vector2(
			get_viewport_rect().size.x
				- (_side_margin - 10.0 * _display_scale) * 2.0,
			28.0 * _display_scale
		)
	)
	draw_rect(
		Rect2(
			header_rect.position + Vector2(2.0, 3.0) * _display_scale,
			header_rect.size
		),
		Color(0.02, 0.015, 0.008, 0.60),
		true
	)
	draw_rect(header_rect, COMMAND_GREEN, true)
	draw_rect(header_rect, ACCENT_GOLD.darkened(0.25), false, 1.5 * _display_scale)
	var button_rect := nation_stats_button_rect(
		get_viewport_rect().size,
		_display_scale,
		_side_margin
	)
	var army_scale_rect := army_icon_scale_control_rect(
		get_viewport_rect().size,
		_display_scale,
		_side_margin
	)
	draw_rect(
		Rect2(
			button_rect.position + Vector2(1.5, 2.0) * _display_scale,
			button_rect.size
		),
		Color(0.02, 0.015, 0.008, 0.72),
		true
	)
	draw_rect(
		button_rect,
		ACCENT_GOLD.darkened(0.18)
			if _nation_stats_open
			else PAPER_DARK,
		true
	)
	draw_rect(
		button_rect,
		PAPER_LIGHT,
		false,
		1.2 * _display_scale
	)
	draw_string(
		_font,
		button_rect.position + Vector2(8.0, 15.0) * _display_scale,
		"关闭列表" if _nation_stats_open else "国家列表",
		HORIZONTAL_ALIGNMENT_CENTER,
		button_rect.size.x - 16.0 * _display_scale,
		_font_size(10),
		PAPER_LIGHT
	)
	var header := "战略司令部 | 第%d日 / 第%d月 | %s | 速度 x%.2f | 左键查看档案 右键取消" % [
		state.day, state.month, status, sim.speed_multiplier()
	]
	draw_string(
		_font,
		Vector2(_side_margin, header_y),
		header,
		HORIZONTAL_ALIGNMENT_LEFT,
		army_scale_rect.position.x
			- _side_margin
			- 8.0 * _display_scale,
		_font_size(13),
		PAPER_LIGHT
	)
	if _nation_stats_open:
		_draw_nation_stats_window()


func _draw_nation_stats_window() -> void:
	var rows := _nation_list_rows_cached()
	_clamp_nation_stats_scroll()
	var window_rect := _nation_stats_window_rect()
	_nation_stats_window_position = window_rect.position
	var title_rect := nation_stats_title_rect(
		window_rect,
		_display_scale
	)
	var close_rect := nation_stats_close_rect(
		window_rect,
		_display_scale
	)
	var header_rect := Rect2(
		Vector2(window_rect.position.x, title_rect.end.y),
		Vector2(
			window_rect.size.x,
			NATION_WINDOW_HEADER_HEIGHT * _display_scale
		)
	)
	draw_rect(
		Rect2(
			window_rect.position
				+ Vector2(5.0, 6.0) * _display_scale,
			window_rect.size
		),
		Color(0.01, 0.008, 0.004, 0.72),
		true
	)
	draw_rect(
		window_rect,
		Color(0.69, 0.59, 0.43, 0.98),
		true
	)
	draw_rect(
		window_rect,
		INK_COLOR,
		false,
		2.0 * _display_scale
	)
	draw_rect(title_rect, COMMAND_GREEN, true)
	draw_line(
		Vector2(title_rect.position.x, title_rect.end.y),
		title_rect.end,
		ACCENT_GOLD.darkened(0.18),
		1.5 * _display_scale
	)
	draw_string(
		_font,
		title_rect.position + Vector2(12.0, 20.0) * _display_scale,
		"国家列表  显示 %d / 存活 %d  · 拖动标题栏移动"
			% [rows.size(), _nation_list_alive_count],
		HORIZONTAL_ALIGNMENT_LEFT,
		title_rect.size.x - 48.0 * _display_scale,
		_font_size(12),
		PAPER_LIGHT
	)
	draw_rect(close_rect, PAPER_DARK, true)
	draw_rect(
		close_rect,
		PAPER_LIGHT,
		false,
		1.0 * _display_scale
	)
	draw_string(
		_font,
		close_rect.position + Vector2(4.0, 16.0) * _display_scale,
		"×",
		HORIZONTAL_ALIGNMENT_CENTER,
		close_rect.size.x - 8.0 * _display_scale,
		_font_size(14),
		PAPER_LIGHT
	)
	draw_rect(header_rect, Color(0.28, 0.22, 0.14, 0.96), true)
	_draw_nation_window_cells(
		header_rect,
		{
			"identity": "国家 / 身份",
			"military": "领土 / 军事",
			"economy": "财政 / 粮食",
			"diplomacy": "外交",
			"action": "相关动作",
		},
		PAPER_LIGHT,
		_font_size(10)
	)
	var capacity := nation_stats_visible_row_capacity(
		window_rect.size,
		_display_scale
	)
	var visible_end := mini(
		_nation_stats_scroll + capacity,
		rows.size()
	)
	for row_index in range(_nation_stats_scroll, visible_end):
		var row_data := rows[row_index]
		var visual_index := row_index - _nation_stats_scroll
		var row_rect := nation_stats_row_rect(
			window_rect,
			_display_scale,
			visual_index
		)
		var row_color := (
			Color(0.73, 0.64, 0.49, 0.98)
			if visual_index % 2 == 0
			else Color(0.66, 0.57, 0.43, 0.98)
		)
		if bool(row_data["at_war"]):
			row_color = row_color.lerp(
				Color(0.58, 0.36, 0.28, 0.98),
				0.34
			)
		draw_rect(row_rect, row_color, true)
		draw_rect(
			Rect2(
				row_rect.position,
				Vector2(5.0 * _display_scale, row_rect.size.y)
			),
			paper_nation_color(row_data["color"]),
			true
		)
		draw_line(
			Vector2(row_rect.position.x, row_rect.end.y),
			row_rect.end,
			Color(0.18, 0.12, 0.06, 0.24),
			1.0
		)
		_draw_nation_window_cells(
			row_rect,
			row_data,
			INK_COLOR,
			_font_size(10)
		)
	var footer_rect := Rect2(
		Vector2(
			window_rect.position.x,
			window_rect.end.y
				- NATION_WINDOW_FOOTER_HEIGHT * _display_scale
		),
		Vector2(
			window_rect.size.x,
			NATION_WINDOW_FOOTER_HEIGHT * _display_scale
		)
	)
	draw_rect(footer_rect, Color(0.25, 0.20, 0.13, 0.96), true)
	var footer := (
		"箭头展开/收起 · 滚轮浏览  %d-%d / %d"
		% [
			mini(_nation_stats_scroll + 1, rows.size()),
			visible_end,
			rows.size(),
		]
		if not rows.is_empty()
		else "当前无存活国家"
	)
	draw_string(
		_font,
		footer_rect.position + Vector2(10.0, 15.0) * _display_scale,
		footer,
		HORIZONTAL_ALIGNMENT_LEFT,
		footer_rect.size.x - 20.0 * _display_scale,
		_font_size(9),
		PAPER_LIGHT
	)


func _draw_nation_window_cells(
	row_rect: Rect2,
	row_data: Dictionary,
	color: Color,
	font_size: int
) -> void:
	var columns := [
		["identity", 0.02, 0.13],
		["military", 0.15, 0.21],
		["economy", 0.36, 0.20],
		["diplomacy", 0.56, 0.19],
		["action", 0.75, 0.23],
	]
	for column in columns:
		var key := str(column[0])
		var x_ratio := float(column[1])
		var width_ratio := float(column[2])
		var text_x := (
			row_rect.position.x
			+ row_rect.size.x * x_ratio
		)
		var text_width := row_rect.size.x * width_ratio
		if key == "identity" and row_data.has("depth"):
			var depth := int(row_data.get("depth", 0))
			var toggle_rect := nation_tree_toggle_rect(
				row_rect,
				_display_scale,
				depth
			)
			if depth > 0:
				draw_line(
					Vector2(
						toggle_rect.position.x
							- NATION_TREE_INDENT
								* _display_scale * 0.55,
						toggle_rect.get_center().y
					),
					Vector2(
						toggle_rect.position.x
							- 2.0 * _display_scale,
						toggle_rect.get_center().y
					),
					Color(0.18, 0.12, 0.06, 0.38),
					1.0 * _display_scale
				)
			if bool(row_data.get("has_subjects", false)):
				draw_string(
					_font,
					toggle_rect.position
						+ Vector2(0.0, 11.0)
							* _display_scale,
					(
						"▼"
						if bool(row_data.get("expanded", false))
						else "▶"
					),
					HORIZONTAL_ALIGNMENT_CENTER,
					toggle_rect.size.x,
					_font_size(9),
					color
				)
			text_x = toggle_rect.end.x + 2.0 * _display_scale
			text_width = maxf(
				row_rect.position.x
					+ row_rect.size.x
						* (x_ratio + width_ratio)
					- text_x,
				1.0
			)
		draw_string(
			_font,
			Vector2(
				text_x,
				row_rect.position.y
					+ row_rect.size.y * 0.68
			),
			str(row_data.get(key, "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			text_width,
			font_size,
			color
		)


func _draw_selection_detail() -> void:
	var lines: Array[String] = []
	var title := ""
	var stripe_color := COMMAND_GREEN
	if _selected_city_id >= 0 and _selected_city_id < state.cities.size():
		var city := state.cities[_selected_city_id]
		title = "城市作战档案  %s%d" % [
			"港" if city.is_dock else "城",
			city.id,
		]
		stripe_color = paper_nation_color(
			state.nations[city.owner_nation].color
		).darkened(0.22)
		lines = city_detail_lines(state, city.id)
	elif _selected_edge_a >= 0 and _selected_edge_b >= 0:
		var edge := state.edge_of(_selected_edge_a, _selected_edge_b)
		if edge != null:
			title = "道路作战档案  %d ↔ %d" % [
				edge.city_a,
				edge.city_b,
			]
			lines = edge_detail_lines(state, edge)
	if lines.is_empty():
		return
	var viewport_size := get_viewport_rect().size
	var margin := DETAIL_PANEL_MARGIN * _display_scale
	var width := minf(
		DETAIL_PANEL_WIDTH * _display_scale,
		viewport_size.x - margin * 2.0
	)
	var line_height := 17.0 * _display_scale
	var height := (
		43.0 * _display_scale
		+ line_height * float(lines.size())
	)
	var rect := Rect2(
		Vector2(
			viewport_size.x - width - margin,
			viewport_size.y - height - margin
		),
		Vector2(width, height)
	)
	draw_rect(
		Rect2(
			rect.position + Vector2(4.0, 5.0) * _display_scale,
			rect.size
		),
		Color(0.02, 0.015, 0.008, 0.68),
		true
	)
	draw_rect(rect, PAPER_LIGHT, true)
	draw_rect(rect, INK_COLOR, false, 2.0 * _display_scale)
	var title_rect := Rect2(
		rect.position,
		Vector2(rect.size.x, 28.0 * _display_scale)
	)
	draw_rect(title_rect, stripe_color, true)
	draw_line(
		Vector2(rect.position.x, title_rect.end.y),
		Vector2(rect.end.x, title_rect.end.y),
		ACCENT_GOLD,
		2.0 * _display_scale
	)
	draw_string(
		_font,
		rect.position + Vector2(12.0, 19.0) * _display_scale,
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 24.0 * _display_scale,
		_font_size(12),
		PAPER_LIGHT
	)
	for index in range(lines.size()):
		draw_string(
			_font,
			rect.position + Vector2(
				12.0,
				43.0 + float(index) * 17.0
			) * _display_scale,
			lines[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 24.0 * _display_scale,
			_font_size(10),
			INK_COLOR
		)


static func city_detail_lines(
	game_state: GameState,
	city_id: int
) -> Array[String]:
	if city_id < 0 or city_id >= game_state.cities.size():
		return []
	var city := game_state.cities[city_id]
	var legal_owner := game_state.recognized_owner_of(city_id)
	var garrison_count := 0
	var garrison_troops := 0
	for army in game_state.armies:
		if army.size > 0 and army.location_city == city_id:
			garrison_count += 1
			garrison_troops += army.size
	var contested := contested_city_ids(game_state).has(city_id)
	var recovery_days := 0
	if city.fort_last_capture_day >= 0:
		recovery_days = maxi(
			Simulation.CITY_WAR_DISRUPTION_DAYS
				- (game_state.day - city.fort_last_capture_day),
			0
		)
	var type_name := "河运码头" if city.is_dock else "陆地城市"
	var special: Array[String] = []
	if city.is_capital:
		special.append("首都")
	if city.has_warehouse:
		special.append("粮仓")
	if city.is_food_hub:
		special.append("粮食核心")
	if city.is_manpower_hub:
		special.append("人口核心")
	if city.is_plain_city:
		special.append("平原")
	if city.is_port_market:
		special.append("港市")
	if city.is_crossroads:
		special.append("枢纽")
	return [
		"类型 %s   状态 %s" % [
			type_name,
			"交战中" if contested else "稳定",
		],
		"控制 国%d   法理 国%d   %s" % [
			city.owner_nation,
			legal_owner,
			" / ".join(special) if not special.is_empty() else "普通据点",
		],
		"工事 %d / %d   恢复剩余 %d 日" % [
			city.fort_strength,
			city.fort_strength_max,
			recovery_days,
		],
		"驻军 %d 支 / %d 人" % [
			garrison_count,
			garrison_troops,
		],
		"产出 人力 %+d/月  金钱 %+d/月  粮食 %+d/半年" % [
			city.manpower_per_month,
			city.gold_per_month,
			city.food_per_half_year,
		],
		"发展权重 金×%.2f  粮×%.2f  海拔产出×%.2f" % [
			city.development_gold_multiplier,
			city.development_food_multiplier,
			city.terrain_output_multiplier,
		],
		"库存 %d   地形高度 %.2f / 起伏 %.2f" % [
			city.food_storage,
			city.terrain_height,
			city.terrain_relief,
		],
	]


static func edge_detail_lines(
	game_state: GameState,
	edge: Edge
) -> Array[String]:
	if edge == null:
		return []
	var city_a := game_state.cities[edge.city_a]
	var city_b := game_state.cities[edge.city_b]
	return [
		"类型 %s   %s" % [
			_edge_kind_name(edge.kind),
			"允许驻边" if edge.allows_holding else "禁止驻边",
		],
		"端点 城%d(国%d) ↔ 城%d(国%d)" % [
			edge.city_a,
			city_a.owner_nation,
			edge.city_b,
			city_b.owner_nation,
		],
		"距离 %d   行军 %.1f 天" % [
			edge.distance,
			Simulation.edge_travel_days(edge),
		],
		"容量 %d   危险 %.0f%%   高差 %.2f" % [
			edge.max_manpower,
			edge.danger * 100.0,
			edge.max_height_difference,
		],
		"粮损倍率 %.2f   通行军队 %d   %s" % [
			edge.supply_loss_multiplier,
			edge.passing_count,
			"占用中" if edge.occupied else "畅通",
		],
	]


static func _edge_kind_name(kind: int) -> String:
	match kind:
		Edge.Kind.LANDING:
			return "抢滩通道"
		Edge.Kind.RIVER:
			return "河运航道"
	return "陆上道路"


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
	var tribute_balance := (
		int(report["monthly_tribute_income"])
		- int(report["monthly_tribute_expense"])
	)
	var line_one := "城%d 兵%d 人%d  金%d" % [
		game_state.cities_of(nation_id).size(),
		troops,
		n.manpower_pool,
		n.treasury_gold,
	]
	var line_two := "月净%+d  城收%d  贡赋%+d" % [
		gold_balance,
		int(report["monthly_city_gold_income"]),
		tribute_balance,
	]
	var line_three := "军费%d  未付%d  支付%.0f%%" % [
		n.last_military_upkeep,
		n.unpaid_military_upkeep,
		n.military_payment_ratio * 100.0,
	]
	var line_four := "粮%d 需%d/月  战%s  盟%s" % [
		n.granary_food,
		int(ceil(float(report["monthly_food_demand"]))),
		str(game_state.wars_of(nation_id)),
		str(game_state.allies_of(nation_id)),
	]
	var lines := [
		line_one,
		line_two,
		line_three,
		line_four,
	] as Array[String]
	if not n.campaign_attack_assignments.is_empty():
		var target_set := {}
		for target_value in n.campaign_attack_assignments.values():
			target_set[int(target_value)] = true
		var target_ids := target_set.keys()
		target_ids.sort()
		var target_labels: Array[String] = []
		for target_value in target_ids:
			if target_labels.size() >= 4:
				break
			target_labels.append("城%d" % int(target_value))
		var omitted_targets := maxi(
			target_ids.size() - target_labels.size(),
			0
		)
		var target_summary := " ".join(target_labels)
		if omitted_targets > 0:
			target_summary += " +%d" % omitted_targets
		lines.append(
			"计划W%d %d路 费%d  %s" % [
				n.campaign_plan_wave,
				target_ids.size(),
				n.last_offensive_gold_cost,
				target_summary,
			]
		)
	elif n.last_offensive_gold_day >= 0:
		lines.append(
			"上次攻势 Day%d 组织费%d"
				% [
					n.last_offensive_gold_day,
					n.last_offensive_gold_cost,
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
