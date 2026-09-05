class_name MapRenderer
extends Node2D
## 表现层：只读 GameState，用 _draw() 单一渲染源绘制地图/城市/边/军队/HUD。
## 鼠标选择仅保存在表现层，不进入模拟状态或存档。

var state: GameState
var sim: Simulation
## false 时仅保留 HUD、详情与控件；地图世界由 StrategicMap3D 绘制和拾取。
var world_layer_visible: bool = true
var _history_mode: bool = false
var _history_preview_active: bool = false

# 地图画布连续适配窗口；图标、字体和线宽只使用四档离散视觉比例。
const BASE_VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const BASE_SIDE_MARGIN := MapLayout.BASE_SIDE_MARGIN
const BASE_BOTTOM_MARGIN := MapLayout.BASE_BOTTOM_MARGIN
const BASE_HEADER_ONLY_TOP := MapLayout.BASE_HEADER_ONLY_TOP
const NATION_STATS_BUTTON_WIDTH := MapLayout.NATION_STATS_BUTTON_WIDTH
const ARMY_ICON_CONTROL_WIDTH := MapLayout.ARMY_ICON_CONTROL_WIDTH
const CITY_NAME_BUTTON_WIDTH := 82.0
const NATION_NAME_BUTTON_WIDTH := 82.0
const ARMY_ICON_SCALE_MIN: float = 0.10
const ARMY_ICON_SCALE_MAX: float = 1.80
const ARMY_ICON_SCALE_STEP: float = 0.10
const ARMY_ICON_SCALE_DEFAULT: float = 1.00
const MAP_ZOOM_MIN: float = MapViewMath.MAP_ZOOM_MIN
const MAP_ZOOM_MAX: float = MapViewMath.MAP_ZOOM_MAX
const MAP_ZOOM_WHEEL_FACTOR: float = MapViewMath.MAP_ZOOM_WHEEL_FACTOR
const MAP_PAN_GESTURE_SCALE: float = 24.0
const MAP_PAN_DRAG_THRESHOLD: float = 4.0
const VISUAL_SCALE_COMPACT: float = MapViewMath.VISUAL_SCALE_COMPACT
const VISUAL_SCALE_STANDARD: float = MapViewMath.VISUAL_SCALE_STANDARD
const VISUAL_SCALE_LARGE: float = MapViewMath.VISUAL_SCALE_LARGE
const VISUAL_SCALE_XL: float = MapViewMath.VISUAL_SCALE_XL
const CITY_PICK_RADIUS: float = 14.0
const EDGE_PICK_TOLERANCE: float = 10.0
const MINOR_ROAD_COLOR := Color(0.46, 0.48, 0.50, 0.30)
const MAJOR_ROAD_COLOR := Color(0.38, 0.40, 0.42, 0.42)
const MINOR_ROAD_WIDTH: float = 0.75
const MAJOR_ROAD_WIDTH: float = 1.15
const DETAIL_PANEL_WIDTH: float = 430.0
const DETAIL_PANEL_MARGIN: float = 18.0
const NATION_WINDOW_WIDTH: float = MapLayout.NATION_WINDOW_WIDTH
const NATION_WINDOW_TITLE_HEIGHT: float = MapLayout.NATION_WINDOW_TITLE_HEIGHT
const NATION_WINDOW_HEADER_HEIGHT: float = MapLayout.NATION_WINDOW_HEADER_HEIGHT
const NATION_WINDOW_ROW_HEIGHT: float = MapLayout.NATION_WINDOW_ROW_HEIGHT
const NATION_WINDOW_FOOTER_HEIGHT: float = MapLayout.NATION_WINDOW_FOOTER_HEIGHT
const NATION_WINDOW_MARGIN: float = MapLayout.NATION_WINDOW_MARGIN
const NATION_TREE_INDENT: float = MapLayout.NATION_TREE_INDENT
const NATION_TREE_TOGGLE_SIZE: float = MapLayout.NATION_TREE_TOGGLE_SIZE
const ACTIVE_REDRAW_FPS: float = 30.0
const STATIC_REDRAW_FPS: float = 5.0
const PAPER_COLOR := Color(0.73, 0.61, 0.42)
const PAPER_LIGHT := Color(0.86, 0.76, 0.57)
const PAPER_DARK := Color(0.24, 0.19, 0.12)
const INK_COLOR := Color(0.105, 0.085, 0.055)
const COMMAND_GREEN := Color(0.16, 0.20, 0.14)
const ACCENT_RED := Color(0.55, 0.12, 0.10)
const ACCENT_GOLD := Color(0.88, 0.67, 0.22)
const TRADE_ACTIVE_GOLD := Color(0.96, 0.72, 0.20, 0.96)
const TRADE_ACTIVE_CYAN := Color(0.10, 0.76, 0.72, 0.98)
const TRADE_REROUTED_ORANGE := Color(0.94, 0.39, 0.075, 0.98)
const TRADE_BLOCKED_RED := Color(0.82, 0.075, 0.055, 0.98)
const TRADE_FLOW_SPACING_PX: float = 52.0
const TRADE_FLOW_SPEED_PX: float = 34.0
const LOYALTY_LOW_COLOR := Color(0.72, 0.10, 0.075, 1.0)
const LOYALTY_MID_COLOR := Color(0.92, 0.68, 0.12, 1.0)
const LOYALTY_HIGH_COLOR := Color(0.12, 0.58, 0.24, 1.0)
const DIPLOMACY_ENEMY_COLOR := Color(0.72, 0.08, 0.06, 1.0)
const DIPLOMACY_ALLY_COLOR := Color(0.10, 0.56, 0.20, 1.0)
const DIPLOMACY_VASSAL_COLOR := Color(0.42, 0.42, 0.42, 1.0)
const DIPLOMACY_NEUTRAL_COLOR := Color(0.0, 0.0, 0.0, 1.0)
## 政治边界统一使用纯色实线。省界是纯黑 1px；国界的两条国家色描边分别
## 内缩到各自领土，因此同一国界能同时表达两侧国家。
const LOCAL_BOUNDARY_INK := Color(0.0, 0.0, 0.0, 1.0)
const POLITICAL_MAP_DEFAULT_STRENGTH: float = 0.93
const POLITICAL_LAND_BASE_COLOR := Color(0.82, 0.82, 0.80, 1.0)
const PROVINCE_VISUAL_SUPERSAMPLE: int = 4
const LOCAL_BOUNDARY_WIDTH_PX: float = 1.0
const COUNTRY_BOUNDARY_WIDTH_PX: float = 3.0
const COUNTRY_BOUNDARY_VALUE_OFFSET: float = -0.15
const COUNTRY_BOUNDARY_SATURATION_OFFSET: float = 0.10
## 以省份归属源贴图像素为单位。增大后，国家色向腹地消退得更快。
const COUNTRY_FILL_FADE_COEFFICIENT: float = 0.035
## 国家腹地保留的最低不透明度。设为 0.0 时大国中心可完全露出白模。
const COUNTRY_FILL_MIN_OPACITY: float = 0.0
const BOUNDARY_ANTIALIAS_PX: float = 0.0
const VASSAL_BRIGHTNESS_STEP: float = 0.05
const CAMPAIGN_ARROW_TEXTURE := preload(
	"res://assets/ui/strategic/offensive_arc_arrow.png"
)
const CAMPAIGN_ARROW_SOURCE_TAIL := Vector2(20.0, 616.0)
const CAMPAIGN_ARROW_SOURCE_TIP := Vector2(1490.0, 15.0)

enum FormationIcon {
	INFANTRY,
	ARMOR,
}

enum MapMode {
	POLITICAL,
	LOYALTY,
	TRADE,
}

const MAP_MODE_POLITICAL: int = MapMode.POLITICAL
const MAP_MODE_LOYALTY: int = MapMode.LOYALTY
const MAP_MODE_TRADE: int = MapMode.TRADE

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
var _province_texture: ImageTexture
var _political_base_texture: ImageTexture
var _political_ocean_texture: ImageTexture
var _political_texture: ImageTexture
var _loyalty_texture: ImageTexture
var _country_fill_opacity_image: Image
var _country_fill_opacity_ownership_revision: int = -1
var _political_fill_signature := PackedInt64Array()
var _loyalty_fill_signature := PackedInt64Array()
var _map_mode: int = MapMode.POLITICAL
var _province_visual_mode: int = -1
var _province_loyalty_day: int = -1
var _province_strength: float = POLITICAL_MAP_DEFAULT_STRENGTH
var _classified_boundary_geometry := {}
var _boundary_topology := {}
var _province_topology_ids := PackedInt32Array()
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
var _selected_nation_id: int = -1
## 与详情选择解耦的外交观察方。点城市仍显示城市详情，同时以其所属国
## 重绘整张地图；点道路不会丢失视角，右键/空白海面才清除。
var _diplomatic_view_nation_id: int = -1
var _province_visual_view_nation_id: int = -2
var _nation_stats_open: bool = false
var _nation_stats_window_position := Vector2(-1.0, -1.0)
var _nation_stats_drag_active: bool = false
var _nation_stats_drag_offset := Vector2.ZERO
var _nation_stats_scroll: int = 0
var _nation_stats_collapsed_nations: Dictionary = {}
var _city_names_visible: bool = true
var _nation_names_visible: bool = true
var _army_icon_scale: float = ARMY_ICON_SCALE_DEFAULT
var _nation_list_cache_day: int = -1
var _nation_list_cache_ownership_revision: int = -1
var _nation_list_cache_diplomacy_revision: int = -1
var _nation_list_cache_naming_revision: int = -1
var _nation_list_cache_trade_revision: int = -1
var _nation_list_cache: Array[Dictionary] = []
var _nation_list_alive_count: int = 0
var _city_label_cache: Dictionary = {}
var _city_label_cache_naming_revision: int = -1
var _contested_city_cache_day: int = -1
var _contested_city_cache: Dictionary = {}
var _visual_animation_active: bool = false
var _army_icon_panel: PanelContainer
var _army_icon_label: Label
var _army_icon_slider: HSlider
var _city_name_button: Button
var _nation_name_button: Button
static var _nation_detail_section_build_count: int = 0

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
	_history_mode = false
	_history_preview_active = false
	if _army_icon_panel != null:
		_army_icon_panel.visible = true
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
	_political_base_texture = null
	_political_ocean_texture = null
	_political_texture = null
	_loyalty_texture = null
	_country_fill_opacity_image = null
	_country_fill_opacity_ownership_revision = -1
	_political_fill_signature = PackedInt64Array()
	_loyalty_fill_signature = PackedInt64Array()
	_province_visual_mode = -1
	_province_loyalty_day = -1
	_classified_boundary_geometry = {}
	_boundary_topology = {}
	_province_topology_ids = PackedInt32Array()
	_province_cache_ready = false
	_province_ownership_revision = -1
	_province_diplomacy_revision = -1
	_selected_city_id = -1
	_selected_edge_a = -1
	_selected_edge_b = -1
	_selected_nation_id = -1
	_diplomatic_view_nation_id = -1
	_province_visual_view_nation_id = -2
	_map_zoom = MAP_ZOOM_MIN
	_map_pan = Vector2.ZERO
	_map_drag_active = false
	_map_drag_moved = false
	_nation_list_cache_day = -1
	_nation_list_cache_ownership_revision = -1
	_nation_list_cache_diplomacy_revision = -1
	_nation_list_cache_naming_revision = -1
	_nation_list_cache_trade_revision = -1
	_nation_list_cache.clear()
	_nation_list_alive_count = 0
	_nation_stats_drag_active = false
	_nation_stats_scroll = 0
	_nation_stats_collapsed_nations.clear()
	_city_label_cache.clear()
	_city_label_cache_naming_revision = -1
	_contested_city_cache_day = -1
	_contested_city_cache.clear()
	_visual_animation_active = false
	_layout_viewport_size = Vector2.ZERO
	_layout_nation_count = -1
	_layout_map_aspect_ratio = -1.0


func _ready() -> void:
	_font = create_ui_font()
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

	_nation_name_button = Button.new()
	_nation_name_button.name = "NationNameToggle"
	_nation_name_button.toggle_mode = true
	_nation_name_button.button_pressed = _nation_names_visible
	_nation_name_button.custom_minimum_size = Vector2(
		NATION_NAME_BUTTON_WIDTH,
		0.0
	)
	_nation_name_button.add_theme_font_override("font", _font)
	_nation_name_button.add_theme_font_size_override("font_size", 10)
	_nation_name_button.add_theme_color_override(
		"font_color",
		PAPER_LIGHT
	)
	_nation_name_button.add_theme_color_override(
		"font_hover_color",
		Color.WHITE
	)
	_nation_name_button.add_theme_color_override(
		"font_pressed_color",
		PAPER_LIGHT
	)
	_nation_name_button.add_theme_stylebox_override(
		"normal",
		city_button_normal.duplicate()
	)
	_nation_name_button.add_theme_stylebox_override(
		"hover",
		city_button_hover.duplicate()
	)
	_nation_name_button.add_theme_stylebox_override(
		"pressed",
		city_button_pressed.duplicate()
	)
	_nation_name_button.tooltip_text = "开启或关闭地图国家名称"
	_nation_name_button.toggled.connect(
		_on_nation_names_toggled
	)
	row.add_child(_nation_name_button)

	set_army_icon_scale(_army_icon_scale)
	set_city_names_visible(_city_names_visible)
	set_nation_names_visible(_nation_names_visible)


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


func _on_nation_names_toggled(visible: bool) -> void:
	set_nation_names_visible(visible)


func set_nation_names_visible(visible: bool) -> void:
	_nation_names_visible = visible
	if _nation_name_button != null:
		_nation_name_button.set_pressed_no_signal(visible)
		_nation_name_button.text = (
			"国名 开" if visible else "国名 关"
		)
	queue_redraw()


func nation_names_visible() -> bool:
	return _nation_names_visible


func set_map_mode(mode: int) -> void:
	var normalized := clampi(mode, MapMode.POLITICAL, MapMode.TRADE)
	if normalized == _map_mode:
		return
	_map_mode = normalized
	_province_visual_mode = -1
	queue_redraw()


func map_mode() -> int:
	return _map_mode


func set_world_layer_visible(visible: bool) -> void:
	world_layer_visible = visible
	_map_drag_active = false
	_map_drag_moved = false
	queue_redraw()


func set_display_state(
	game_state: GameState,
	historical: bool,
	map_mode_override: int = -1,
	fast_preview: bool = false
) -> void:
	state = game_state
	_history_mode = historical
	_history_preview_active = fast_preview
	if map_mode_override >= 0:
		_map_mode = clampi(
			map_mode_override, MapMode.POLITICAL, MapMode.TRADE
		)
	_selected_city_id = -1
	_selected_edge_a = -1
	_selected_edge_b = -1
	_selected_nation_id = -1
	_diplomatic_view_nation_id = -1
	_province_texture = null
	_political_texture = null
	_loyalty_texture = null
	_country_fill_opacity_image = null
	_political_fill_signature = PackedInt64Array()
	_loyalty_fill_signature = PackedInt64Array()
	_province_visual_mode = -1
	_province_ownership_revision = -1
	_province_diplomacy_revision = -1
	_province_visual_view_nation_id = -2
	_nation_list_cache_day = -1
	_nation_list_cache_ownership_revision = -1
	_nation_list_cache_diplomacy_revision = -1
	_nation_list_cache.clear()
	_contested_city_cache_day = -1
	_contested_city_cache.clear()
	_last_day = -1
	if fast_preview and world_layer_visible:
		var preview_image := build_province_overlay_image(
			state, _diplomatic_view_nation_id
		)
		preview_image.resize(
			preview_image.get_width() * PROVINCE_VISUAL_SUPERSAMPLE,
			preview_image.get_height() * PROVINCE_VISUAL_SUPERSAMPLE,
			Image.INTERPOLATE_NEAREST
		)
		_province_texture = ImageTexture.create_from_image(preview_image)
		_political_texture = _province_texture
		_political_fill_signature = political_fill_signature(
			state, _diplomatic_view_nation_id
		)
		_province_ownership_revision = state.ownership_revision
		_province_diplomacy_revision = state.diplomacy_revision
		_province_visual_mode = _map_mode
		_province_visual_view_nation_id = _diplomatic_view_nation_id
		_province_loyalty_day = state.day
	if _army_icon_panel != null:
		_army_icon_panel.visible = not historical
	queue_redraw()


func history_mode() -> bool:
	return _history_mode


func refresh_road_network() -> void:
	_clear_selection()
	queue_redraw()


func select_city(city_id: int) -> void:
	if (
		_history_mode
		and state != null
		and city_id >= 0
		and city_id < state.cities.size()
	):
		select_nation(state.cities[city_id].owner_nation)
		return
	_selected_city_id = city_id
	_selected_edge_a = -1
	_selected_edge_b = -1
	_selected_nation_id = -1
	var next_view := -1
	if state != null and city_id >= 0 and city_id < state.cities.size():
		next_view = state.cities[city_id].owner_nation
	_set_diplomatic_view_nation(next_view)
	queue_redraw()


func select_edge(city_a: int, city_b: int) -> void:
	_selected_city_id = -1
	_selected_edge_a = mini(city_a, city_b)
	_selected_edge_b = maxi(city_a, city_b)
	_selected_nation_id = -1
	queue_redraw()


func select_nation(nation_id: int) -> void:
	_selected_city_id = -1
	_selected_edge_a = -1
	_selected_edge_b = -1
	_selected_nation_id = (
		nation_id
		if state != null and nation_id >= 0 and nation_id < state.nations.size()
		else -1
	)
	_set_diplomatic_view_nation(_selected_nation_id)
	queue_redraw()


func clear_map_selection() -> void:
	_clear_selection()


func selected_city_id() -> int:
	return _selected_city_id


func selected_edge_pair() -> Vector2i:
	return Vector2i(_selected_edge_a, _selected_edge_b)


func selected_nation_id() -> int:
	return _selected_nation_id


func diplomatic_view_nation_id() -> int:
	return _diplomatic_view_nation_id


func _set_diplomatic_view_nation(nation_id: int) -> void:
	var normalized := (
		nation_id
		if (
			state != null
			and nation_id >= 0
			and nation_id < state.nations.size()
			and state.nations[nation_id].alive
		)
		else -1
	)
	if normalized == _diplomatic_view_nation_id:
		return
	_diplomatic_view_nation_id = normalized
	_province_visual_view_nation_id = -2
	_political_fill_signature = PackedInt64Array()


func world_input_blocked(point: Vector2) -> bool:
	_compute_layout()
	if point.y <= 38.0 * _display_scale:
		return true
	if (
		_nation_stats_open
		and _nation_stats_window_rect().has_point(point)
	):
		return true
	var detail_line_count := _selection_detail_line_count()
	if (
		detail_line_count > 0
		and _selection_detail_rect(
			detail_line_count
		).has_point(point)
	):
		return true
	return false


func army_map_position(army: Army) -> Vector2:
	return army_snapshot_position(army.id, _logical_grid_pos(army))


## 返回最近两次已提交日快照之间的显示位置；调用者无需读取正在推进的军队状态。
func army_snapshot_position(army_id: int, fallback: Vector2) -> Vector2:
	var curr: Vector2 = _curr_pos.get(
		army_id,
		fallback
	)
	var prev: Vector2 = _prev_pos.get(army_id, curr)
	var t := clampf(
		_tick_elapsed / maxf(_tick_duration, 0.0001),
		0.0,
		1.0
	)
	return prev.lerp(curr, smoothstep(0.0, 1.0, t))


static func create_ui_font() -> Font:
	var candidates := PackedStringArray([
		"/System/Library/Fonts/Hiragino Sans GB.ttc",
		"/System/Library/Fonts/STHeiti Medium.ttc",
		"C:/Windows/Fonts/msyh.ttc",
		"C:/Windows/Fonts/simhei.ttf",
		"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
		"/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
		"/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf",
		"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
		"/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
		"/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
	])
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var font_file := FontFile.new()
		if font_file.load_dynamic_font(path) == OK:
			return font_file
	var portable := SystemFont.new()
	portable.font_names = PackedStringArray([
		"sans-serif", "Noto Sans CJK SC", "Source Han Sans SC",
		"Microsoft YaHei", "SimHei", "PingFang SC", "Heiti SC",
	])
	portable.allow_system_fallback = true
	return portable


static func create_map_label_font() -> Font:
	# 地图标签统一复用 UI 的 CJK Sans/黑体字体：黑体在任意缩放下笔画更清晰、
	# 与国名大字风格一致，不再声明仿宋/衬线候选。
	return create_ui_font()


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
	var trade_flow_active := (
		state != null
		and _map_mode == MapMode.TRADE
		and has_animated_trade_routes(state.trade_routes)
	)
	var target_fps := target_redraw_fps(
		sim == null or sim.paused,
		_visual_animation_active or trade_flow_active
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
	if event is InputEventMagnifyGesture:
		_handle_magnify_gesture(event as InputEventMagnifyGesture)
		return
	if event is InputEventPanGesture:
		_handle_pan_gesture(event as InputEventPanGesture)
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
		return
	if not event is InputEventMouseButton:
		return
	_handle_mouse_button(event as InputEventMouseButton)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	_compute_layout()
	var stats_rect := _nation_stats_window_rect()
	if _handle_nation_stats_wheel(event, stats_rect):
		return
	if _handle_map_wheel(event):
		return
	if _handle_right_mouse_button(event, stats_rect):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	_handle_left_mouse_button(event, stats_rect)


func _handle_nation_stats_wheel(
	event: InputEventMouseButton,
	stats_rect: Rect2
) -> bool:
	if (
		_nation_stats_open
		and stats_rect.has_point(event.position)
		and event.pressed
		and event.button_index in [
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
					if event.button_index
						== MOUSE_BUTTON_WHEEL_UP
					else 1
				),
			0,
			maximum_scroll
		)
		queue_redraw()
		get_viewport().set_input_as_handled()
		return true
	return false


func _handle_map_wheel(event: InputEventMouseButton) -> bool:
	if (
		event.pressed
		and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN,
		]
		and world_layer_visible
		and Rect2(_origin, _map_size).has_point(event.position)
	):
		var factor := wheel_zoom_multiplier(
			event.button_index,
			event.factor
		)
		_set_map_zoom_at(_map_zoom * factor, event.position)
		get_viewport().set_input_as_handled()
		return true
	return false


func _handle_right_mouse_button(
	event: InputEventMouseButton,
	stats_rect: Rect2
) -> bool:
	if (
		event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		if _nation_stats_open and stats_rect.has_point(event.position):
			get_viewport().set_input_as_handled()
			return true
		if not world_layer_visible:
			return true
		_clear_selection()
		get_viewport().set_input_as_handled()
		return true
	return false


func _handle_left_mouse_button(
	event: InputEventMouseButton,
	stats_rect: Rect2
) -> void:
	var point := event.position
	if event.pressed:
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
				var toggled := _toggle_nation_tree_at_point(
					point,
					stats_rect
				)
				if not toggled:
					_select_nation_row_at_point(point, stats_rect)
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if not world_layer_visible:
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
	if _nation_stats_drag_active:
		_nation_stats_drag_active = false
		get_viewport().set_input_as_handled()
		return
	if not world_layer_visible:
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


func _handle_magnify_gesture(event: InputEventMagnifyGesture) -> void:
	if not world_layer_visible:
		return
	_compute_layout()
	if (
		not _point_blocked_by_nation_stats(event.position)
		and Rect2(_origin, _map_size).has_point(event.position)
	):
		_set_map_zoom_at(
			_map_zoom * magnify_zoom_multiplier(event.factor),
			event.position
		)
		get_viewport().set_input_as_handled()


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	if not world_layer_visible:
		return
	_compute_layout()
	if (
		not _point_blocked_by_nation_stats(event.position)
		and Rect2(_origin, _map_size).has_point(event.position)
	):
		_map_pan -= (
			event.delta * MAP_PAN_GESTURE_SCALE * _display_scale
		)
		_apply_map_view_transform()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _nation_stats_drag_active:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_nation_stats_drag_active = false
			return
		_nation_stats_window_position = (
			event.position - _nation_stats_drag_offset
		)
		_clamp_nation_stats_window_position()
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if not world_layer_visible:
		return
	if (
		not _map_drag_active
		or (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0
	):
		return
	if (
		not _map_drag_moved
		and event.position.distance_to(_map_drag_start)
			>= MAP_PAN_DRAG_THRESHOLD * _display_scale
	):
		_map_drag_moved = true
	if _map_drag_moved:
		_map_pan = _map_drag_start_pan + (event.position - _map_drag_start)
		_apply_map_view_transform()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _point_blocked_by_nation_stats(point: Vector2) -> bool:
	return (
		_nation_stats_open
		and _nation_stats_window_rect().has_point(point)
	)


static func magnify_zoom_multiplier(factor: float) -> float:
	return MapViewMath.magnify_zoom_multiplier(factor)


static func wheel_zoom_multiplier(
	button_index: int,
	factor: float
) -> float:
	return MapViewMath.wheel_zoom_multiplier(button_index, factor)


func _pick_map_feature(point: Vector2) -> void:
	var city_id := pick_city_at_pixel(
		state,
		point,
		_origin,
		_map_size,
		CITY_PICK_RADIUS * _display_scale
	)
	if city_id >= 0:
		select_city(city_id)
		get_viewport().set_input_as_handled()
		return
	var edge := pick_edge_at_pixel(
		state,
		point,
		_origin,
		_map_size,
		EDGE_PICK_TOLERANCE * _display_scale
	)
	if edge != null:
		select_edge(edge.city_a, edge.city_b)
		return
	var nation_id := nation_at_map_position(
		state, (point - _origin) / _map_size
	)
	if nation_id >= 0:
		select_nation(nation_id)
	else:
		_clear_selection()


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
	_selected_nation_id = -1
	_set_diplomatic_view_nation(-1)
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
	return MapViewMath.clamp_map_pan(pan, zoom, base_map_size)


static func map_view_origin(
	base_origin: Vector2,
	base_map_size: Vector2,
	zoom: float,
	pan: Vector2
) -> Vector2:
	return MapViewMath.map_view_origin(
		base_origin,
		base_map_size,
		zoom,
		pan
	)


static func map_pan_for_zoom_anchor(
	base_origin: Vector2,
	base_map_size: Vector2,
	old_zoom: float,
	old_pan: Vector2,
	new_zoom: float,
	anchor: Vector2
) -> Vector2:
	return MapViewMath.map_pan_for_zoom_anchor(
		base_origin,
		base_map_size,
		old_zoom,
		old_pan,
		new_zoom,
		anchor
	)


static func compute_layout_for_viewport(
	viewport_size: Vector2,
	nation_count: int,
	_nation_stats_open: bool = true
) -> Dictionary:
	return MapLayout.compute_for_viewport(viewport_size, nation_count)


static func nation_stats_button_rect(
	viewport_size: Vector2,
	display_scale: float,
	side_margin: float
) -> Rect2:
	return MapLayout.nation_stats_button_rect(
		viewport_size,
		display_scale,
		side_margin
	)


static func nation_stats_window_size(
	viewport_size: Vector2,
	display_scale: float,
	alive_nation_count: int
) -> Vector2:
	return MapLayout.nation_stats_window_size(
		viewport_size,
		display_scale,
		alive_nation_count
	)


static func nation_stats_visible_row_capacity(
	window_size: Vector2,
	display_scale: float
) -> int:
	return MapLayout.nation_stats_visible_row_capacity(
		window_size,
		display_scale
	)


static func nation_stats_window_rect(
	viewport_size: Vector2,
	display_scale: float,
	position: Vector2,
	alive_nation_count: int
) -> Rect2:
	return MapLayout.nation_stats_window_rect(
		viewport_size,
		display_scale,
		position,
		alive_nation_count
	)


static func nation_stats_title_rect(
	window_rect: Rect2,
	display_scale: float
) -> Rect2:
	return MapLayout.nation_stats_title_rect(window_rect, display_scale)


static func nation_stats_close_rect(
	window_rect: Rect2,
	display_scale: float
) -> Rect2:
	return MapLayout.nation_stats_close_rect(window_rect, display_scale)


static func nation_stats_row_rect(
	window_rect: Rect2,
	display_scale: float,
	visual_index: int
) -> Rect2:
	return MapLayout.nation_stats_row_rect(
		window_rect,
		display_scale,
		visual_index
	)


static func nation_tree_toggle_rect(
	row_rect: Rect2,
	display_scale: float,
	depth: int
) -> Rect2:
	return MapLayout.nation_tree_toggle_rect(
		row_rect,
		display_scale,
		depth
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


func _select_nation_row_at_point(
	point: Vector2,
	window_rect: Rect2
) -> bool:
	var rows := _nation_list_rows_cached()
	var capacity := nation_stats_visible_row_capacity(
		window_rect.size, _display_scale
	)
	for visual_index in range(mini(capacity, rows.size() - _nation_stats_scroll)):
		var row_rect := nation_stats_row_rect(
			window_rect, _display_scale, visual_index
		)
		if not row_rect.has_point(point):
			continue
		select_nation(int(rows[_nation_stats_scroll + visual_index]["nation_id"]))
		return true
	return false


static func army_icon_scale_control_rect(
	viewport_size: Vector2,
	display_scale: float,
	side_margin: float
) -> Rect2:
	return MapLayout.army_icon_scale_control_rect(
		viewport_size,
		display_scale,
		side_margin
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
	_nation_name_button.add_theme_font_size_override(
		"font_size",
		_font_size(10)
	)
	_nation_name_button.custom_minimum_size = Vector2(
		NATION_NAME_BUTTON_WIDTH * _display_scale,
		0.0
	)


static func visual_scale_for_viewport(viewport_size: Vector2) -> float:
	return MapViewMath.visual_scale_for_viewport(viewport_size)


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
	return MapHitTesting.pick_city_at_pixel(
		game_state, point, origin, map_size, radius
	)


static func pick_edge_at_pixel(
	game_state: GameState,
	point: Vector2,
	origin: Vector2,
	map_size: Vector2,
	tolerance: float
) -> Edge:
	return MapHitTesting.pick_edge_at_pixel(
		game_state, point, origin, map_size, tolerance
	)


static func point_to_segment_distance(
	point: Vector2,
	from: Vector2,
	to: Vector2
) -> float:
	return MapHitTesting.point_to_segment_distance(point, from, to)


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
	var snapshot_started := (
		Time.get_ticks_usec()
		if sim != null and sim.runtime_stage_profiling_enabled
		else 0
	)
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
	if sim != null and sim.runtime_stage_profiling_enabled:
		sim._record_runtime_span(
			&"render_sync_army_snapshots", snapshot_started
		)
# ================================================================== 绘制

func _draw() -> void:
	if state == null:
		return
	_compute_layout()
	var detail_payload := _selection_detail_payload()
	if world_layer_visible:
		_draw_paper_canvas()
		_draw_terrain_background()
		_ensure_province_visual_cache()
		_draw_province_fills()
		_draw_rivers()
		_draw_edges()
		_draw_trade_routes()
		_draw_selection_highlight()
		# Political divisions form one solid-color line layer above the map,
		# terrain and transport network, while counters remain topmost.
		_draw_province_boundaries()
		if not _history_preview_active:
			_draw_national_boundaries()
		_draw_campaign_arrows()
		_draw_cities()
		_draw_battles()
		_draw_armies()
	_draw_selection_detail(detail_payload)
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
	if not state.uses_heightmap:
		return
	if effective_map_mode_strength(_map_mode, _province_strength) > 0.0:
		return
	draw_rect(
		Rect2(_origin, _map_size),
		POLITICAL_LAND_BASE_COLOR,
		true
	)
	if _political_ocean_texture != null:
		draw_texture_rect(
			_political_ocean_texture,
			Rect2(_origin, _map_size),
			false,
			Color.WHITE
		)


func _draw_rivers() -> void:
	var features: Array = state.river_features
	if features.is_empty():
		features = MapFeatureContract.from_legacy_river_paths(state.river_paths)
	for feature_value in features:
		var feature := feature_value as Dictionary
		var river := MapFeatureContract.build_river_render_path(
			feature, state.province_map_size, 4
		)
		if river.size() < 2:
			continue
		var points := PackedVector2Array()
		for normalized_point in river:
			points.append(_origin + normalized_point * _map_size)
		draw_polyline(
			points,
				Color(0.08, 0.16, 0.19, 0.86),
				5.0 * _display_scale * MapFeatureContract.width_at_progress(
					feature, 0.5
				),
			true
		)
		draw_polyline(
			points,
				Color(0.24, 0.48, 0.55, 0.90),
				2.0 * _display_scale * MapFeatureContract.width_at_progress(
					feature, 0.5
				),
			true
		)


func _ensure_province_visual_cache() -> void:
	if (
		state.province_map_size.x <= 0
		or state.province_map_size.y <= 0
		or state.province_ids.is_empty()
	):
		return
	var ownership_changed := (
		_province_ownership_revision != state.ownership_revision
	)
	var loyalty_signature := (
		loyalty_fill_signature(state)
		if _map_mode == MapMode.LOYALTY
		else PackedInt64Array()
	)
	var loyalty_changed := (
		_map_mode == MapMode.LOYALTY
		and (
			_loyalty_texture == null
			or loyalty_signature != _loyalty_fill_signature
		)
	)
	var visual_revision_changed := (
		_province_texture == null
		or ownership_changed
		or _province_diplomacy_revision != state.diplomacy_revision
		or _province_visual_mode != _map_mode
		or (
			_province_visual_view_nation_id
				!= _diplomatic_view_nation_id
		)
		or loyalty_changed
	)
	if not visual_revision_changed:
		return
	var topology_changed := (
		not _province_cache_ready
		or _boundary_topology.is_empty()
		or _province_topology_ids != state.province_ids
	)
	if topology_changed:
		_boundary_topology = build_province_boundary_topology(state)
		_province_topology_ids = state.province_ids.duplicate()
		_province_cache_ready = true
	var geometry := classify_province_boundary_topology(
		state, _boundary_topology
	)
	_classified_boundary_geometry = geometry
	# Most diplomacy revisions only recolor diplomatic edges. A compact semantic
	# signature still catches suzerainty/civil-war color changes without first
	# rebuilding the full categorical image.
	var fill_signature := political_fill_signature(
		state, _diplomatic_view_nation_id
	)
	var fill_changed := (
		topology_changed
		or _province_texture == null
		or fill_signature != _political_fill_signature
	)
	if fill_changed:
		if (
			topology_changed
			or _country_fill_opacity_image == null
			or _country_fill_opacity_ownership_revision
				!= state.ownership_revision
		):
			_country_fill_opacity_image = build_country_fill_opacity_image(state)
			_country_fill_opacity_ownership_revision = state.ownership_revision
		var fill_source := build_province_overlay_image(
			state, _diplomatic_view_nation_id
		)
		var canvas := build_political_canvas_images(
			state, geometry, false, fill_source, true,
			_country_fill_opacity_image
		)
		var political_image: Image = canvas["fill"]
		_province_texture = ImageTexture.create_from_image(
			political_image
		)
		# Sea bathymetry and the neutral primer depend only on province topology
		# and terrain, not on who owns a city. Cache this million-pixel pass across
		# ordinary captures; only a topology edit can move the land/sea mask.
		if topology_changed or _political_base_texture == null:
			_rebuild_political_base_texture(political_image)
		_political_texture = ImageTexture.create_from_image(
			political_image
		)
		_political_fill_signature = fill_signature
	if loyalty_changed or (
		_map_mode == MapMode.LOYALTY and topology_changed
	):
		var loyalty_source := build_loyalty_overlay_image(state)
		loyalty_source.resize(
			loyalty_source.get_width() * PROVINCE_VISUAL_SUPERSAMPLE,
			loyalty_source.get_height() * PROVINCE_VISUAL_SUPERSAMPLE,
			Image.INTERPOLATE_NEAREST
		)
		_loyalty_texture = ImageTexture.create_from_image(loyalty_source)
		_loyalty_fill_signature = loyalty_signature
	_province_ownership_revision = state.ownership_revision
	_province_diplomacy_revision = state.diplomacy_revision
	_province_visual_mode = _map_mode
	_province_visual_view_nation_id = _diplomatic_view_nation_id
	_province_loyalty_day = state.day


func _rebuild_political_base_texture(political_image: Image) -> void:
	var packed_height := (
		load(GameState.terrain_map_path()) as Texture2D
	).get_image()
	var images := build_political_base_images(
		political_image.get_size(), packed_height
	)
	_political_base_texture = ImageTexture.create_from_image(images["land"])
	_political_ocean_texture = ImageTexture.create_from_image(images["ocean"])


static func build_political_base_images(
	output_size: Vector2i, packed_height: Image
) -> Dictionary:
	var political_base_image := Image.create(
		output_size.x, output_size.y,
		false, Image.FORMAT_RGBA8
	)
	political_base_image.fill(POLITICAL_LAND_BASE_COLOR)
	var ocean_image := Image.create(
		output_size.x, output_size.y,
		false, Image.FORMAT_RGBA8
	)
	ocean_image.fill(Color.TRANSPARENT)
	for political_y in range(output_size.y):
		for political_x in range(output_size.x):
			var source_x := clampi(int(
				(float(political_x) + 0.5)
				/ float(output_size.x)
				* float(packed_height.get_width())
			), 0, packed_height.get_width() - 1)
			var source_y := clampi(int(
				(float(political_y) + 0.5)
				/ float(output_size.y)
				* float(packed_height.get_height())
			), 0, packed_height.get_height() - 1)
			var signed_elevation := (
				TerrainMapGenerator.packed_signed_elevation(
					packed_height.get_pixel(source_x, source_y)
				)
			)
			if signed_elevation < 0.0:
				var sea_depth := maxf(-signed_elevation, 0.0)
				var deep_mix := smoothstep(0.06, 0.375, sea_depth)
				ocean_image.set_pixel(
					political_x, political_y,
					Color(0.090, 0.310, 0.470).lerp(
						Color(0.025, 0.060, 0.130), deep_mix
					)
				)
	return {"land": political_base_image, "ocean": ocean_image}


static func build_province_overlay_image(
	game_state: GameState,
	view_nation_id: int = -1
) -> Image:
	var size := game_state.province_map_size
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var province_colors := PackedColorArray()
	var occupation_colors := PackedColorArray()
	var occupied := PackedByteArray()
	province_colors.resize(game_state.cities.size())
	occupation_colors.resize(game_state.cities.size())
	occupied.resize(game_state.cities.size())
	# Political color depends on the province owner, not on the individual
	# raster cell. Compute vassal/civil-war color transforms once per city
	# instead of tens of thousands of times during every capture refresh.
	for city_id in range(game_state.cities.size()):
		var current_owner := game_state.cities[city_id].owner_nation
		if not game_state.cities[city_id].politically_active:
			province_colors[city_id] = Color.TRANSPARENT
			occupation_colors[city_id] = Color.TRANSPARENT
			continue
		var recognized_owner := game_state.recognized_owner_of(city_id)
		if recognized_owner < 0:
			recognized_owner = current_owner
		# 外交视角回答“谁实际控制这片疆域、与观察国是什么关系”，
		# 因而不以法理底色加占领斜线稀释红/绿/灰/黑分类。
		var display_owner := (
			current_owner if view_nation_id >= 0 else recognized_owner
		)
		var base := political_map_color_for_view(
			game_state, display_owner, view_nation_id
		)
		base.a = 1.0
		province_colors[city_id] = base
		if view_nation_id < 0 and current_owner != recognized_owner:
			var occupation := political_map_color_for_view(
				game_state, current_owner, view_nation_id
			).darkened(0.08)
			occupation.a = 1.0
			occupation_colors[city_id] = occupation
			occupied[city_id] = 1
	for y in range(size.y):
		for x in range(size.x):
			var province_id := game_state.province_ids[y * size.x + x]
			if province_id < 0 or province_id >= game_state.cities.size():
				continue
			var color := province_colors[province_id]
			if occupied[province_id] > 0 and (x + y) % 9 < 3:
				color = occupation_colors[province_id]
			image.set_pixel(x, y, color)
	return image


static func loyalty_color(value: float) -> Color:
	var normalized := clampf(value, 0.0, 100.0)
	if normalized <= 50.0:
		return LOYALTY_LOW_COLOR.lerp(
			LOYALTY_MID_COLOR, normalized / 50.0
		)
	return LOYALTY_MID_COLOR.lerp(
		LOYALTY_HIGH_COLOR, (normalized - 50.0) / 50.0
	)


static func build_loyalty_overlay_image(game_state: GameState) -> Image:
	var size := game_state.province_map_size
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var colors := PackedColorArray()
	colors.resize(game_state.cities.size())
	for city_id in range(game_state.cities.size()):
		colors[city_id] = (
			loyalty_color(game_state.cities[city_id].loyalty)
			if game_state.cities[city_id].politically_active
			else Color.TRANSPARENT
		)
	for y in range(size.y):
		for x in range(size.x):
			var province_id := game_state.province_ids[y * size.x + x]
			if province_id >= 0 and province_id < colors.size():
				image.set_pixel(x, y, colors[province_id])
	return image


static func loyalty_fill_signature(game_state: GameState) -> PackedInt64Array:
	var signature := PackedInt64Array()
	signature.resize(game_state.cities.size())
	for city_id in range(game_state.cities.size()):
		# A tenth of a point is finer than the visible gradient while preventing
		# floating-point noise from rebuilding a million-pixel texture.
		signature[city_id] = int(round(
			game_state.cities[city_id].loyalty * 10.0
		))
	return signature


## Compact semantic signature for political fill. This avoids rebuilding the
## 256x256 source image merely to discover that an alliance/war revision did
## not change any province color. Province topology is tracked separately.
static func political_fill_signature(
	game_state: GameState,
	view_nation_id: int = -1
) -> PackedInt64Array:
	var signature := PackedInt64Array()
	signature.resize(game_state.cities.size() * 4 + 1)
	signature[0] = view_nation_id
	for city_id in range(game_state.cities.size()):
		var current_owner := game_state.cities[city_id].owner_nation
		var recognized_owner := game_state.recognized_owner_of(city_id)
		if recognized_owner < 0:
			recognized_owner = current_owner
		var offset := city_id * 4 + 1
		signature[offset] = current_owner
		signature[offset + 1] = recognized_owner
		signature[offset + 2] = int(
			political_map_color_for_view(
				game_state, recognized_owner, view_nation_id
			).to_rgba32()
		)
		signature[offset + 3] = int(
			political_map_color_for_view(
				game_state, current_owner, view_nation_id
			).to_rgba32()
		)
	return signature


## Build the categorical political fill and, when requested, the three soft
## boundary layers derived from the same authoritative province topology.
static func build_political_canvas_images(
	game_state: GameState,
	boundary_geometry: Dictionary = {},
	include_soft_boundaries: bool = true,
	prebuilt_source: Image = null,
	apply_country_fade: bool = true,
	prebuilt_country_opacity: Image = null
) -> Dictionary:
	var source := prebuilt_source
	if source == null:
		source = build_province_overlay_image(game_state)
	if source == null or source.is_empty():
		return {
			"fill": source,
			"terrain_fill": source,
			"country_opacity": source,
			"province_boundaries": source,
			"country_boundaries": source,
		}
	var country_opacity := prebuilt_country_opacity
	if country_opacity == null or country_opacity.is_empty():
		country_opacity = build_country_fill_opacity_image(game_state)
	var fill := source.duplicate()
	if apply_country_fade:
		_apply_country_fill_opacity(fill, country_opacity)
	fill.resize(
		source.get_width() * PROVINCE_VISUAL_SUPERSAMPLE,
		source.get_height() * PROVINCE_VISUAL_SUPERSAMPLE,
		Image.INTERPOLATE_NEAREST
	)
	# The shader masks political color with authoritative terrain geometry, so
	# this texture only needs to supply a nearby province RGB where the coarse
	# ownership raster stops just inside the real coast. Dilate three source cells
	# before nearest-neighbor enlargement instead of scanning the 16x larger
	# supersampled image eight times. The enlarged low-resolution diamond fully
	# contains the old 8-texel dilation, preventing coastal color gaps; any extra
	# sea texels are discarded by the authoritative 0m terrain mask in shader.
	# This cuts synchronous ownership refresh from roughly 2.0s to ~0.1s.
	var terrain_fill := _dilate_political_fill(source, 3)
	terrain_fill.resize(
		source.get_width() * PROVINCE_VISUAL_SUPERSAMPLE,
		source.get_height() * PROVINCE_VISUAL_SUPERSAMPLE,
		Image.INTERPOLATE_NEAREST
	)
	if not include_soft_boundaries:
		return {
			"fill": fill,
			"terrain_fill": terrain_fill,
			"country_opacity": country_opacity,
		}
	var soft_boundaries := build_soft_boundary_images(game_state, boundary_geometry)
	return {
		"fill": fill,
		"terrain_fill": terrain_fill,
		"country_opacity": country_opacity,
		"province_boundaries": soft_boundaries["province"],
		"country_boundaries": soft_boundaries["country"],
	}


static func country_fill_opacity_for_distance(distance: float) -> float:
	return maxf(
		COUNTRY_FILL_MIN_OPACITY,
		1.0 - maxf(distance, 0.0) * COUNTRY_FILL_FADE_COEFFICIENT
	)


## 多源洪泛只在 256x256 所有权源图上运行。边界与海岸像素为 1，向同一
## 国家腹地按像素距离线性衰减；国家之间不会互相传播距离。
static func build_country_fill_opacity_image(game_state: GameState) -> Image:
	var city_owners := PackedInt32Array()
	city_owners.resize(game_state.cities.size())
	for city_id in range(game_state.cities.size()):
		city_owners[city_id] = game_state.cities[city_id].owner_nation
	return build_country_fill_opacity_image_from_owners(
		game_state.province_map_size,
		game_state.province_ids,
		city_owners
	)


## Worker-safe variant using detached packed arrays instead of GameState.
static func build_country_fill_opacity_image_from_owners(
	size: Vector2i,
	province_ids: PackedInt32Array,
	city_owners: PackedInt32Array
) -> Image:
	var width := maxi(size.x, 1)
	var height := maxi(size.y, 1)
	var pixel_count := width * height
	var owners := PackedInt32Array()
	owners.resize(pixel_count)
	owners.fill(-1)
	for y in range(size.y):
		for x in range(size.x):
			var index := y * width + x
			var province_id := province_ids[index]
			if province_id >= 0 and province_id < city_owners.size():
				owners[index] = city_owners[province_id]
	var distances := PackedFloat32Array()
	distances.resize(pixel_count)
	distances.fill(INF)
	var queue := PackedInt32Array()
	queue.resize(pixel_count)
	var tail := 0
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			var owner := owners[index]
			if owner < 0:
				continue
			var is_boundary := (
				x == 0 or x == width - 1 or y == 0 or y == height - 1
				or owners[index - 1] != owner
				or owners[index + 1] != owner
				or owners[index - width] != owner
				or owners[index + width] != owner
			)
			if is_boundary:
				distances[index] = 0.0
				queue[tail] = index
				tail += 1
	var head := 0
	while head < tail:
		var index := queue[head]
		head += 1
		var owner := owners[index]
		var x := index % width
		var y := index / width
		var next_distance := distances[index] + 1.0
		if (
			x > 0
			and owners[index - 1] == owner
			and distances[index - 1] > next_distance
		):
			distances[index - 1] = next_distance
			queue[tail] = index - 1
			tail += 1
		if (
			x + 1 < width
			and owners[index + 1] == owner
			and distances[index + 1] > next_distance
		):
			distances[index + 1] = next_distance
			queue[tail] = index + 1
			tail += 1
		if (
			y > 0
			and owners[index - width] == owner
			and distances[index - width] > next_distance
		):
			distances[index - width] = next_distance
			queue[tail] = index - width
			tail += 1
		if (
			y + 1 < height
			and owners[index + width] == owner
			and distances[index + width] > next_distance
		):
			distances[index + width] = next_distance
			queue[tail] = index + width
			tail += 1
	var opacity := Image.create(width, height, false, Image.FORMAT_RGBA8)
	opacity.fill(Color.TRANSPARENT)
	for index in range(pixel_count):
		if owners[index] < 0:
			continue
		var value := country_fill_opacity_for_distance(distances[index])
		opacity.set_pixel(
			index % width, index / width, Color(value, value, value, 1.0)
		)
	return opacity


static func _apply_country_fill_opacity(
	fill: Image, country_opacity: Image
) -> void:
	if fill == null or fill.is_empty() or country_opacity == null:
		return
	for y in range(fill.get_height()):
		for x in range(fill.get_width()):
			var color := fill.get_pixel(x, y)
			if color.a <= 0.001:
				continue
			color.a = country_opacity.get_pixel(x, y).r
			fill.set_pixel(x, y, color)


static func _dilate_political_fill(
	source: Image, radius: int
) -> Image:
	var result := source.duplicate()
	for _pass in range(maxi(radius, 0)):
		var previous := result.duplicate()
		var changed := false
		for y in range(result.get_height()):
			for x in range(result.get_width()):
				if previous.get_pixel(x, y).a > 0.5:
					continue
				for offset in [
					Vector2i.LEFT, Vector2i.RIGHT,
					Vector2i.UP, Vector2i.DOWN,
				]:
					var sample: Vector2i = Vector2i(x, y) + offset
					if (
						sample.x < 0 or sample.y < 0
						or sample.x >= result.get_width()
						or sample.y >= result.get_height()
					):
						continue
					var color: Color = previous.get_pixelv(sample)
					if color.a > 0.5:
						result.set_pixel(x, y, color)
						changed = true
						break
		if not changed:
			break
	return result


## 将共享平滑路径栅格化为硬实线。省界是纯黑 1px；国家边界
## 以共享中心为轴向两国各延伸 3px，RGB 由所在国家自身鲜艳颜色决定。
static func build_soft_boundary_images(
	game_state: GameState,
	boundary_geometry: Dictionary = {}
) -> Dictionary:
	var geometry := boundary_geometry
	if geometry.is_empty():
		geometry = build_province_boundary_segments(game_state)
	var source_size := game_state.province_map_size
	var output_size := Vector2i(
		maxi(source_size.x * PROVINCE_VISUAL_SUPERSAMPLE, 1),
		maxi(source_size.y * PROVINCE_VISUAL_SUPERSAMPLE, 1)
	)
	var province := _rasterize_soft_boundary_layer(
		geometry.get("province", PackedVector2Array()),
		output_size, LOCAL_BOUNDARY_INK, LOCAL_BOUNDARY_WIDTH_PX,
		BOUNDARY_ANTIALIAS_PX
	)
	var country := build_country_boundary_image(game_state, geometry, true)
	return {
		"province": province,
		"country": country,
	}


static func build_country_color_image(
	game_state: GameState,
	extend_to_real_coast: bool = false,
	view_nation_id: int = -1,
	prebuilt_country_opacity: Image = null
) -> Image:
	var source := build_country_color_source_image(
		game_state, view_nation_id
	)
	var country_opacity := prebuilt_country_opacity
	if country_opacity == null or country_opacity.is_empty():
		country_opacity = build_country_fill_opacity_image(game_state)
	return build_country_color_image_from_source(
		source, country_opacity, extend_to_real_coast
	)


static func build_country_color_source_image(
	game_state: GameState, view_nation_id: int = -1
) -> Image:
	var city_owners := PackedInt32Array()
	city_owners.resize(game_state.cities.size())
	for city_id in range(game_state.cities.size()):
		city_owners[city_id] = game_state.cities[city_id].owner_nation
	var boundary_colors := country_boundary_colors(
		game_state, view_nation_id
	)
	return build_country_color_source_image_from_owners(
		game_state.province_map_size,
		game_state.province_ids,
		city_owners,
		boundary_colors
	)


## Worker-safe country-color source builder for immutable ownership snapshots.
static func build_country_color_source_image_from_owners(
	source_size: Vector2i,
	province_ids: PackedInt32Array,
	city_owners: PackedInt32Array,
	boundary_colors: PackedColorArray
) -> Image:
	var source := Image.create(
		maxi(source_size.x, 1), maxi(source_size.y, 1),
		false, Image.FORMAT_RGBA8
	)
	source.fill(Color.TRANSPARENT)
	for y in range(source_size.y):
		for x in range(source_size.x):
			var index := y * source_size.x + x
			if index < 0 or index >= province_ids.size():
				continue
			var province_id := province_ids[index]
			if province_id < 0 or province_id >= city_owners.size():
				continue
			var owner_id := city_owners[province_id]
			source.set_pixel(
				x, y,
				boundary_colors[owner_id]
				if owner_id >= 0 and owner_id < boundary_colors.size()
				else Color.TRANSPARENT
			)
	return source


## Worker-safe finishing pass over immutable source images.
static func build_country_color_image_from_source(
	source: Image,
	country_opacity: Image,
	extend_to_real_coast: bool = false
) -> Image:
	var source_size := source.get_size()
	var result := (
		_extend_nearest_country_color(source, 3)
		if extend_to_real_coast
		else source
	)
	# Only original claimed texels fade. The short extension beyond the coarse
	# province mask stays opaque so the exact mesh coastline retains solid ink.
	for y in range(source_size.y):
		for x in range(source_size.x):
			if source.get_pixel(x, y).a <= 0.5:
				continue
			var color := result.get_pixel(x, y)
			color.a = country_opacity.get_pixel(x, y).r
			result.set_pixel(x, y, color)
	result.resize(
		maxi(source_size.x * PROVINCE_VISUAL_SUPERSAMPLE, 1),
		maxi(source_size.y * PROVINCE_VISUAL_SUPERSAMPLE, 1),
		Image.INTERPOLATE_NEAREST
	)
	return result


## Extend owner colors just beyond the coarse province mask for the true 0m
## mesh coastline. Each destination selects the nearest original land texel;
## stable source-index tie-breaking prevents iteration order from leaking a
## neighboring country's color into narrow straits or border river mouths.
static func _extend_nearest_country_color(
	source: Image, radius: int
) -> Image:
	var result := source.duplicate()
	var width := source.get_width()
	var height := source.get_height()
	var search_radius := maxi(radius, 0)
	for y in range(height):
		for x in range(width):
			if source.get_pixel(x, y).a > 0.5:
				continue
			var best_distance := INF
			var best_index := 9223372036854775807
			var best_color := Color.TRANSPARENT
			for offset_y in range(-search_radius, search_radius + 1):
				for offset_x in range(-search_radius, search_radius + 1):
					var sample_x := x + offset_x
					var sample_y := y + offset_y
					if (
						sample_x < 0 or sample_x >= width
						or sample_y < 0 or sample_y >= height
					):
						continue
					var color := source.get_pixel(sample_x, sample_y)
					if color.a <= 0.5:
						continue
					var distance := float(offset_x * offset_x + offset_y * offset_y)
					var source_index := sample_y * width + sample_x
					if (
						distance < best_distance
						or (
							is_equal_approx(distance, best_distance)
							and source_index < best_index
						)
					):
						best_distance = distance
						best_index = source_index
						best_color = color
			if best_color.a > 0.5:
				result.set_pixel(x, y, best_color)
	return result


static func build_country_boundary_image(
	game_state: GameState,
	boundary_geometry: Dictionary = {},
	include_coast: bool = false,
	view_nation_id: int = -1
) -> Image:
	var geometry := boundary_geometry
	if geometry.is_empty():
		geometry = build_province_boundary_segments(game_state)
	return build_country_boundary_image_from_visuals(
		game_state.province_map_size,
		country_boundary_colors(game_state, view_nation_id),
		geometry,
		include_coast
	)


## Worker-safe boundary raster entry: every input is an immutable visual
## snapshot, so no background task needs to retain or read live GameState.
static func build_country_boundary_image_from_visuals(
	source_size: Vector2i,
	boundary_colors: PackedColorArray,
	geometry: Dictionary,
	include_coast: bool = false
) -> Image:
	var output_size := Vector2i(
		maxi(source_size.x * PROVINCE_VISUAL_SUPERSAMPLE, 1),
		maxi(source_size.y * PROVINCE_VISUAL_SUPERSAMPLE, 1)
	)
	var country := Image.create(
		output_size.x, output_size.y, false, Image.FORMAT_RGBA8
	)
	country.fill(Color(0.0, 0.0, 0.0, 0.0))
	var closest_distance_key := PackedInt32Array()
	closest_distance_key.resize(output_size.x * output_size.y)
	closest_distance_key.fill(2147483647)
	var closest_owner := PackedInt32Array()
	closest_owner.resize(output_size.x * output_size.y)
	closest_owner.fill(2147483647)
	_rasterize_owned_boundary_sides(
		country, boundary_colors,
		geometry.get("country", PackedVector2Array()),
		geometry.get("country_owner_a", PackedInt32Array()),
		geometry.get("country_owner_b", PackedInt32Array()),
		geometry.get("country_side_a", PackedVector2Array()),
		geometry.get("country_side_b", PackedVector2Array()),
		closest_distance_key, closest_owner
	)
	if include_coast:
		_rasterize_owned_boundary_sides(
			country, boundary_colors,
			geometry.get("coast", PackedVector2Array()),
			geometry.get("coast_owner", PackedInt32Array()),
			PackedInt32Array(),
			geometry.get("coast_side", PackedVector2Array()),
			PackedVector2Array(),
			closest_distance_key, closest_owner
		)
	return country


static func _rasterize_owned_boundary_sides(
	image: Image,
	boundary_colors: PackedColorArray,
	segments: PackedVector2Array,
	owner_a: PackedInt32Array,
	owner_b: PackedInt32Array,
	side_a: PackedVector2Array,
	side_b: PackedVector2Array,
	closest_distance_key: PackedInt32Array = PackedInt32Array(),
	closest_owner: PackedInt32Array = PackedInt32Array()
) -> void:
	var segment_count := segments.size() / 2
	if segment_count <= 0:
		return
	var image_size := Vector2(image.get_size())
	# Coverage alone is flat throughout the 3px core, so it cannot arbitrate
	# overlaps at bends and three-country junctions. Keep the actual closest
	# curve distance and owner beside the image; equal-distance ties resolve by
	# owner id and therefore never depend on raster scan order.
	var pixel_count := image.get_width() * image.get_height()
	if closest_distance_key.size() != pixel_count:
		closest_distance_key.resize(pixel_count)
		closest_distance_key.fill(2147483647)
	if closest_owner.size() != pixel_count:
		closest_owner.resize(pixel_count)
		closest_owner.fill(2147483647)
	for index in range(segment_count):
		var from := segments[index * 2] * image_size
		var to := segments[index * 2 + 1] * image_size
		if index < owner_a.size() and index < side_a.size():
			_rasterize_owned_boundary_side(
				image, boundary_colors, from, to, owner_a[index],
				side_a[index], closest_distance_key, closest_owner
			)
		if index < owner_b.size() and index < side_b.size():
			_rasterize_owned_boundary_side(
				image, boundary_colors, from, to, owner_b[index],
				side_b[index], closest_distance_key, closest_owner
			)


static func _rasterize_owned_boundary_side(
	image: Image,
	boundary_colors: PackedColorArray,
	from: Vector2,
	to: Vector2,
	owner_id: int,
	side_vector: Vector2,
	closest_distance_key: PackedInt32Array,
	closest_owner: PackedInt32Array
) -> void:
	var direction := (to - from).normalized()
	if direction.length_squared() <= 0.000001:
		return
	var normal := Vector2(-direction.y, direction.x)
	if side_vector.dot(normal) < 0.0:
		normal = -normal
	var color := (
		boundary_colors[owner_id]
		if owner_id >= 0 and owner_id < boundary_colors.size()
		else Color.TRANSPARENT
	)
	var segment_length := from.distance_to(to)
	var outer_width := COUNTRY_BOUNDARY_WIDTH_PX + BOUNDARY_ANTIALIAS_PX
	# Curved topology is already split into short micro-segments (about 3 px on
	# the 500-city map). Visit each candidate pixel once instead of stamping a
	# heavily overlapping round brush every 0.34 px along the same segment.
	var x_from := clampi(
		int(floor(minf(from.x, to.x) - outer_width - 1.0)),
		0, image.get_width() - 1
	)
	var x_to := clampi(
		int(ceil(maxf(from.x, to.x) + outer_width + 1.0)),
		0, image.get_width() - 1
	)
	var y_from := clampi(
		int(floor(minf(from.y, to.y) - outer_width - 1.0)),
		0, image.get_height() - 1
	)
	var y_to := clampi(
		int(ceil(maxf(from.y, to.y) + outer_width + 1.0)),
		0, image.get_height() - 1
	)
	for y in range(y_from, y_to + 1):
		for x in range(x_from, x_to + 1):
			var sample := Vector2(float(x) + 0.5, float(y) + 0.5)
			var along := clampf(
				(sample - from).dot(direction), 0.0, segment_length
			)
			var nearest := from + direction * along
			var side_distance := (sample - nearest).dot(normal)
			var distance := sample.distance_to(nearest)
			if side_distance < 0.0 or distance >= outer_width:
				continue
			var pixel_index := y * image.get_width() + x
			# A fixed-point pixel-distance key makes arbitration a strict,
			# transitive lexicographic minimum instead of an epsilon relation.
			var distance_key := int(round(distance * 1048576.0))
			var old_distance_key := closest_distance_key[pixel_index]
			var old_owner := closest_owner[pixel_index]
			if (
				distance_key > old_distance_key
				or (
					distance_key == old_distance_key
					and owner_id >= old_owner
				)
			):
				continue
			var coverage := (
				1.0
				if (
					BOUNDARY_ANTIALIAS_PX <= 0.000001
					or distance <= COUNTRY_BOUNDARY_WIDTH_PX
				)
				else 1.0 - smoothstep(
					COUNTRY_BOUNDARY_WIDTH_PX, outer_width, distance
				)
			)
			var source := color
			source.a = coverage
			closest_distance_key[pixel_index] = distance_key
			closest_owner[pixel_index] = owner_id
			image.set_pixel(x, y, source)


static func _rasterize_soft_boundary_layer(
	segments: PackedVector2Array,
	size: Vector2i,
	color: Color,
	core_width_px: float,
	feather_px: float
) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_rasterize_soft_segments_into(
		image, segments, color, core_width_px, feather_px
	)
	return image


static func _rasterize_soft_segments_into(
	image: Image,
	segments: PackedVector2Array,
	color: Color,
	core_width_px: float,
	feather_px: float
) -> void:
	if image == null or image.is_empty() or segments.size() < 2:
		return
	var image_size := Vector2(image.get_width(), image.get_height())
	var core_radius := maxf(core_width_px * 0.5, 0.05)
	var outer_radius := core_radius + maxf(feather_px, 0.0)
	for index in range(0, segments.size(), 2):
		var from := segments[index] * image_size
		var to := segments[index + 1] * image_size
		# 沿线盖小圆笔刷，复杂度与线长成正比。旧实现逐段扫描完整
		# 包围矩形，斜长线会退化为 O(width*height)，一次归属刷新需秒级。
		var step_count := maxi(int(ceil(from.distance_to(to) / 0.34)), 1)
		for step in range(step_count + 1):
			var center := from.lerp(to, float(step) / float(step_count))
			var x_from := clampi(
				int(floor(center.x - outer_radius - 0.5)), 0, image.get_width() - 1
			)
			var x_to := clampi(
				int(ceil(center.x + outer_radius + 0.5)), 0, image.get_width() - 1
			)
			var y_from := clampi(
				int(floor(center.y - outer_radius - 0.5)), 0, image.get_height() - 1
			)
			var y_to := clampi(
				int(ceil(center.y + outer_radius + 0.5)), 0, image.get_height() - 1
			)
			for y in range(y_from, y_to + 1):
				for x in range(x_from, x_to + 1):
					var distance := Vector2(
						float(x) + 0.5, float(y) + 0.5
					).distance_to(center)
					if distance >= outer_radius:
						continue
					var coverage := (
						1.0
						if feather_px <= 0.000001 or distance <= core_radius
						else 1.0 - smoothstep(core_radius, outer_radius, distance)
					)
					var source := color
					source.a *= coverage
					var destination := image.get_pixel(x, y)
					# Coverage 取最大值而非反复 source-over；相邻小线段和三岔口
					# 不得把 0.52 墨量累加成近乎不透明的黑结。相同 coverage 时
					# 后写入的外交类别取得确定性优先级。
					if source.a + 0.0001 < destination.a:
						continue
					image.set_pixel(x, y, source)



static func paper_nation_color(color: Color) -> Color:
	return GameState.normalize_nation_color(color)


static func country_boundary_display_color(color: Color) -> Color:
	return Color.from_hsv(
		color.h,
		clampf(color.s + COUNTRY_BOUNDARY_SATURATION_OFFSET, 0.0, 1.0),
		clampf(color.v + COUNTRY_BOUNDARY_VALUE_OFFSET, 0.0, 1.0),
		1.0
	)


static func country_boundary_colors(
	game_state: GameState, view_nation_id: int = -1
) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(game_state.nations.size())
	for nation_id in range(game_state.nations.size()):
		colors[nation_id] = nation_boundary_color(
			game_state, nation_id, view_nation_id
		)
	return colors


## 国界始终使用所属国家本色，不随外交观察模式切换成关系分类色。
static func nation_boundary_color(
	game_state: GameState,
	nation_id: int,
	_view_nation_id: int = -1
) -> Color:
	if (
		game_state == null
		or nation_id < 0
		or nation_id >= game_state.nations.size()
	):
		return Color.TRANSPARENT
	return country_boundary_display_color(
		paper_nation_color(game_state.nations[nation_id].color)
	)


## Political-map color is intentionally shared by 2D and 3D renderers. A
## peaceful vassal inherits its ultimate sovereign's hue and is 5% darker per
## level, so each fief remains legible without looking like a foreign bloc.
static func political_map_color(
	game_state: GameState,
	nation_id: int
) -> Color:
	if (
		game_state == null
		or nation_id < 0
		or nation_id >= game_state.nations.size()
	):
		return Color(0.45, 0.45, 0.43)
	if game_state.is_in_civil_war(nation_id):
		return paper_nation_color(game_state.nations[nation_id].color)
	var sovereign_id := nation_id
	var depth := 0
	var guard := game_state.nations.size()
	while game_state.is_vassal(sovereign_id) and guard > 0:
		var overlord_id := game_state.overlord_of(sovereign_id)
		if (
			overlord_id < 0
			or overlord_id >= game_state.nations.size()
			or game_state.is_in_civil_war(sovereign_id)
		):
			break
		sovereign_id = overlord_id
		depth += 1
		guard -= 1
	var result := paper_nation_color(
		game_state.nations[sovereign_id].color
	)
	var accumulated_darken := 1.0 - pow(
		1.0 - VASSAL_BRIGHTNESS_STEP,
		float(depth)
	)
	return Color.from_hsv(
		result.h,
		clampf(result.s + 0.03, GameState.NATION_COLOR_SATURATION_MIN, GameState.NATION_COLOR_SATURATION_MAX),
		clampf(result.v * (1.0 - accumulated_darken), 0.24, GameState.NATION_COLOR_VALUE_MAX),
		result.a
	)


## 外交视角的领土分类色。观察国保留自身阵营色；其他国家按战争、
## 本国宗藩体系、盟友、中立依次映射为红、灰、绿、黑。
static func political_map_color_for_view(
	game_state: GameState,
	nation_id: int,
	view_nation_id: int = -1
) -> Color:
	if (
		game_state == null
		or nation_id < 0
		or nation_id >= game_state.nations.size()
	):
		return Color(0.45, 0.45, 0.43)
	if (
		view_nation_id < 0
		or view_nation_id >= game_state.nations.size()
		or not game_state.nations[view_nation_id].alive
	):
		return political_map_color(game_state, nation_id)
	if nation_id == view_nation_id:
		return political_map_color(game_state, nation_id)
	if game_state.is_enemy(view_nation_id, nation_id):
		return DIPLOMACY_ENEMY_COLOR
	if _is_peaceful_subject_of(game_state, nation_id, view_nation_id):
		return DIPLOMACY_VASSAL_COLOR
	if game_state.is_allied(view_nation_id, nation_id):
		return DIPLOMACY_ALLY_COLOR
	return DIPLOMACY_NEUTRAL_COLOR


static func _is_peaceful_subject_of(
	game_state: GameState,
	candidate_id: int,
	view_nation_id: int
) -> bool:
	var current := candidate_id
	var guard := game_state.nations.size()
	while game_state.is_vassal(current) and guard > 0:
		if game_state.is_in_civil_war(current):
			return false
		current = game_state.overlord_of(current)
		if current == view_nation_id:
			return true
		guard -= 1
	return false


## 将地图归一化坐标解析为省份的当前实控国家；海面与越界点返回 -1。
static func nation_at_map_position(
	game_state: GameState,
	map_position: Vector2
) -> int:
	if (
		game_state == null
		or game_state.province_map_size.x <= 0
		or game_state.province_map_size.y <= 0
		or game_state.province_ids.is_empty()
		or map_position.x < 0.0
		or map_position.x >= 1.0
		or map_position.y < 0.0
		or map_position.y >= 1.0
	):
		return -1
	var pixel := Vector2i(
		clampi(
			int(floor(map_position.x * game_state.province_map_size.x)),
			0, game_state.province_map_size.x - 1
		),
		clampi(
			int(floor(map_position.y * game_state.province_map_size.y)),
			0, game_state.province_map_size.y - 1
		)
	)
	var province_id := game_state.province_ids[
		pixel.y * game_state.province_map_size.x + pixel.x
	]
	if province_id < 0 or province_id >= game_state.cities.size():
		return -1
	return game_state.cities[province_id].owner_nation


## Counters and offensive arrows need a denser ink than the broad political
## fill: preserve the same faction hue, raise chroma and lower brightness.
static func command_marker_color(
	game_state: GameState,
	nation_id: int
) -> Color:
	return political_map_color(game_state, nation_id)


static func final_faction_visual_color(
	game_state: GameState,
	nation_id: int,
	alert_mix: float = 0.0,
	highlight: float = 0.0
) -> Color:
	var result := command_marker_color(game_state, nation_id)
	if alert_mix > 0.0:
		result = result.lerp(
			Color.from_hsv(0.0, 0.68, 0.68),
			clampf(alert_mix, 0.0, 1.0)
		)
	if highlight > 0.0:
		result = Color.from_hsv(
			result.h, result.s,
			clampf(
				result.v + highlight,
				GameState.NATION_COLOR_VALUE_MIN,
				GameState.NATION_COLOR_VALUE_MAX
			), result.a
		)
	var minimum_value := (
		0.24 if game_state.is_vassal(nation_id) else GameState.NATION_COLOR_VALUE_MIN
	)
	return Color.from_hsv(
		result.h,
		clampf(result.s, GameState.NATION_COLOR_SATURATION_MIN, GameState.NATION_COLOR_SATURATION_MAX),
		clampf(result.v, minimum_value, GameState.NATION_COLOR_VALUE_MAX),
		result.a
	)


static func build_province_boundary_segments(
	game_state: GameState
) -> Dictionary:
	return classify_province_boundary_topology(
		game_state, build_province_boundary_topology(game_state)
	)


## Geometry/topology is independent from ownership and diplomacy. Cache this
## object across ordinary captures and relation changes; only a province_ids
## rebuild (for example moving a city in the editor) invalidates it.
static func build_province_boundary_topology(
	game_state: GameState
) -> Dictionary:
	var province := PackedVector2Array()
	var coast := PackedVector2Array()
	var province_a := PackedInt32Array()
	var province_b := PackedInt32Array()
	var province_side_a := PackedVector2Array()
	var province_side_b := PackedVector2Array()
	var coast_province := PackedInt32Array()
	var coast_side := PackedVector2Array()
	var size := game_state.province_map_size
	var contract_metadata := {
		"contract_version": 1,
		"render_only": true,
		"source_size": size,
		"source_hash": hash(game_state.province_ids),
	}
	if size.x <= 0 or size.y <= 0:
		return contract_metadata.merged({
			"province": province,
			"coast": coast,
			"province_a": province_a,
			"province_b": province_b,
			"province_side_a": province_side_a,
			"province_side_b": province_side_b,
			"coast_province": coast_province,
			"coast_side": coast_side,
		})
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
				coast_province.append(province_id)
				coast_side.append(Vector2.RIGHT)
			if top < 0:
				_append_segment(coast, Vector2(x0, y0), Vector2(x1, y0))
				coast_province.append(province_id)
				coast_side.append(Vector2.DOWN)
			if right < 0:
				_append_segment(coast, Vector2(x1, y0), Vector2(x1, y1))
				coast_province.append(province_id)
				coast_side.append(Vector2.LEFT)
			elif right != province_id:
				_append_segment(province, Vector2(x1, y0), Vector2(x1, y1))
				province_a.append(province_id)
				province_b.append(right)
				province_side_a.append(Vector2.LEFT)
				province_side_b.append(Vector2.RIGHT)
			if bottom < 0:
				_append_segment(coast, Vector2(x0, y1), Vector2(x1, y1))
				coast_province.append(province_id)
				coast_side.append(Vector2.UP)
			elif bottom != province_id:
				_append_segment(province, Vector2(x0, y1), Vector2(x1, y1))
				province_a.append(province_id)
				province_b.append(bottom)
				province_side_a.append(Vector2.UP)
				province_side_b.append(Vector2.DOWN)
	var curved_province := _curve_subdivide_boundary_graph(
		province,
		{
			"kind": "province",
			"province_a": province_a,
			"province_b": province_b,
			"side_a": province_side_a,
			"side_b": province_side_b,
		},
		size
	)
	var curved_coast := _curve_subdivide_boundary_graph(
		coast,
		{
			"kind": "coast",
			"coast_province": coast_province,
			"coast_side": coast_side,
		},
		size
	)
	return contract_metadata.merged({
		"province": curved_province["segments"],
		"coast": curved_coast["segments"],
		"province_a": curved_province["province_a"],
		"province_b": curved_province["province_b"],
		"province_side_a": curved_province["province_side_a"],
		"province_side_b": curved_province["province_side_b"],
		"coast_province": curved_coast["coast_province"],
		"coast_side": curved_coast["coast_side"],
	})


## Reclassify cached, already-smoothed city-border edges by current control.
## Every cross-country edge belongs to one country layer regardless of alliance
## or war: its two visible sides receive their respective national colors later.
static func classify_province_boundary_topology(
	game_state: GameState,
	topology: Dictionary
) -> Dictionary:
	var province: PackedVector2Array = topology.get(
		"province", PackedVector2Array()
	)
	var province_a: PackedInt32Array = topology.get(
		"province_a", PackedInt32Array()
	)
	var province_b: PackedInt32Array = topology.get(
		"province_b", PackedInt32Array()
	)
	var province_side_a: PackedVector2Array = topology.get(
		"province_side_a", PackedVector2Array()
	)
	var province_side_b: PackedVector2Array = topology.get(
		"province_side_b", PackedVector2Array()
	)
	var local := PackedVector2Array()
	var country := PackedVector2Array()
	var country_owner_a := PackedInt32Array()
	var country_owner_b := PackedInt32Array()
	var country_side_a := PackedVector2Array()
	var country_side_b := PackedVector2Array()
	# Keep diplomatic subsets as non-visual semantic diagnostics. Rendering uses
	# only country, so alliances and wars never override either nation's color.
	var nation := PackedVector2Array()
	var alliance := PackedVector2Array()
	var enemy := PackedVector2Array()
	var suzerainty := PackedVector2Array()
	var edge_count := mini(
		mini(province_a.size(), province_b.size()), province.size() / 2
	)
	for edge_index in range(edge_count):
		var city_a := province_a[edge_index]
		var city_b := province_b[edge_index]
		var from := province[edge_index * 2]
		var to := province[edge_index * 2 + 1]
		if not _province_owners_differ(game_state, city_a, city_b):
			_append_segment(local, from, to)
		else:
			_append_segment(country, from, to)
			country_owner_a.append(game_state.cities[city_a].owner_nation)
			country_owner_b.append(game_state.cities[city_b].owner_nation)
			country_side_a.append(province_side_a[edge_index])
			country_side_b.append(province_side_b[edge_index])
			if _province_owners_same_peaceful_suzerainty(
				game_state, city_a, city_b
			):
				_append_segment(suzerainty, from, to)
			elif _province_owners_allied(game_state, city_a, city_b):
				_append_segment(alliance, from, to)
			elif _province_owners_enemy(game_state, city_a, city_b):
				_append_segment(enemy, from, to)
			else:
				_append_segment(nation, from, to)
	var coast_owner := PackedInt32Array()
	var coast_province: PackedInt32Array = topology.get(
		"coast_province", PackedInt32Array()
	)
	for coast_city in coast_province:
		coast_owner.append(
			game_state.cities[coast_city].owner_nation
			if coast_city >= 0 and coast_city < game_state.cities.size() else -1
		)
	return {
		"province": province,
		"local": local,
		"country": country,
		"country_owner_a": country_owner_a,
		"country_owner_b": country_owner_b,
		"country_side_a": country_side_a,
		"country_side_b": country_side_b,
		"nation": nation,
		"alliance": alliance,
		"enemy": enemy,
		"suzerainty": suzerainty,
		"coast": topology.get("coast", PackedVector2Array()),
		"coast_owner": coast_owner,
		"coast_side": topology.get("coast_side", PackedVector2Array()),
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


static func _province_owners_enemy(
	game_state: GameState, province_a: int, province_b: int
) -> bool:
	if province_a < 0 or province_b < 0:
		return false
	return game_state.is_enemy(
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


## Trace the raster boundary graph by maximal constant-semantic chains first,
## then run a light pixel-space RDP pass before centripetal curve subdivision.
## This
## keeps junctions/endpoints pinned, makes closed-loop ordering deterministic,
## and lets every curved micro-segment carry explicit side-aware metadata.
static func _curve_subdivide_boundary_graph(
	segments: PackedVector2Array,
	metadata: Dictionary,
	raster_size: Vector2i,
	subdivisions: int = 4,
	rdp_tolerance_px: float = 0.85
) -> Dictionary:
	var kind := str(metadata.get("kind", ""))
	var result := {
		"segments": PackedVector2Array(),
		"province_a": PackedInt32Array(),
		"province_b": PackedInt32Array(),
		"province_side_a": PackedVector2Array(),
		"province_side_b": PackedVector2Array(),
		"coast_province": PackedInt32Array(),
		"coast_side": PackedVector2Array(),
	}
	if segments.size() < 2:
		return result
	var semantic_edges := _build_boundary_semantic_edges(segments, metadata)
	if semantic_edges.is_empty():
		return result
	var chains := _trace_boundary_semantic_chains(semantic_edges)
	for chain in chains:
		var source_points: PackedVector2Array = chain.get(
			"points", PackedVector2Array()
		)
		if source_points.size() < 2:
			continue
		var closed := bool(chain.get("closed", false))
		var simplified := _simplify_boundary_path(
			source_points, raster_size, closed, rdp_tolerance_px
		)
		if simplified.size() < 2:
			continue
		if kind == "province":
			_append_curved_province_boundary_chain(
				result, simplified, closed, chain, maxi(subdivisions, 1)
			)
		elif kind == "coast":
			_append_curved_coast_boundary_chain(
				result, simplified, closed, chain, maxi(subdivisions, 1)
			)
	return result


static func _build_boundary_semantic_edges(
	segments: PackedVector2Array,
	metadata: Dictionary
) -> Array:
	var kind := str(metadata.get("kind", ""))
	var result: Array = []
	var edge_count := segments.size() / 2
	var province_a: PackedInt32Array = metadata.get(
		"province_a", PackedInt32Array()
	)
	var province_b: PackedInt32Array = metadata.get(
		"province_b", PackedInt32Array()
	)
	var side_a: PackedVector2Array = metadata.get(
		"side_a", PackedVector2Array()
	)
	var side_b: PackedVector2Array = metadata.get(
		"side_b", PackedVector2Array()
	)
	var coast_province: PackedInt32Array = metadata.get(
		"coast_province", PackedInt32Array()
	)
	var coast_side: PackedVector2Array = metadata.get(
		"coast_side", PackedVector2Array()
	)
	for edge_index in range(edge_count):
		var from := segments[edge_index * 2]
		var to := segments[edge_index * 2 + 1]
		if from.is_equal_approx(to):
			continue
		var edge := {
			"id": result.size(),
			"from": from,
			"to": to,
			"from_key": _boundary_point_key(from),
			"to_key": _boundary_point_key(to),
			"kind": kind,
		}
		if kind == "province":
			var city_a := (
				province_a[edge_index]
				if edge_index < province_a.size()
				else -1
			)
			var city_b := (
				province_b[edge_index]
				if edge_index < province_b.size()
				else -1
			)
			edge["province_a"] = city_a
			edge["province_b"] = city_b
			edge["side_a"] = (
				side_a[edge_index]
				if edge_index < side_a.size()
				else Vector2.ZERO
			)
			edge["side_b"] = (
				side_b[edge_index]
				if edge_index < side_b.size()
				else Vector2.ZERO
			)
			edge["semantic_key"] = _province_pair_key(city_a, city_b)
		elif kind == "coast":
			var province_id := (
				coast_province[edge_index]
				if edge_index < coast_province.size()
				else -1
			)
			edge["coast_province"] = province_id
			edge["coast_side"] = (
				coast_side[edge_index]
				if edge_index < coast_side.size()
				else Vector2.ZERO
			)
			edge["semantic_key"] = "coast:%d" % province_id
		else:
			continue
		result.append(edge)
	return result


static func _trace_boundary_semantic_chains(
	semantic_edges: Array
) -> Array:
	var positions := {}
	var adjacency := {}
	var global_degree := {}
	var edges_by_semantic := {}
	for edge_value in semantic_edges:
		var edge: Dictionary = edge_value
		var semantic_key := str(edge.get("semantic_key", ""))
		var from_key := str(edge.get("from_key", ""))
		var to_key := str(edge.get("to_key", ""))
		positions[from_key] = edge.get("from", Vector2.ZERO)
		positions[to_key] = edge.get("to", Vector2.ZERO)
		global_degree[from_key] = int(global_degree.get(from_key, 0)) + 1
		global_degree[to_key] = int(global_degree.get(to_key, 0)) + 1
		if not edges_by_semantic.has(semantic_key):
			edges_by_semantic[semantic_key] = []
		(edges_by_semantic[semantic_key] as Array).append(edge)
		if not adjacency.has(semantic_key):
			adjacency[semantic_key] = {}
		var semantic_adjacency: Dictionary = adjacency[semantic_key]
		if not semantic_adjacency.has(from_key):
			semantic_adjacency[from_key] = []
		if not semantic_adjacency.has(to_key):
			semantic_adjacency[to_key] = []
		(semantic_adjacency[from_key] as Array).append(int(edge["id"]))
		(semantic_adjacency[to_key] as Array).append(int(edge["id"]))
	var traced: Array = []
	var visited := {}
	var semantic_keys: Array = edges_by_semantic.keys()
	semantic_keys.sort()
	for semantic_key_value in semantic_keys:
		var semantic_key := str(semantic_key_value)
		var semantic_edges_list: Array = edges_by_semantic[semantic_key]
		var semantic_adjacency: Dictionary = adjacency[semantic_key]
		var vertex_keys: Array = semantic_adjacency.keys()
		vertex_keys.sort()
		for vertex_key_value in vertex_keys:
			var vertex_key := str(vertex_key_value)
			var incident := _sort_incident_edges(
				semantic_adjacency[vertex_key], semantic_edges, vertex_key
			)
			if incident.size() == 2 and int(global_degree[vertex_key]) == 2:
				continue
			for edge_id_value in incident:
				var edge_id := int(edge_id_value)
				if bool(visited.get(edge_id, false)):
					continue
				var chain := _trace_boundary_semantic_chain(
					vertex_key,
					edge_id,
					semantic_edges,
					semantic_adjacency,
					global_degree,
					positions,
					visited
				)
				var traced_points: PackedVector2Array = chain.get(
					"points", PackedVector2Array()
				)
				if not traced_points.is_empty():
					traced.append(chain)
		var remaining := _sort_semantic_edges(semantic_edges_list)
		for edge_value in remaining:
			var edge: Dictionary = edge_value
			var edge_id := int(edge.get("id", -1))
			if edge_id < 0 or bool(visited.get(edge_id, false)):
				continue
			var loop_start := _deterministic_loop_start(edge)
			var chain := _trace_boundary_semantic_chain(
				str(loop_start["start_key"]),
				int(loop_start["edge_id"]),
				semantic_edges,
				semantic_adjacency,
				global_degree,
				positions,
				visited
			)
			var loop_points: PackedVector2Array = chain.get(
				"points", PackedVector2Array()
			)
			if not loop_points.is_empty():
				traced.append(chain)
	return traced


static func _sort_incident_edges(
	incident_edges: Array,
	semantic_edges: Array,
	vertex_key: String
) -> Array:
	var sorted_edges := incident_edges.duplicate()
	sorted_edges.sort_custom(func(a: int, b: int) -> bool:
		return _incident_edge_sort_key(semantic_edges[a], vertex_key) < _incident_edge_sort_key(semantic_edges[b], vertex_key)
	)
	return sorted_edges


static func _sort_semantic_edges(semantic_edges: Array) -> Array:
	var sorted_edges := semantic_edges.duplicate()
	sorted_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _semantic_edge_sort_key(a) < _semantic_edge_sort_key(b)
	)
	return sorted_edges


static func _trace_boundary_semantic_chain(
	start_key: String,
	first_edge_id: int,
	semantic_edges: Array,
	adjacency: Dictionary,
	global_degree: Dictionary,
	positions: Dictionary,
	visited: Dictionary
) -> Dictionary:
	var points := PackedVector2Array()
	var oriented_edges: Array = []
	if not positions.has(start_key):
		return {"points": points, "closed": false, "edges": oriented_edges}
	points.append(positions[start_key])
	var current_key := start_key
	var edge_id := first_edge_id
	var closed := false
	while edge_id >= 0:
		if bool(visited.get(edge_id, false)):
			break
		visited[edge_id] = true
		var edge: Dictionary = semantic_edges[edge_id]
		var next_key := (
			str(edge["to_key"])
			if str(edge["from_key"]) == current_key
			else str(edge["from_key"])
		)
		oriented_edges.append(
			_orient_boundary_edge(edge, current_key, next_key)
		)
		points.append(positions[next_key])
		if next_key == start_key:
			closed = true
			break
		var incident: Array = adjacency.get(next_key, [])
		if (
			incident.size() != 2
			or int(global_degree.get(next_key, 0)) != 2
		):
			break
		var candidate := (
			int(incident[1])
			if int(incident[0]) == edge_id
			else int(incident[0])
		)
		if bool(visited.get(candidate, false)):
			break
		current_key = next_key
		edge_id = candidate
	return {"points": points, "closed": closed, "edges": oriented_edges}


static func _orient_boundary_edge(
	edge: Dictionary,
	from_key: String,
	to_key: String
) -> Dictionary:
	var oriented := edge.duplicate()
	if str(edge.get("from_key", "")) == from_key:
		oriented["from"] = edge.get("from", Vector2.ZERO)
		oriented["to"] = edge.get("to", Vector2.ZERO)
	else:
		oriented["from"] = edge.get("to", Vector2.ZERO)
		oriented["to"] = edge.get("from", Vector2.ZERO)
	oriented["from_key"] = from_key
	oriented["to_key"] = to_key
	return oriented


static func _append_curved_province_boundary_chain(
	result: Dictionary,
	path: PackedVector2Array,
	closed: bool,
	chain: Dictionary,
	subdivisions: int
) -> void:
	var oriented_edges: Array = chain.get("edges", [])
	if oriented_edges.is_empty():
		return
	var side_info := _province_chain_side_info(oriented_edges[0])
	var province_left := int(side_info["left_province"])
	var province_right := int(side_info["right_province"])
	var result_province_a: PackedInt32Array = result["province_a"]
	var result_province_b: PackedInt32Array = result["province_b"]
	var result_side_a: PackedVector2Array = result["province_side_a"]
	var result_side_b: PackedVector2Array = result["province_side_b"]
	_append_curved_boundary_chain_segments(
		result,
		path,
		closed,
		subdivisions,
		func(normal: Vector2) -> void:
			result_province_a.append(province_left)
			result_province_b.append(province_right)
			result_side_a.append(normal)
			result_side_b.append(-normal)
	)


static func _append_curved_coast_boundary_chain(
	result: Dictionary,
	path: PackedVector2Array,
	closed: bool,
	chain: Dictionary,
	subdivisions: int
) -> void:
	var oriented_edges: Array = chain.get("edges", [])
	if oriented_edges.is_empty():
		return
	var first_edge: Dictionary = oriented_edges[0]
	var side_sign := _coast_chain_side_sign(first_edge)
	var province_id := int(first_edge.get("coast_province", -1))
	var result_coast_province: PackedInt32Array = result["coast_province"]
	var result_coast_side: PackedVector2Array = result["coast_side"]
	_append_curved_boundary_chain_segments(
		result,
		path,
		closed,
		subdivisions,
		func(normal: Vector2) -> void:
			result_coast_province.append(province_id)
			result_coast_side.append(normal * side_sign)
	)


static func _append_curved_boundary_chain_segments(
	result: Dictionary,
	path: PackedVector2Array,
	closed: bool,
	subdivisions: int,
	append_metadata: Callable
) -> void:
	var result_segments: PackedVector2Array = result["segments"]
	var point_count := path.size()
	var segment_count := (
		point_count
		if closed
		else point_count - 1
	)
	for segment_index in range(segment_count):
		var next_index := (segment_index + 1) % point_count
		var from := path[segment_index]
		var previous := from
		for sample_index in range(1, subdivisions + 1):
			var ratio := float(sample_index) / float(subdivisions)
			var point := _centripetal_boundary_point(
				path, segment_index, closed, ratio
			)
			var direction := point - previous
			# Coordinates are normalized UVs. A province raster cell can be
			# smaller than 0.001 UV, so only discard true floating-point noise.
			if direction.length_squared() <= 0.000000000001:
				continue
			var normal := Vector2(-direction.y, direction.x).normalized()
			_append_segment(result_segments, previous, point)
			append_metadata.call(normal)
			previous = point


static func _province_chain_side_info(edge: Dictionary) -> Dictionary:
	var from: Vector2 = edge.get("from", Vector2.ZERO)
	var to: Vector2 = edge.get("to", Vector2.ZERO)
	var direction := (to - from).normalized()
	if direction.length_squared() <= 0.000000000001:
		return {
			"left_province": int(edge.get("province_a", -1)),
			"right_province": int(edge.get("province_b", -1)),
		}
	var normal := Vector2(-direction.y, direction.x)
	var side_a: Vector2 = edge.get("side_a", Vector2.ZERO)
	var side_b: Vector2 = edge.get("side_b", Vector2.ZERO)
	if side_a.dot(normal) >= side_b.dot(normal):
		return {
			"left_province": int(edge.get("province_a", -1)),
			"right_province": int(edge.get("province_b", -1)),
		}
	return {
		"left_province": int(edge.get("province_b", -1)),
		"right_province": int(edge.get("province_a", -1)),
	}


static func _coast_chain_side_sign(edge: Dictionary) -> float:
	var from: Vector2 = edge.get("from", Vector2.ZERO)
	var to: Vector2 = edge.get("to", Vector2.ZERO)
	var direction := (to - from).normalized()
	if direction.length_squared() <= 0.000000000001:
		return 1.0
	var normal := Vector2(-direction.y, direction.x)
	var coast_side: Vector2 = edge.get("coast_side", Vector2.ZERO)
	return (
		1.0
		if coast_side.dot(normal) >= 0.0
		else -1.0
	)


## Centripetal Catmull-Rom (alpha=0.5) is stable when RDP leaves unevenly
## spaced controls. Extrapolated endpoint controls preserve open-chain ends.
static func _centripetal_boundary_point(
	path: PackedVector2Array,
	segment_index: int,
	closed: bool,
	ratio: float
) -> Vector2:
	var point_count := path.size()
	if point_count < 2:
		return Vector2.ZERO
	var index_1 := segment_index % point_count
	var index_2 := (segment_index + 1) % point_count
	var point_1 := path[index_1]
	var point_2 := path[index_2]
	var point_0 := (
		path[(index_1 - 1 + point_count) % point_count]
		if closed or index_1 > 0
		else point_1 * 2.0 - point_2
	)
	var point_3 := (
		path[(index_2 + 1) % point_count]
		if closed or index_2 + 1 < point_count
		else point_2 * 2.0 - point_1
	)
	var knot_0 := 0.0
	var knot_1 := knot_0 + sqrt(maxf(point_0.distance_to(point_1), 0.00000001))
	var knot_2 := knot_1 + sqrt(maxf(point_1.distance_to(point_2), 0.00000001))
	var knot_3 := knot_2 + sqrt(maxf(point_2.distance_to(point_3), 0.00000001))
	var parameter := lerpf(knot_1, knot_2, clampf(ratio, 0.0, 1.0))
	var a_1 := point_0.lerp(point_1, (parameter - knot_0) / (knot_1 - knot_0))
	var a_2 := point_1.lerp(point_2, (parameter - knot_1) / (knot_2 - knot_1))
	var a_3 := point_2.lerp(point_3, (parameter - knot_2) / (knot_3 - knot_2))
	var b_1 := a_1.lerp(a_2, (parameter - knot_0) / (knot_2 - knot_0))
	var b_2 := a_2.lerp(a_3, (parameter - knot_1) / (knot_3 - knot_1))
	return b_1.lerp(b_2, (parameter - knot_1) / (knot_2 - knot_1))


## Run a light RDP pass in source raster space so diagonal chains collapse
## before curve generation, but topology breakpoints remain explicit.
static func _simplify_boundary_path(
	source: PackedVector2Array,
	raster_size: Vector2i,
	closed: bool,
	tolerance: float
) -> PackedVector2Array:
	if source.size() < 3:
		return source
	if not closed:
		return _rdp_boundary_path(source, raster_size, tolerance)
	var ring := source
	if ring[0].is_equal_approx(ring[ring.size() - 1]):
		ring = ring.slice(0, ring.size() - 1)
	if ring.size() < 3:
		return ring
	var split_index := 1
	var maximum_distance := -1.0
	var origin := ring[0] * Vector2(raster_size)
	for index in range(1, ring.size()):
		var distance := origin.distance_squared_to(
			ring[index] * Vector2(raster_size)
		)
		if distance > maximum_distance:
			maximum_distance = distance
			split_index = index
	if split_index <= 0 or split_index >= ring.size():
		return ring
	var first_arc := ring.slice(0, split_index + 1)
	var second_arc := ring.slice(split_index, ring.size())
	second_arc.append(ring[0])
	var first_simplified := _rdp_boundary_path(
		first_arc, raster_size, tolerance
	)
	var second_simplified := _rdp_boundary_path(
		second_arc, raster_size, tolerance
	)
	var result := PackedVector2Array()
	result.append_array(first_simplified)
	for index in range(1, second_simplified.size() - 1):
		result.append(second_simplified[index])
	# Never collapse a real closed province/island into a two-point backtrack.
	# Small rings below the RDP tolerance keep their original topology.
	if result.size() < 3 or absf(_boundary_ring_area(result)) <= 0.000000000001:
		return ring
	return result


static func _boundary_ring_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var twice_area := 0.0
	for index in range(points.size()):
		var following := (index + 1) % points.size()
		twice_area += (
			points[index].x * points[following].y
			- points[following].x * points[index].y
		)
	return twice_area * 0.5


static func _rdp_boundary_path(
	source: PackedVector2Array,
	raster_size: Vector2i,
	tolerance: float
) -> PackedVector2Array:
	if source.size() < 3:
		return source
	var keep := PackedByteArray()
	keep.resize(source.size())
	keep[0] = 1
	keep[source.size() - 1] = 1
	var stack: Array = [Vector2i(0, source.size() - 1)]
	while not stack.is_empty():
		var range_pair: Vector2i = stack.pop_back()
		var start := range_pair.x
		var finish := range_pair.y
		var maximum_distance := 0.0
		var maximum_index := -1
		var from := source[start] * Vector2(raster_size)
		var to := source[finish] * Vector2(raster_size)
		for index in range(start + 1, finish):
			var distance := _boundary_point_segment_distance(
				source[index] * Vector2(raster_size),
				from,
				to
			)
			if distance > maximum_distance:
				maximum_distance = distance
				maximum_index = index
		if maximum_index >= 0 and maximum_distance > tolerance:
			keep[maximum_index] = 1
			stack.append(Vector2i(start, maximum_index))
			stack.append(Vector2i(maximum_index, finish))
	var result := PackedVector2Array()
	for index in range(source.size()):
		if keep[index] != 0:
			result.append(source[index])
	return result


static func _boundary_point_segment_distance(
	point: Vector2,
	from: Vector2,
	to: Vector2
) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(from)
	var ratio := clampf(
		(point - from).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return point.distance_to(from + segment * ratio)


static func _province_pair_key(province_a: int, province_b: int) -> String:
	return (
		"%d:%d" % [province_a, province_b]
		if province_a <= province_b
		else "%d:%d" % [province_b, province_a]
	)


static func _incident_edge_sort_key(
	edge: Dictionary,
	vertex_key: String
) -> String:
	var other_key := (
		str(edge.get("to_key", ""))
		if str(edge.get("from_key", "")) == vertex_key
		else str(edge.get("from_key", ""))
	)
	return "%s|%s" % [other_key, _semantic_edge_sort_key(edge)]


static func _semantic_edge_sort_key(edge: Dictionary) -> String:
	var from_key := str(edge.get("from_key", ""))
	var to_key := str(edge.get("to_key", ""))
	return (
		"%s|%s" % [from_key, to_key]
		if from_key <= to_key
		else "%s|%s" % [to_key, from_key]
	)


static func _deterministic_loop_start(edge: Dictionary) -> Dictionary:
	var from_key := str(edge.get("from_key", ""))
	var to_key := str(edge.get("to_key", ""))
	return {
		"start_key": from_key if from_key <= to_key else to_key,
		"edge_id": int(edge.get("id", -1)),
	}


static func _boundary_point_key(point: Vector2) -> String:
	return "%d:%d" % [
		int(round(point.x * 1000000.0)),
		int(round(point.y * 1000000.0)),
	]


func _draw_province_fills() -> void:
	var fill_strength := effective_map_mode_strength(
		_map_mode, _province_strength
	)
	if (
		_political_texture == null
		or _political_base_texture == null
		or _political_ocean_texture == null
		or fill_strength <= 0.0
	):
		return
	# Political modes start from the same neutral white terrain primer. Nation
	# colors and ocean color then share the configured opacity.
	draw_texture_rect(
		_political_base_texture,
		Rect2(_origin, _map_size),
		false,
		Color.WHITE
	)
	draw_texture_rect(
		_political_ocean_texture,
		Rect2(_origin, _map_size),
		false,
		Color(1.0, 1.0, 1.0, fill_strength)
	)
	draw_texture_rect(
		(
			_loyalty_texture
			if (
				_map_mode == MapMode.LOYALTY
				and _diplomatic_view_nation_id < 0
			)
			else _political_texture
		),
		Rect2(_origin, _map_size),
		false,
		Color(1.0, 1.0, 1.0, fill_strength)
	)


func set_province_strength(strength: float) -> void:
	_province_strength = clampf(strength, 0.0, 1.0)
	queue_redraw()


static func effective_map_mode_strength(
	mode: int, configured_strength: float
) -> float:
	var configured := clampf(configured_strength, 0.0, 1.0)
	if mode == MapMode.LOYALTY:
		return maxf(configured, POLITICAL_MAP_DEFAULT_STRENGTH)
	if mode == MapMode.TRADE:
		return maxf(configured, POLITICAL_MAP_DEFAULT_STRENGTH) * 0.58
	return configured


func _draw_province_boundaries() -> void:
	if _classified_boundary_geometry.is_empty():
		return
	var segments: PackedVector2Array = (
		_classified_boundary_geometry.get(
			"province", PackedVector2Array()
		)
	)
	if segments.is_empty():
		return
	var pixels := PackedVector2Array()
	pixels.resize(segments.size())
	for index in range(segments.size()):
		pixels[index] = _origin + segments[index] * _map_size
	draw_multiline(pixels, LOCAL_BOUNDARY_INK, LOCAL_BOUNDARY_WIDTH_PX, false)


func _draw_national_boundaries() -> void:
	if _classified_boundary_geometry.is_empty():
		return
	_draw_owned_boundary_sides_2d(
		_classified_boundary_geometry.get("country", PackedVector2Array()),
		_classified_boundary_geometry.get("country_owner_a", PackedInt32Array()),
		_classified_boundary_geometry.get("country_side_a", PackedVector2Array())
	)
	_draw_owned_boundary_sides_2d(
		_classified_boundary_geometry.get("country", PackedVector2Array()),
		_classified_boundary_geometry.get("country_owner_b", PackedInt32Array()),
		_classified_boundary_geometry.get("country_side_b", PackedVector2Array())
	)
	_draw_owned_boundary_sides_2d(
		_classified_boundary_geometry.get("coast", PackedVector2Array()),
		_classified_boundary_geometry.get("coast_owner", PackedInt32Array()),
		_classified_boundary_geometry.get("coast_side", PackedVector2Array())
	)


func _draw_owned_boundary_sides_2d(
	segments: PackedVector2Array,
	owners: PackedInt32Array,
	side_vectors: PackedVector2Array
) -> void:
	var segment_count := mini(
		segments.size() / 2, mini(owners.size(), side_vectors.size())
	)
	for index in range(segment_count):
		var from := _origin + segments[index * 2] * _map_size
		var to := _origin + segments[index * 2 + 1] * _map_size
		var direction := (to - from).normalized()
		if direction.length_squared() <= 0.000001:
			continue
		var normal := Vector2(-direction.y, direction.x)
		if side_vectors[index].dot(normal) < 0.0:
			normal = -normal
		var offset := normal * (COUNTRY_BOUNDARY_WIDTH_PX * 0.5)
		var color := nation_boundary_color(
			state, owners[index], _diplomatic_view_nation_id
		)
		draw_line(
			from + offset, to + offset,
			color,
			COUNTRY_BOUNDARY_WIDTH_PX, false
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
	alpha: float,
	curve_index: int
) -> void:
	var delta := finish - start
	if delta.length_squared() < 1.0:
		return
	var source_delta := (
		CAMPAIGN_ARROW_SOURCE_TIP - CAMPAIGN_ARROW_SOURCE_TAIL
	)
	var scale := delta.length() / source_delta.length()
	var rotation := delta.angle() - source_delta.angle()
	draw_set_transform(start, rotation, Vector2.ONE * scale)
	draw_texture(
		CAMPAIGN_ARROW_TEXTURE, -CAMPAIGN_ARROW_SOURCE_TAIL,
		Color(1.0, 1.0, 1.0, 0.94 * alpha)
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_edges() -> void:
	var route_alpha := 0.28 if _map_mode == MapMode.TRADE else 1.0
	for e in state.edges:
		var pixel_points := PackedVector2Array()
		for point in e.map_points(
			state.cities[e.city_a].map_position,
			state.cities[e.city_b].map_position
		):
			pixel_points.append(_grid_to_pixel(point))
		var danger := clampf(e.danger, 0.0, 1.0)
		if not is_edge_visible(e):
			continue
		if e.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]:
			var river_color := Color(0.010, 0.105, 0.165, route_alpha)
			river_color = river_color.lerp(
				Color(0.22, 0.018, 0.028),
				danger * 0.45
			)
			draw_polyline(
				pixel_points,
				Color(0.04, 0.075, 0.075, 0.90 * route_alpha),
				7.0 * _display_scale
			)
			draw_polyline(
				pixel_points,
				river_color,
				4.5 * _display_scale
			)
			continue
		if e.kind == Edge.Kind.LANDING:
			for index in range(pixel_points.size() - 1):
				draw_dashed_line(
					pixel_points[index], pixel_points[index + 1],
					Color(0.28, 0.018, 0.010, 0.96 * route_alpha),
					3.0 * _display_scale, 6.0 * _display_scale
				)
			continue
		var road_level := (
			2
			if e.max_manpower >= Edge.TERRAIN_STANDARD_MANPOWER
			else 1
		)
		var col := MAJOR_ROAD_COLOR if road_level >= 2 else MINOR_ROAD_COLOR
		col.a *= route_alpha
		var width := (
			MAJOR_ROAD_WIDTH if road_level >= 2 else MINOR_ROAD_WIDTH
		) * _display_scale
		draw_polyline(pixel_points, col, width, true)
		if danger >= 0.72:
			for index in range(pixel_points.size() - 1):
				_draw_edge_danger_ticks(
					pixel_points[index], pixel_points[index + 1], danger
				)


func _draw_trade_routes() -> void:
	if _map_mode != MapMode.TRADE or state.trade_routes.is_empty():
		return
	var width := 3.2 * _display_scale
	for route in state.trade_routes:
		var status := int(route.get("status", TradeNetwork.ACTIVE))
		var color := trade_route_color(route, true)
		var flow_path := trade_route_flow_path(state, route)
		if flow_path.size() < 2:
			continue
		var pixels := PackedVector2Array()
		for point in flow_path:
			pixels.append(_grid_to_pixel(point))
		if status == TradeNetwork.BLOCKED:
			for index in range(pixels.size() - 1):
				draw_dashed_line(
					pixels[index], pixels[index + 1], color,
					width, 7.0 * _display_scale, true
				)
		else:
			draw_polyline(pixels, color, width, true)
			_draw_trade_flow_markers(
				pixels, color, int(route.get("id", 0))
			)


func _draw_trade_flow_markers(
	pixels: PackedVector2Array,
	color: Color,
	route_id: int
) -> void:
	var total_length := polyline_length(pixels)
	if total_length <= 0.001:
		return
	var spacing := TRADE_FLOW_SPACING_PX * _display_scale
	var phase := fposmod(
		_blink * TRADE_FLOW_SPEED_PX
			+ float(posmod(route_id * 17, 47)),
		spacing
	)
	var distance := phase
	while distance < total_length:
		var sample := polyline_sample(pixels, distance)
		var point: Vector2 = sample["position"]
		var tangent: Vector2 = sample["tangent"]
		var normal := tangent.orthogonal()
		var length := 7.0 * _display_scale
		var half_width := 3.0 * _display_scale
		var tip := point + tangent * length
		var tail := point - tangent * length * 0.55
		draw_colored_polygon(PackedVector2Array([
			tip, tail + normal * half_width, tail - normal * half_width,
		]), color.lightened(0.18))
		distance += spacing


static func has_animated_trade_routes(routes: Array[Dictionary]) -> bool:
	for route in routes:
		if int(route.get("status", TradeNetwork.BLOCKED)) != TradeNetwork.BLOCKED:
			return true
	return false


static func polyline_length(points: PackedVector2Array) -> float:
	var result := 0.0
	for index in range(points.size() - 1):
		result += points[index].distance_to(points[index + 1])
	return result


static func polyline_sample(
	points: PackedVector2Array, distance: float
) -> Dictionary:
	if points.size() < 2:
		return {"position": Vector2.ZERO, "tangent": Vector2.RIGHT}
	var remaining := clampf(distance, 0.0, polyline_length(points))
	for index in range(points.size() - 1):
		var delta := points[index + 1] - points[index]
		var segment_length := delta.length()
		if segment_length <= 0.000001:
			continue
		if remaining <= segment_length:
			return {
				"position": points[index] + delta * (remaining / segment_length),
				"tangent": delta / segment_length,
			}
		remaining -= segment_length
	var tail := points[points.size() - 1] - points[points.size() - 2]
	return {
		"position": points[points.size() - 1],
		"tangent": tail.normalized() if tail.length_squared() > 0.0 else Vector2.RIGHT,
	}


static func trade_route_color(
	route: Dictionary, emphasized: bool = true
) -> Color:
	var status := int(route.get("status", TradeNetwork.ACTIVE))
	var color := TRADE_ACTIVE_GOLD
	if status == TradeNetwork.REROUTED:
		color = TRADE_REROUTED_ORANGE
	elif status == TradeNetwork.BLOCKED:
		color = TRADE_BLOCKED_RED
	elif int(route.get("food_transfer", route.get("food", 0))) > 0:
		color = TRADE_ACTIVE_CYAN
	color.a *= 1.0 if emphasized else 0.52
	return color


static func trade_route_map_paths(
	game_state: GameState, route: Dictionary
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var city_path: Variant = route.get("city_path", [])
	if not (city_path is Array or city_path is PackedInt32Array):
		return result
	for index in range(city_path.size() - 1):
		var from_id := int(city_path[index])
		var to_id := int(city_path[index + 1])
		if (
			from_id < 0 or to_id < 0
			or from_id >= game_state.cities.size()
			or to_id >= game_state.cities.size()
		):
			continue
		var edge := game_state.edge_of(from_id, to_id)
		if edge == null:
			continue
		var points := edge.map_points(
			game_state.cities[edge.city_a].map_position,
			game_state.cities[edge.city_b].map_position
		)
		if from_id == edge.city_a:
			result.append(points)
		else:
			var reversed := PackedVector2Array()
			for point_index in range(points.size() - 1, -1, -1):
				reversed.append(points[point_index])
			result.append(reversed)
	return result


static func trade_route_flow_path(
	game_state: GameState, route: Dictionary
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for edge_path in trade_route_map_paths(game_state, route):
		for point in edge_path:
			if result.is_empty() or not result[-1].is_equal_approx(point):
				result.append(point)
	if result.size() < 2:
		return result
	var food_amount := int(route.get("food_transfer", route.get("food", 0)))
	if food_amount <= 0:
		return result
	var food_source := int(route.get("food_source_city", -1))
	var food_destination := int(route.get("food_destination_city", -1))
	if (
		food_source < 0
		or food_destination < 0
		or food_source >= game_state.cities.size()
		or food_destination >= game_state.cities.size()
	):
		return result
	var source_position := game_state.cities[food_source].map_position
	var destination_position := game_state.cities[food_destination].map_position
	var forward_error := (
		result[0].distance_squared_to(source_position)
		+ result[-1].distance_squared_to(destination_position)
	)
	var reverse_error := (
		result[-1].distance_squared_to(source_position)
		+ result[0].distance_squared_to(destination_position)
	)
	if reverse_error < forward_error:
		result.reverse()
	return result


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
			var points := PackedVector2Array()
			for point in edge.map_points(
				state.cities[edge.city_a].map_position,
				state.cities[edge.city_b].map_position
			):
				points.append(_grid_to_pixel(point))
			draw_polyline(
				points,
				Color(0.04, 0.025, 0.01, 0.95),
				10.0 * _display_scale
			)
			for index in range(points.size() - 1):
				draw_dashed_line(
					points[index], points[index + 1], ACCENT_GOLD,
					4.0 * _display_scale, 8.0 * _display_scale
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
	return MapHitTesting.is_edge_visible(edge)


func _draw_cities() -> void:
	var half := 7.0 * _display_scale
	var contested_cities := _contested_city_ids_cached()
	if _city_label_cache_naming_revision != state.naming_revision:
		_city_label_cache.clear()
		_city_label_cache_naming_revision = state.naming_revision
	for city in state.cities:
		var center := _city_center(city)
		var rect := Rect2(center - Vector2(half, half), Vector2(half * 2, half * 2))
		var base := (
			loyalty_color(city.loyalty)
			if _map_mode == MapMode.LOYALTY
			else final_faction_visual_color(
				state, city.owner_nation,
				0.30 if contested_cities.has(city.id) else 0.0,
				0.06 if city.is_capital else 0.0
			)
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
	var label := WorldNaming.city_display_name(city)
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
		var profile := army_counter_profile(
			army.max_size, army.strategic_role
		)
		var is_main_role := bool(profile["main_role"])
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
		var army_color := final_faction_visual_color(
			state, army.owner_nation,
			0.48 if army.starving and blink_on else 0.0,
			0.04 if army.state == Army.State.FIGHTING else 0.0
		)
		var counter_color := army_color
		_draw_army_counter_body(
			rect,
			counter_color,
			GameState.normalize_nation_color(army_color.darkened(0.10)),
			is_main_role,
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
		var role_code := str(profile["role_code"])
		draw_string(
			_font,
			rect.position + Vector2(2.5, 4.5) * icon_scale,
			role_code,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_army_font_size(8 if is_main_role else 7),
			ACCENT_GOLD if is_main_role else PAPER_LIGHT
		)
		draw_string(
			_font,
			rect.position + Vector2(
				rect.size.x - 10.0 * icon_scale,
				4.5 * icon_scale
			),
			_army_state_code(army.state),
			HORIZONTAL_ALIGNMENT_RIGHT,
			8.0 * icon_scale,
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


static func army_counter_profile(
	max_size: int,
	strategic_role: int = -1
) -> Dictionary:
	# 角色是兵棋轮廓的第一判据：战团里的5000轻军也必须和独立
	# 5000填线军明显不同。省略角色的旧调用仍按重军推断 MAIN。
	var main_role := (
		strategic_role == Army.StrategicRole.MAIN
		or (
			strategic_role < 0
			and max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE
		)
	)
	var heavy := max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE
	if main_role:
		return {
			"icon": FormationIcon.ARMOR if heavy else FormationIcon.INFANTRY,
			"width": 52.0 if heavy else 46.0,
			"height": 28.0,
			"marks": 3 if heavy else 2,
			"main_role": true,
			"role_code": "主",
		}
	return {
		"icon": FormationIcon.INFANTRY,
		"width": 31.0,
		"height": 21.0,
		"marks": 1,
		"main_role": false,
		"role_code": "线",
	}


func _draw_army_counter_body(
	rect: Rect2,
	fill: Color,
	nation_color: Color,
	is_main_role: bool,
	icon_scale: float
) -> void:
	var shadow_offset := Vector2(2.5, 3.0) * icon_scale
	if not is_main_role:
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
	draw_polyline(
		PackedVector2Array(Array(shape) + [shape[0]]),
		ACCENT_GOLD,
		4.2 * icon_scale
	)
	draw_line(
		Vector2(
			rect.position.x + chamfer,
			rect.position.y + 2.5 * icon_scale
		),
		Vector2(
			rect.end.x - chamfer,
			rect.position.y + 2.5 * icon_scale
		),
		ACCENT_GOLD.lerp(nation_color, 0.28),
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
		return _grid_to_pixel(b.edge.map_position_at(
			clampf(b.contact_dist_a / length, 0.0, 1.0),
			_city_grid(state.cities[b.edge.city_a]),
			_city_grid(state.cities[b.edge.city_b]),
			state.map_aspect_ratio
		))
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
		var edge := state.edge_of(army.move_from, army.move_to)
		if edge != null:
			var progress := clampf(army.move_progress, 0.0, 1.0)
			if army.move_from == edge.city_b:
				progress = 1.0 - progress
			return edge.map_position_at(
				progress,
				state.cities[edge.city_a].map_position,
				state.cities[edge.city_b].map_position,
				state.map_aspect_ratio
			)
		return a.lerp(b, clampf(army.move_progress, 0.0, 1.0))
	var cid := army.location_city if army.location_city != -1 else army.move_from
	return _city_grid(state.cities[cid])


func _city_grid(city: City) -> Vector2:
	return city.map_position


func _grid_to_pixel(g: Vector2) -> Vector2:
	return _origin + g * _map_size


static func nation_debug_name(
	game_state: GameState, nation_id: int, short_form: bool = false
) -> String:
	return "%s（国%d）" % [
		WorldNaming.nation_display_name(game_state, nation_id, short_form),
		nation_id,
	]


static func city_debug_name(game_state: GameState, city_id: int) -> String:
	return "%s（城%d）" % [
		WorldNaming.city_display_name(game_state, city_id), city_id,
	]


static func _nation_id_list_text(
	game_state: GameState, nation_ids: Array[int]
) -> String:
	if nation_ids.is_empty():
		return "无"
	var names: Array[String] = []
	for nation_id in nation_ids:
		names.append(WorldNaming.nation_display_name(game_state, nation_id))
	return "、".join(names)


static func ruler_summary(
	nation: Nation,
	game_state: GameState = null
) -> String:
	if nation == null:
		return "无君主"
	var traits: Array[String] = []
	for trait_id in nation.ruler_traits:
		traits.append(RulerProfile.trait_name(trait_id))
	var reign_text := ""
	if game_state != null:
		var reign_years := RulerProfile.reign_years(
			game_state.world_seed,
			nation.id,
			nation.ruler_revision
		)
		var remaining_days := maxi(
			RulerProfile.succession_due_day(
				nation, game_state.world_seed
			) - game_state.day,
			0
		)
		var remaining_years := int(ceil(
			float(remaining_days) / float(RulerProfile.DAYS_PER_YEAR)
		))
		reign_text = "·任期%d年/余%d年" % [reign_years, remaining_years]
	return "%s·%s%s%s" % [
		nation.ruler_name if not nation.ruler_name.is_empty() else "无名君主",
		RulerProfile.archetype_name(nation.ruler_archetype),
		"·%s" % ("/".join(traits) if not traits.is_empty() else "无特质"),
		reign_text,
	]


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
		var relation_text := _nation_relation_text(game_state, nation.id)
		var war_tag := " · 交战" if not wars.is_empty() else ""
		var traits: Array[String] = []
		for trait_id in nation.ruler_traits:
			traits.append(RulerProfile.trait_name(trait_id))
		var trait_text := "、".join(traits) if not traits.is_empty() else "无特质"
		var monthly_food_balance_text := _signed_value_text(
			nation.last_food_estimated_balance
		)
		var food_snapshot_secondary := (
			"粮仓 %d   月产 %d   月需 %d   月净 %s"
			% [
				nation.granary_food,
				nation.last_food_estimated_production,
				nation.last_food_estimated_consumption,
				monthly_food_balance_text,
			]
		)
		row_by_nation[nation.id] = {
			"nation_id": nation.id,
			"color": nation.color,
			"at_war": not wars.is_empty(),
			"identity_primary": nation_debug_name(game_state, nation.id),
			"identity_secondary": relation_text + war_tag,
			"power_primary": "城 %d   军 %d   兵力 %d" % [
				city_count_by_nation[nation.id],
				army_count_by_nation[nation.id],
				troops_by_nation[nation.id],
			],
			"power_secondary": "人力 %d   忠诚 %.0f" % [
				nation.manpower_pool,
				nation.average_loyalty,
			],
			"economy_primary": "国库 %d   月净 %+d" % [
				nation.treasury_gold,
				int(report["monthly_gold_balance"]),
			],
				"economy_secondary": food_snapshot_secondary,
			"governance_primary": "%s · %s" % [
				nation.ruler_name if not nation.ruler_name.is_empty() else "无名君主",
				RulerProfile.archetype_name(nation.ruler_archetype),
			],
			"governance_secondary": "%s · %s" % [
				trait_text, nation_action_summary(game_state, nation.id),
			],
			# 兼容旧调用与脚本检查；实际窗口读取上面的结构化双行字段。
			"identity": "%s  %s" % [nation_debug_name(game_state, nation.id), relation_text],
			"military": "城%d 军%d/%d 人%d 忠%.0f" % [
				city_count_by_nation[nation.id], army_count_by_nation[nation.id],
				troops_by_nation[nation.id], nation.manpower_pool, nation.average_loyalty,
			],
				"economy": "金%d 月%+d 商%d线 金%s %s" % [
					nation.treasury_gold,
					int(report["monthly_gold_balance"]),
					nation.last_trade_route_count,
					_signed_value_text(nation.last_trade_gold),
					food_snapshot_secondary,
				],
			"diplomacy": ruler_summary(nation, game_state),
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
		var overlord_name := WorldNaming.nation_display_name(
			game_state, overlord_id
		)
		return (
			"内战藩王→%s" % overlord_name
			if game_state.is_in_civil_war(nation_id)
			else "藩王→%s" % overlord_name
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
			"备战→%s/%s" % [
				WorldNaming.nation_display_name(
					game_state, nation.war_preparation_target_nation
				),
				WorldNaming.city_display_name(
					game_state, nation.war_preparation_objective_city
				),
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
			"外D%d:%s→%s" % [
				nation.ai_last_diplomatic_day,
				_diplomatic_action_name(
					nation.ai_last_diplomatic_action
				),
				WorldNaming.nation_display_name(
					game_state, nation.ai_last_diplomatic_target
				),
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
		or _nation_list_cache_naming_revision != state.naming_revision
		or _nation_list_cache_trade_revision != state.trade_revision
	):
		_nation_list_cache_day = state.day
		_nation_list_cache_ownership_revision = state.ownership_revision
		_nation_list_cache_diplomacy_revision = state.diplomacy_revision
		_nation_list_cache_naming_revision = state.naming_revision
		_nation_list_cache_trade_revision = state.trade_revision
		_nation_list_cache = nation_list_rows(
			state,
			_nation_stats_collapsed_nations
		)
		_nation_list_alive_count = nation_list_alive_count(state)
	return _nation_list_cache


func _draw_hud() -> void:
	var status := "历史" if _history_mode else ("暂停" if sim.paused else "推演中")
	if state.winner != -1:
		status = (
			"%s 已统一 · %s"
			% [
				WorldNaming.nation_display_name(state, state.winner),
				"暂停" if sim.paused else "继续推演",
			]
		)
	var header_rect := Rect2(
		Vector2(_side_margin - 10.0 * _display_scale, 4.0 * _display_scale),
		Vector2(
			get_viewport_rect().size.x
				- (_side_margin - 10.0 * _display_scale) * 2.0,
			30.0 * _display_scale
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
	draw_rect(header_rect, Color(0.075, 0.095, 0.060, 0.97), true)
	draw_rect(
		Rect2(header_rect.position, Vector2(header_rect.size.x, 2.0 * _display_scale)),
		ACCENT_GOLD, true
	)
	draw_rect(header_rect, ACCENT_GOLD.darkened(0.32), false, 1.2 * _display_scale)
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
	var title_x := _side_margin
	draw_string(
		_font,
		Vector2(title_x, 23.0 * _display_scale),
		"战略司令部",
		HORIZONTAL_ALIGNMENT_LEFT,
		92.0 * _display_scale,
		_font_size(12),
		PAPER_LIGHT
	)
	var chip_x := title_x + 100.0 * _display_scale
	var chip_values := [
		["第 %d 日" % state.day, 66.0, PAPER_LIGHT],
		["第 %d 月" % state.month, 60.0, PAPER_LIGHT],
		[status, 72.0, ACCENT_GOLD if sim.paused else Color(0.48, 0.78, 0.56)],
		[
			"只读政治地图" if _history_mode else "速度 ×%.2f" % sim.speed_multiplier(),
			92.0 if _history_mode else 82.0,
			PAPER_LIGHT,
		],
	]
	for chip in chip_values:
		var chip_width := float(chip[1]) * _display_scale
		if chip_x + chip_width >= army_scale_rect.position.x - 6.0 * _display_scale:
			break
		var chip_rect := Rect2(
			Vector2(chip_x, 8.0 * _display_scale),
			Vector2(chip_width, 21.0 * _display_scale)
		)
		draw_rect(chip_rect, Color(0.03, 0.04, 0.025, 0.62), true)
		draw_rect(
			chip_rect, Color(0.66, 0.54, 0.30, 0.42),
			false, 1.0 * _display_scale
		)
		draw_string(
			_font,
			chip_rect.position + Vector2(6.0, 14.5) * _display_scale,
			str(chip[0]), HORIZONTAL_ALIGNMENT_CENTER,
			chip_rect.size.x - 12.0 * _display_scale,
			_font_size(9), chip[2]
		)
		chip_x += chip_width + 5.0 * _display_scale
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
			"identity_primary": "国家身份",
			"power_primary": "国力与民心",
			"economy_primary": "财政与贸易",
			"governance_primary": "君主与政务",
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
		["identity", 0.02, 0.23],
		["power", 0.25, 0.22],
		["economy", 0.47, 0.25],
		["governance", 0.72, 0.26],
	]
	for column in columns:
		var base_key := str(column[0])
		var primary_key := base_key + "_primary"
		var secondary_key := base_key + "_secondary"
		var x_ratio := float(column[1])
		var width_ratio := float(column[2])
		var text_x := (
			row_rect.position.x
			+ row_rect.size.x * x_ratio
		)
		var text_width := row_rect.size.x * width_ratio
		if base_key == "identity" and row_data.has("depth"):
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
		var primary := str(row_data.get(primary_key, ""))
		var secondary := str(row_data.get(secondary_key, ""))
		# Header dictionaries only carry the primary label.
		if primary.is_empty():
			primary = str(row_data.get(base_key, ""))
		var primary_y := (
			row_rect.position.y + row_rect.size.y * (0.60 if secondary.is_empty() else 0.42)
		)
		draw_string(
			_font,
			Vector2(text_x, primary_y),
			primary,
			HORIZONTAL_ALIGNMENT_LEFT,
			text_width,
			font_size,
			color
		)
		if not secondary.is_empty():
			draw_string(
				_font,
				Vector2(text_x, row_rect.position.y + row_rect.size.y * 0.79),
				secondary, HORIZONTAL_ALIGNMENT_LEFT, text_width,
				maxi(font_size - 1, 8), color.darkened(0.18)
			)


func _draw_selection_detail(detail_payload: Dictionary) -> void:
	var sections := detail_payload.get("sections", []) as Array[Dictionary]
	if sections.is_empty():
		return
	var rect := _selection_detail_rect(int(detail_payload.get("line_count", 0)))
	var title := str(detail_payload.get("title", ""))
	var stripe_color := detail_payload.get(
		"stripe_color",
		COMMAND_GREEN
	) as Color
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
	var visual_line := 0
	for section in sections:
		var section_title := str(section.get("title", ""))
		if not section_title.is_empty():
			var section_y := 43.0 + float(visual_line) * 17.0
			draw_rect(Rect2(
				rect.position + Vector2(10.0, section_y - 11.0) * _display_scale,
				Vector2(rect.size.x / _display_scale - 20.0, 16.0) * _display_scale
			), Color(0.30, 0.23, 0.14, 0.16), true)
			draw_string(
				_font, rect.position + Vector2(14.0, section_y) * _display_scale,
				section_title, HORIZONTAL_ALIGNMENT_LEFT,
				rect.size.x - 28.0 * _display_scale, _font_size(9),
				stripe_color.darkened(0.05)
			)
			visual_line += 1
		for line_value in section.get("lines", []):
			draw_string(
				_font, rect.position + Vector2(18.0, 43.0 + float(visual_line) * 17.0) * _display_scale,
				str(line_value), HORIZONTAL_ALIGNMENT_LEFT,
				rect.size.x - 34.0 * _display_scale, _font_size(10), INK_COLOR
			)
			visual_line += 1


func _selection_detail_line_count() -> int:
	if state == null:
		return 0
	if _selected_city_id >= 0 and _selected_city_id < state.cities.size():
		return _city_detail_line_count()
	if _selected_edge_a >= 0 and _selected_edge_b >= 0:
		var edge := state.edge_of(_selected_edge_a, _selected_edge_b)
		if edge != null:
			return _edge_detail_line_count()
	if _selected_nation_id >= 0 and _selected_nation_id < state.nations.size():
		return _section_visual_line_count(
			_display_nation_detail_sections(_selected_nation_id)
		)
	return 0


func _selection_detail_payload() -> Dictionary:
	var payload := {
		"title": "",
		"stripe_color": COMMAND_GREEN,
		"sections": [] as Array[Dictionary],
		"line_count": 0,
	}
	if state == null:
		return payload
	var sections: Array[Dictionary] = []
	var title := ""
	var stripe_color := COMMAND_GREEN
	if _selected_city_id >= 0 and _selected_city_id < state.cities.size():
		var city := state.cities[_selected_city_id]
		title = "城市信息  %s" % city_debug_name(state, city.id)
		if city.owner_nation >= 0 and city.owner_nation < state.nations.size():
			stripe_color = GameState.normalize_nation_color(
				paper_nation_color(
					state.nations[city.owner_nation].color
				).darkened(0.22)
			)
		sections = city_detail_sections(state, city.id)
	elif _selected_edge_a >= 0 and _selected_edge_b >= 0:
		var edge := state.edge_of(_selected_edge_a, _selected_edge_b)
		if edge != null:
			title = "道路信息  %s ↔ %s" % [
				WorldNaming.city_display_name(state, edge.city_a),
				WorldNaming.city_display_name(state, edge.city_b),
			]
			sections = [{"title": "道路", "lines": edge_detail_lines(state, edge)}]
	elif _selected_nation_id >= 0 and _selected_nation_id < state.nations.size():
		var nation := state.nations[_selected_nation_id]
		title = "国家信息  %s" % nation_debug_name(state, nation.id)
		stripe_color = GameState.normalize_nation_color(
			paper_nation_color(nation.color).darkened(0.22)
		)
		sections = _display_nation_detail_sections(nation.id)
	payload["title"] = title
	payload["stripe_color"] = stripe_color
	payload["sections"] = sections
	payload["line_count"] = _section_visual_line_count(sections)
	return payload


func _display_nation_detail_sections(nation_id: int) -> Array[Dictionary]:
	if not _history_mode:
		return nation_detail_sections(state, nation_id)
	return historical_nation_detail_sections(state, nation_id)


static func historical_nation_detail_sections(
	game_state: GameState,
	nation_id: int
) -> Array[Dictionary]:
	if nation_id < 0 or nation_id >= game_state.nations.size():
		return []
	var relation_lines: Array[String] = [
		"战争：%s" % _nation_id_list_text(
			game_state, game_state.wars_of(nation_id)
		),
		"盟国：%s" % _nation_id_list_text(
			game_state, game_state.allies_of(nation_id)
		),
	]
	var subjects := game_state.subjects_of(nation_id)
	if not subjects.is_empty():
		relation_lines.append(
			"藩属：%s" % _nation_id_list_text(game_state, subjects)
		)
	return [
		{"title": "历史身份", "lines": [
			"第 %d 日    第 %d 月    %s" % [
				game_state.day,
				game_state.month,
				_nation_relation_text(game_state, nation_id),
			],
			"控制城市 %d" % game_state.cities_of(nation_id).size(),
		]},
		{"title": "历史外交", "lines": relation_lines},
	]


static func _section_visual_line_count(sections: Array[Dictionary]) -> int:
	var count := 0
	for section in sections:
		count += 1 + (section.get("lines", []) as Array).size()
	return count


static func _section_layout_line_count(line_counts: PackedInt32Array) -> int:
	var count := line_counts.size()
	for line_count in line_counts:
		count += int(line_count)
	return count


static func _city_detail_line_count() -> int:
	return _section_layout_line_count(PackedInt32Array([3, 2, 3, 3, 1]))


static func _edge_detail_line_count() -> int:
	return _section_layout_line_count(PackedInt32Array([6]))


static func _nation_detail_line_count(
	game_state: GameState,
	nation_id: int
) -> int:
	if nation_id < 0 or nation_id >= game_state.nations.size():
		return 0
	var count := _section_layout_line_count(
		PackedInt32Array([1, 2, 2, 2, 3])
	)
	var nation := game_state.nations[nation_id]
	if (
		not nation.campaign_attack_assignments.is_empty()
		or nation.last_offensive_gold_day >= 0
	):
		count += 1
	return count


func _selection_detail_rect(line_count: int) -> Rect2:
	var viewport_size := get_viewport_rect().size
	var margin := DETAIL_PANEL_MARGIN * _display_scale
	var width := minf(
		DETAIL_PANEL_WIDTH * _display_scale,
		viewport_size.x - margin * 2.0
	)
	var height := (
		43.0 * _display_scale
		+ 17.0 * _display_scale * float(line_count)
	)
	return Rect2(
		Vector2(
			viewport_size.x - width - margin,
			viewport_size.y - height - margin
		),
		Vector2(width, height)
	)


static func city_detail_lines(
	game_state: GameState,
	city_id: int
) -> Array[String]:
	var result: Array[String] = []
	for section in city_detail_sections(game_state, city_id):
		for line_value in section.get("lines", []):
			result.append(str(line_value))
	return result


static func city_detail_sections(
	game_state: GameState,
	city_id: int
) -> Array[Dictionary]:
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
	var target_name := (
		WorldNaming.nation_display_name(
			game_state, city.loyalty_target_nation
		)
		if city.loyalty_target_nation >= 0
		else "无"
	)
	var reason := loyalty_reason_text(city.last_loyalty_reason)
	return [
		{"title": "概况", "lines": [
			"简称：%s" % WorldNaming.city_short_name(game_state, city_id),
			"%s · %s · %s" % [
			type_name,
			"交战中" if contested else "稳定",
				" / ".join(special) if not special.is_empty() else "普通据点",
		],
			"控制：%s    法理：%s" % [
			nation_debug_name(game_state, city.owner_nation),
			nation_debug_name(game_state, legal_owner),
		],
		]},
		{"title": "军事", "lines": [
			"工事：%d / %d    恢复：%d 日" % [
			city.fort_strength,
			city.fort_strength_max,
			recovery_days,
		],
			"驻军：%d 支，共 %d 人" % [
			garrison_count,
			garrison_troops,
		],
		]},
		{"title": "经济", "lines": [
			"人力 %+d/月    金钱 %+d/月    粮食 %+d/半年" % [
			city.manpower_per_month,
			city.gold_per_month,
			city.food_per_half_year,
		],
			"发展：金×%.2f  粮×%.2f  地形×%.2f" % [
			city.development_gold_multiplier,
			city.development_food_multiplier,
			city.terrain_output_multiplier,
		],
			"库存：%d    海拔 %.2f    起伏 %.2f" % [
			city.food_storage,
			city.terrain_height,
			city.terrain_relief,
		],
		]},
		{"title": "治理", "lines": [
			"忠诚 %.1f    趋势 %+0.2f/月    动乱 %.1f" % [
				city.loyalty, city.loyalty_trend, city.unrest,
			],
			"认同：%s    原因：%s" % [
				target_name, reason,
			],
			"叛乱进度：%d / %d 月" % [
				city.rebellion_progress, RebellionSystem.REBELLION_PROGRESS_MONTHS,
			],
		]},
		{"title": "贸易", "lines": [
			"商路：%d    贸易金：%+d/月    粮食净流：%+d/月" % [
				city.trade_route_count, city.trade_gold_bonus, city.trade_food_balance,
			],
		]},
	] as Array[Dictionary]


static func loyalty_reason_text(raw_reason: String) -> String:
	var labels := {
		"foreign_rule": "异国统治",
		"capital": "首都归属",
		"distance": "远离中枢",
		"war_disruption": "战争破坏",
		"unpaid_military": "军饷拖欠",
		"neighbor_unrest": "邻地动乱",
		"ruler": "君主治理",
		"garrison": "驻军维稳",
		"regional_rebellion": "地方叛乱",
		"invalid_city": "无效城市",
	}
	if raw_reason.strip_edges().is_empty():
		return "暂无记录"
	var translated: Array[String] = []
	for reason in raw_reason.split(",", false):
		translated.append(str(labels.get(reason, reason)))
	return "、".join(translated)


static func edge_detail_lines(
	game_state: GameState,
	edge: Edge
) -> Array[String]:
	if edge == null:
		return []
	var city_a := game_state.cities[edge.city_a]
	var city_b := game_state.cities[edge.city_b]
	var route_count := 0
	var blocked_route_count := 0
	for route in game_state.trade_routes:
		var city_path: Variant = route.get("city_path", [])
		for index in range(city_path.size() - 1):
			var from_id := int(city_path[index])
			var to_id := int(city_path[index + 1])
			if (
				mini(from_id, to_id) == edge.city_a
				and maxi(from_id, to_id) == edge.city_b
			):
				route_count += 1
				if int(route.get("status", TradeNetwork.ACTIVE)) == TradeNetwork.BLOCKED:
					blocked_route_count += 1
				break
	return [
		"类型 %s   %s" % [
			_edge_kind_name(edge.kind),
			"允许驻边" if edge.allows_holding else "禁止驻边",
		],
		"端点 %s(%s) ↔ %s(%s)" % [
			city_debug_name(game_state, edge.city_a),
			WorldNaming.nation_display_name(game_state, city_a.owner_nation),
			city_debug_name(game_state, edge.city_b),
			WorldNaming.nation_display_name(game_state, city_b.owner_nation),
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
		"贸易路线 %d   其中阻断 %d" % [
			route_count, blocked_route_count,
		],
	]


static func _edge_kind_name(kind: int) -> String:
	match kind:
		Edge.Kind.LANDING:
			return "抢滩通道"
		Edge.Kind.RIVER:
			return "河运航道"
		Edge.Kind.SEA:
			return "跨海航道"
	return "陆上道路"


static func nation_detail_lines(
	game_state: GameState,
	nation_id: int
) -> Array[String]:
	var result: Array[String] = []
	for section in nation_detail_sections(game_state, nation_id):
		for line_value in section.get("lines", []):
			result.append(str(line_value))
	return result


static func nation_detail_sections(
	game_state: GameState,
	nation_id: int
) -> Array[Dictionary]:
	if nation_id < 0 or nation_id >= game_state.nations.size():
		return []
	_nation_detail_section_build_count += 1
	var n := game_state.nations[nation_id]
	var troops := 0
	var army_count := 0
	for army in game_state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			troops += army.size
			army_count += 1
	var finance := _nation_detail_finance_snapshot(
		game_state,
		nation_id
	)
	var monthly_food_balance_text := _signed_value_text(
		n.last_food_estimated_balance
	)
	var sections: Array[Dictionary] = [
		{"title": "身份与君主", "lines": [
			"%s    %s" % [
				_nation_relation_text(game_state, nation_id), ruler_summary(n, game_state),
			],
		]},
		{"title": "国力与民心", "lines": [
			"城市 %d    军队 %d 支    总兵力 %d" % [
				game_state.cities_of(nation_id).size(), army_count, troops,
			],
			"人力 %d    平均忠诚 %.1f" % [n.manpower_pool, n.average_loyalty],
		]},
		{"title": "财政与军费", "lines": [
			"国库 %d    月净 %+d    城市收入 %d    贡赋 %+d" % [
				n.treasury_gold,
				int(finance["monthly_gold_balance"]),
				int(finance["monthly_city_gold_income"]),
				int(finance["monthly_tribute_balance"]),
			],
			"军费 %d    欠饷 %d    支付率 %.0f%%" % [
				n.last_military_upkeep, n.unpaid_military_upkeep,
				n.military_payment_ratio * 100.0,
			],
		]},
		{"title": "粮食与贸易", "lines": [
			"粮仓 %d    月产(预计) %d    月需(预计) %d    月净(预计) %s" % [
				n.granary_food,
				n.last_food_estimated_production,
				n.last_food_estimated_consumption,
				monthly_food_balance_text,
			],
			"商路 %d    商贸金 %s" % [
				n.last_trade_route_count,
				_signed_value_text(n.last_trade_gold),
			],
		]},
		{"title": "外交与行动", "lines": [
			"战争：%s" % _nation_id_list_text(game_state, game_state.wars_of(nation_id)),
			"盟国：%s" % _nation_id_list_text(game_state, game_state.allies_of(nation_id)),
			nation_action_summary(game_state, nation_id),
		]},
	]
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
			target_labels.append(WorldNaming.city_display_name(
				game_state, int(target_value)
			))
		var omitted_targets := maxi(
			target_ids.size() - target_labels.size(),
			0
		)
		var target_summary := " ".join(target_labels)
		if omitted_targets > 0:
			target_summary += " +%d" % omitted_targets
		(sections[-1]["lines"] as Array).append(
			"计划W%d %d路 费%d  %s" % [
				n.campaign_plan_wave,
				target_ids.size(),
				n.last_offensive_gold_cost,
				target_summary,
			]
		)
	elif n.last_offensive_gold_day >= 0:
		(sections[-1]["lines"] as Array).append(
			"上次攻势 Day%d 组织费%d"
				% [
					n.last_offensive_gold_day,
					n.last_offensive_gold_cost,
				]
		)
	return sections


static func reset_nation_detail_section_build_count() -> void:
	_nation_detail_section_build_count = 0


static func nation_detail_section_build_count() -> int:
	return _nation_detail_section_build_count


static func _nation_detail_finance_snapshot(
	game_state: GameState,
	nation_id: int
) -> Dictionary:
	var city_income := 0
	for city in game_state.cities:
		if city.owner_nation != nation_id:
			continue
		city_income += Simulation.city_gold_output(game_state, city)
	var tribute_received := 0
	var tribute_paid := 0
	for subject_value in game_state.suzerainty:
		var subject_id := int(subject_value)
		var overlord_id := game_state.overlord_of(subject_id)
		if (
			subject_id < 0
			or subject_id >= game_state.nations.size()
			or overlord_id < 0
			or overlord_id >= game_state.nations.size()
		):
			continue
		var subject_city_income := 0
		for city in game_state.cities:
			if city.owner_nation != subject_id:
				continue
			subject_city_income += Simulation.city_gold_output(
				game_state,
				city
			)
		var tribute := int(floor(
			float(subject_city_income)
			* Simulation.effective_tribute_rate(
				game_state,
				subject_id
			)
		))
		if subject_id == nation_id:
			tribute_paid += tribute
		if overlord_id == nation_id:
			tribute_received += tribute
	var tribute_balance := tribute_received - tribute_paid
	var nation := game_state.nations[nation_id]
	return {
		"monthly_city_gold_income": city_income,
		"monthly_tribute_balance": tribute_balance,
		"monthly_gold_balance": (
			city_income
			+ nation.last_trade_gold
			+ tribute_balance
			- nation.last_military_upkeep
		),
	}


static func _signed_value_text(value: int) -> String:
	if value > 0:
		return "+%d" % value
	if value < 0:
		return "%d" % value
	return "0"


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
		DiplomacyAI.Action.RETARGET_WAR_PREPARATION:
			return "调整备战目标"
	return "外交"
