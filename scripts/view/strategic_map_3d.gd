class_name StrategicMap3D
extends Node3D
## 3D 战略地图表现层。Renderer 直接从 Copernicus 高度图生成确定性网格，本节点
## 负责连续地形、国家覆色、道路、河流、城市、军队、战斗和相机交互。

const BASE_WORLD_SPAN: float = 64.0
@export_range(0.5, 4.0, 0.1) var world_span_scale: float = 1.0
## Hybrid terrain contract: political boundaries are smoothed in texture space,
## while a moderately denser mesh preserves the real 0m coast and small islands.
## 512 adds roughly four times the old triangle count for little gain over 384.
const BASE_MESH_RESOLUTION: int = 384
const HEIGHT_STEPS: int = 128
const HEIGHT_SCALE: float = 4.8
const VERTICAL_TERRAIN_LIGHT_MAX_ENERGY: float = 1.50
const VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH: float = 0.62
const SCULPT_TERRAIN_LIGHT_MAX_ENERGY: float = 2.00
const SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH: float = 0.42
const VERTICAL_TERRAIN_LIGHT_COLOR := Color(0.91, 0.94, 1.0)
const SCULPT_TERRAIN_LIGHT_COLOR := Color(1.0, 0.82, 0.62)
const MAP_PICK_CITY_PIXELS: float = 18.0
const MAP_PICK_EDGE_PIXELS: float = 10.0
const CAMERA_MIN_DISTANCE: float = 24.0
const CAMERA_MAX_DISTANCE: float = 92.0
const CAMERA_DRAG_THRESHOLD: float = 4.0
const CAMERA_OVERVIEW_NORMAL_ANGLE_DEGREES: float = 0.0
const CAMERA_MAX_NORMAL_ANGLE_DEGREES: float = 30.0
const MAP_INK := Color(0.075, 0.055, 0.032)
const MAP_IVORY := Color(0.94, 0.87, 0.69)
const MAP_GOLD := Color(0.94, 0.67, 0.20)
const MAP_ALERT := Color(0.84, 0.13, 0.055)
const MAP_SUPPLY := Color(0.20, 0.62, 0.48)
const MAP_COUNTER_MARK := Color(0.32, 0.25, 0.12)
const TRADE_ROUTE_ELEVATION: float = 0.185
const TRADE_ROUTE_WIDTH: float = 0.055
const TRADE_ROUTE_DASH_WORLD_LENGTH: float = 0.42
const TRADE_FLOW_ELEVATION: float = 0.265
const TRADE_FLOW_SPEED: float = 0.95
const TRADE_FLOW_MARKER_SPACING: float = 2.40
const TRADE_FLOW_MARKER_WIDTH: float = 0.26
const TRADE_FLOW_MARKER_LENGTH: float = 0.50
const TRADE_FLOW_MAX_MARKERS_PER_ROUTE: int = 24
const CAMPAIGN_ARROW_TEXTURE := MapRenderer.CAMPAIGN_ARROW_TEXTURE
const CAMPAIGN_ARROW_GRID := Vector2i(12, 8)
## 攻势箭头仍是原始红色贴图；这些参数只控制承载贴图的无光照拱形曲面。
const CAMPAIGN_ARROW_ENDPOINT_CLEARANCE: float = 0.72
const CAMPAIGN_ARROW_SURFACE_CLEARANCE: float = 0.52
const CAMPAIGN_ARROW_MIN_ARCH_HEIGHT: float = 1.60
const CAMPAIGN_ARROW_MAX_ARCH_HEIGHT: float = 4.20
const CAMPAIGN_ARROW_ARCH_LENGTH_RATIO: float = 0.070
const CAMPAIGN_ARROW_TERRAIN_SAMPLES: int = 16
const NATION_LABEL_FONT_SIZE: int = 84
const NATION_LABEL_OUTLINE_SIZE: int = 3
const NATION_LABEL_SAFETY: float = 0.86
const NATION_LABEL_FIT_EPSILON: float = 0.0001
const NATION_LABEL_BASE_PIXEL_SIZE: float = 0.026
const NATION_LABEL_MAX_PIXEL_SIZE: float = 0.080
const ANTIQUE_OVERLAY_SHADER := preload(
	"res://scripts/view/terrain/antique_overlay.gdshader"
)
const WATER_SHADER := preload(
	"res://scripts/view/terrain/strategic_water.gdshader"
)
var state: GameState
var sim: Simulation
var overlay: MapRenderer

var _terrain: StrategicTerrainRenderer
var _camera: Camera3D
var _content: Node3D
var _vertical_terrain_light: DirectionalLight3D
var _sculpt_terrain_light: DirectionalLight3D
var _water: MeshInstance3D
var _roads: MeshInstance3D
var _minor_roads: MeshInstance3D
var _rivers: MeshInstance3D
var _trade_routes: MeshInstance3D
var _trade_flow_markers: MultiMeshInstance3D
var _boundaries: MeshInstance3D
var _campaigns: MeshInstance3D
var _cities: MultiMeshInstance3D
var _city_bases: MultiMeshInstance3D
var _city_resource_markers: MultiMeshInstance3D
var _dock_rings: MultiMeshInstance3D
var _capital_rings: MultiMeshInstance3D
var _armies: MultiMeshInstance3D
var _army_bases: MultiMeshInstance3D
var _army_symbol_a: MultiMeshInstance3D
var _army_symbol_b: MultiMeshInstance3D
var _army_morale_backs: MultiMeshInstance3D
var _army_morale_bars: MultiMeshInstance3D
var _battles: MultiMeshInstance3D
var _battle_rings: MultiMeshInstance3D
var _battle_cross_a: MultiMeshInstance3D
var _battle_cross_b: MultiMeshInstance3D
var _selection: MeshInstance3D
var _edge_selection: MeshInstance3D
var _antique_overlay_layer: CanvasLayer
var _city_labels: Array[Label3D] = []
var _nation_labels: Array[Label3D] = []
var _battle_labels: Array[Label3D] = []
var _province_texture: ImageTexture
var _loyalty_texture: ImageTexture
var _country_boundary_texture: ImageTexture
var _country_color_texture: ImageTexture
var _province_boundary_texture: ImageTexture
var _political_fill_signature := PackedInt64Array()
var _loyalty_fill_signature := PackedInt64Array()
var _boundary_topology := {}
var _province_topology_ids := PackedInt32Array()
var _map_font: Font
## 国家标签的领土几何按 ownership_revision 批量构建一次。名称或外交变化只
## 重算文字尺寸，不再让每个国家各自扫描整张 province map。
var _nation_label_territory_cache := {}
var _nation_label_layout_cache := {}
var _nation_label_cache_ownership_revision: int = -1
var _nation_label_cache_naming_revision: int = -1
var _nation_label_cache_diplomacy_revision: int = -1
var _nation_label_cache_map_size := Vector2i.ZERO
var _nation_label_cache_nation_count: int = -1
var _nation_label_territory_index_builds: int = 0
var _nation_label_territory_index_pixel_visits: int = 0

var _world_size := Vector2(BASE_WORLD_SPAN, BASE_WORLD_SPAN)
var _mesh_resolution := Vector2i(
	BASE_MESH_RESOLUTION,
	BASE_MESH_RESOLUTION
)
var _camera_target := Vector3.ZERO
var _camera_distance: float = 56.0
var _camera_overview_distance: float = 56.0
var _drag_active: bool = false
var _drag_moved: bool = false
var _drag_start := Vector2.ZERO
var _drag_target_start := Vector3.ZERO
var _last_day: int = -1
var _last_ownership_revision: int = -1
var _last_diplomacy_revision: int = -1
var _last_diplomatic_view_nation_id: int = -2
var _last_road_network_revision: int = -1
var _last_trade_revision: int = -1
var _last_army_instances_day: int = -1
var _army_instances_initialized: bool = false
var _army_instance_ids: Array[int] = []
var _army_render_positions: Dictionary = {}
var _army_render_signatures: Dictionary = {}
var _last_army_icon_scale: float = -1.0
var _last_detail_visibility_signature: Array = []
var _last_naming_revision: int = -1
var _map_mode: int = MapRenderer.MapMode.POLITICAL
var _last_selected_edge := Vector2i(-2, -2)
var _province_strength: float = (
	MapRenderer.POLITICAL_MAP_DEFAULT_STRENGTH
)
var _elevation_shadow_strength: float = (
	SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH
)
var _vertical_terrain_light_strength: float = (
	VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH
)
var _visual_time: float = 0.0
var _trade_flow_time: float = 0.0
var _trade_flow_paths: Array[Dictionary] = []
var _trade_flow_path_indices := PackedInt32Array()
var _trade_flow_offsets := PackedFloat32Array()


func setup(
	game_state: GameState,
	simulation: Simulation,
	overlay_renderer: MapRenderer
) -> void:
	state = game_state
	sim = simulation
	overlay = overlay_renderer
	var mesh_resolution_override := int(OS.get_environment(
		"WW_VISUAL_MESH_RESOLUTION"
	))
	if _map_font == null:
		_map_font = MapRenderer.create_map_label_font()
	_ensure_scene_nodes()
	_clear_labels()
	_configure_dimensions()
	if mesh_resolution_override > 0:
		var aspect := clampf(state.map_aspect_ratio, 0.5, 2.5)
		_mesh_resolution = (
			Vector2i(
				mesh_resolution_override,
				maxi(int(round(float(mesh_resolution_override) / aspect)), 72)
			)
			if aspect >= 1.0
			else Vector2i(
				maxi(int(round(float(mesh_resolution_override) * aspect)), 72),
				mesh_resolution_override
			)
		)
	_configure_camera()
	_build_static_scene()
	_start_terrain_generation()
	_last_day = -1
	_last_ownership_revision = -1
	_last_diplomacy_revision = -1
	_last_diplomatic_view_nation_id = -2
	_political_fill_signature = PackedInt64Array()
	_loyalty_fill_signature = PackedInt64Array()
	_boundary_topology = {}
	_province_topology_ids = PackedInt32Array()
	_nation_label_territory_cache.clear()
	_nation_label_layout_cache.clear()
	_nation_label_cache_ownership_revision = -1
	_nation_label_cache_naming_revision = -1
	_nation_label_cache_diplomacy_revision = -1
	_nation_label_cache_map_size = Vector2i.ZERO
	_nation_label_cache_nation_count = -1
	_nation_label_territory_index_builds = 0
	_nation_label_territory_index_pixel_visits = 0
	_last_road_network_revision = -1
	_last_trade_revision = -1
	_last_naming_revision = -1
	_trade_flow_time = 0.0
	_trade_flow_paths.clear()
	_trade_flow_path_indices = PackedInt32Array()
	_trade_flow_offsets = PackedFloat32Array()
	if not sim.runtime_day_committed.is_connected(
		_on_runtime_day_committed
	):
		sim.runtime_day_committed.connect(_on_runtime_day_committed)
	if (
		_trade_flow_markers != null
		and _trade_flow_markers.multimesh != null
	):
		_trade_flow_markers.multimesh.instance_count = 0
	_apply_map_mode_visibility()
	set_process(true)
	set_process_unhandled_input(true)


func _process(delta: float) -> void:
	if state == null or _terrain == null:
		return
	_visual_time += delta
	if _map_mode == MapRenderer.MapMode.TRADE:
		_trade_flow_time += delta
	if (
		state.ownership_revision != _last_ownership_revision
		or state.diplomacy_revision
			!= _last_diplomacy_revision
		or (
			overlay != null
			and overlay.diplomatic_view_nation_id()
				!= _last_diplomatic_view_nation_id
		)
	):
		_update_province_visuals()
		_update_city_instances()
		_army_instances_initialized = false
		_rebuild_nation_labels()
		_last_ownership_revision = state.ownership_revision
		_last_diplomacy_revision = state.diplomacy_revision
		_last_diplomatic_view_nation_id = (
			overlay.diplomatic_view_nation_id() if overlay != null else -1
		)
	if state.naming_revision != _last_naming_revision:
		_rebuild_city_labels()
		_rebuild_nation_labels()
		_last_naming_revision = state.naming_revision
	if state.day != _last_day:
		var daily_render_started := (
			Time.get_ticks_usec()
			if sim != null and sim.runtime_stage_profiling_enabled
			else 0
		)
		if _map_mode == MapRenderer.MapMode.LOYALTY:
			_update_province_visuals()
		_update_campaign_mesh()
		_update_battle_instances()
		if sim != null and sim.runtime_stage_profiling_enabled:
			sim._record_runtime_span(
				&"render_daily_updates", daily_render_started
			)
		_last_day = state.day
	if (
		state.road_network_revision
		!= _last_road_network_revision
		and _terrain.land_cell_count() > 0
	):
		_build_road_mesh()
		_last_road_network_revision = state.road_network_revision
	if (
		state.trade_revision != _last_trade_revision
		and _terrain.land_cell_count() > 0
	):
		_build_trade_route_mesh()
		_last_trade_revision = state.trade_revision
	if (
		_army_instances_initialized
		and not is_equal_approx(
			_last_army_icon_scale, overlay.army_icon_scale()
		)
	):
		_rescale_army_instances(overlay.army_icon_scale())
	if _should_update_army_instances():
		var army_render_started := (
			Time.get_ticks_usec()
			if sim != null and sim.runtime_stage_profiling_enabled
			else 0
		)
		_update_army_instances()
		if sim != null and sim.runtime_stage_profiling_enabled:
			sim._record_runtime_span(
				&"render_army_instances", army_render_started
			)
	elif _army_instances_initialized:
		_update_army_snapshot_positions()
	var overlay_render_started := (
		Time.get_ticks_usec()
		if sim != null and sim.runtime_stage_profiling_enabled
		else 0
	)
	_update_selection_marker()
	_update_edge_selection()
	_update_city_label_visibility()
	if _map_mode == MapRenderer.MapMode.TRADE:
		_update_trade_flow_markers()
	if sim != null and sim.runtime_stage_profiling_enabled:
		sim._record_runtime_span(
			&"render_overlay_updates", overlay_render_started
		)


func _unhandled_input(event: InputEvent) -> void:
	if state == null or _camera == null:
		return
	if event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		if overlay.world_input_blocked(magnify.position):
			return
		_zoom_camera(1.0 / maxf(magnify.factor, 0.05))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		if overlay.world_input_blocked(pan.position):
			return
		_pan_camera(pan.delta * 14.0)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (
			not _drag_active
			and overlay.world_input_blocked(motion.position)
		):
			return
		if (
			not _drag_active
			or (
				motion.button_mask
				& MOUSE_BUTTON_MASK_LEFT
			) == 0
		):
			return
		if (
			not _drag_moved
			and motion.position.distance_to(_drag_start)
				>= CAMERA_DRAG_THRESHOLD
		):
			_drag_moved = true
		if _drag_moved:
			var scale := (
				_camera_distance
				/ maxf(get_viewport().get_visible_rect().size.y, 1.0)
			)
			var delta := motion.position - _drag_start
			_camera_target = _drag_target_start + Vector3(
				-delta.x * scale * 1.35,
				0.0,
				-delta.y * scale * 1.35
			)
			_clamp_camera_target()
			_apply_camera_transform()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if overlay.world_input_blocked(mouse.position):
		return
	if (
		mouse.pressed
		and mouse.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN,
		]
	):
		_zoom_camera(
			0.88
			if mouse.button_index == MOUSE_BUTTON_WHEEL_UP
			else 1.0 / 0.88
		)
		get_viewport().set_input_as_handled()
		return
	if (
		mouse.pressed
		and mouse.button_index == MOUSE_BUTTON_RIGHT
	):
		overlay.clear_map_selection()
		get_viewport().set_input_as_handled()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_drag_active = true
		_drag_moved = false
		_drag_start = mouse.position
		_drag_target_start = _camera_target
		return
	if not _drag_active:
		return
	_drag_active = false
	if _drag_moved:
		_drag_moved = false
		get_viewport().set_input_as_handled()
		return
	_pick_map_feature(mouse.position)
	get_viewport().set_input_as_handled()


func _ensure_scene_nodes() -> void:
	if _content == null:
		_content = Node3D.new()
		_content.name = "WorldContent"
		add_child(_content)
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "StrategicCamera"
		_camera.fov = 34.0
		_camera.near = 0.2
		_camera.far = 300.0
		add_child(_camera)
	_ensure_terrain_lights()
	if get_node_or_null("Environment") == null:
		var world_environment := WorldEnvironment.new()
		world_environment.name = "Environment"
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.55, 0.49, 0.38)
		environment.background_energy_multiplier = 0.82
		environment.ambient_light_source = (
			Environment.AMBIENT_SOURCE_COLOR
		)
		environment.ambient_light_color = Color(0.52, 0.56, 0.64)
		# The vertical plane light is the readable base illumination. Keep only
		# a small world ambient term so the horizontal sculpt light retains form.
		environment.ambient_light_energy = 0.16
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		world_environment.environment = environment
		add_child(world_environment)
	_ensure_feature_nodes()
	_ensure_antique_overlay()


func _ensure_terrain_lights() -> void:
	if _vertical_terrain_light == null:
		_vertical_terrain_light = DirectionalLight3D.new()
		_vertical_terrain_light.name = "TerrainVerticalPlaneLight"
		# DirectionalLight3D emits along local -Z. X=-90° points straight down.
		_vertical_terrain_light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_vertical_terrain_light.light_color = VERTICAL_TERRAIN_LIGHT_COLOR
		_vertical_terrain_light.light_cull_mask = (
			StrategicTerrainRenderer.TERRAIN_VISUAL_LAYER
		)
		_vertical_terrain_light.shadow_enabled = false
		add_child(_vertical_terrain_light)
	if _sculpt_terrain_light == null:
		_sculpt_terrain_light = DirectionalLight3D.new()
		_sculpt_terrain_light.name = "TerrainNorthwestSculptPlaneLight"
		# Map top-left is world (-X,-Z); horizontal emission toward (+X,+Z)
		# is local -Z rotated -135° around Y. It lights slopes, not flat ground.
		_sculpt_terrain_light.rotation_degrees = Vector3(0.0, -135.0, 0.0)
		_sculpt_terrain_light.light_color = SCULPT_TERRAIN_LIGHT_COLOR
		_sculpt_terrain_light.light_cull_mask = (
			StrategicTerrainRenderer.TERRAIN_VISUAL_LAYER
		)
		_sculpt_terrain_light.shadow_enabled = false
		add_child(_sculpt_terrain_light)
	_apply_vertical_terrain_light_strength()
	_apply_terrain_sculpt_light_strength()


func _apply_vertical_terrain_light_strength() -> void:
	if _vertical_terrain_light != null:
		_vertical_terrain_light.light_energy = (
			_vertical_terrain_light_strength
			* VERTICAL_TERRAIN_LIGHT_MAX_ENERGY
		)


func _apply_terrain_sculpt_light_strength() -> void:
	if _sculpt_terrain_light != null:
		_sculpt_terrain_light.light_energy = (
			_elevation_shadow_strength
			* SCULPT_TERRAIN_LIGHT_MAX_ENERGY
		)


func _ensure_antique_overlay() -> void:
	if _antique_overlay_layer != null:
		return
	_antique_overlay_layer = CanvasLayer.new()
	_antique_overlay_layer.name = "AntiqueOverlay"
	_antique_overlay_layer.layer = -1
	var overlay_rect := ColorRect.new()
	overlay_rect.name = "PaperTintAndVignette"
	overlay_rect.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_rect.color = Color.WHITE
	var material := ShaderMaterial.new()
	material.shader = ANTIQUE_OVERLAY_SHADER
	overlay_rect.material = material
	_antique_overlay_layer.add_child(overlay_rect)
	add_child(_antique_overlay_layer)


func _ensure_feature_nodes() -> void:
	if _water == null:
		_water = MeshInstance3D.new()
		_water.name = "Water"
		_content.add_child(_water)
	if _roads == null:
		_roads = MeshInstance3D.new()
		_roads.name = "MajorRoads"
		_content.add_child(_roads)
	if _minor_roads == null:
		_minor_roads = MeshInstance3D.new()
		_minor_roads.name = "MinorRoads"
		_content.add_child(_minor_roads)
	if _rivers == null:
		_rivers = MeshInstance3D.new()
		_rivers.name = "Rivers"
		_content.add_child(_rivers)
	if _trade_routes == null:
		_trade_routes = MeshInstance3D.new()
		_trade_routes.name = "TradeRoutes"
		_content.add_child(_trade_routes)
	if _trade_flow_markers == null:
		_trade_flow_markers = MultiMeshInstance3D.new()
		_trade_flow_markers.name = "TradeFlowMarkers"
		_content.add_child(_trade_flow_markers)
	if _boundaries == null:
		_boundaries = MeshInstance3D.new()
		_boundaries.name = "Boundaries"
		_content.add_child(_boundaries)
	if _campaigns == null:
		_campaigns = MeshInstance3D.new()
		_campaigns.name = "Campaigns"
		_content.add_child(_campaigns)
	if _cities == null:
		_cities = MultiMeshInstance3D.new()
		_cities.name = "Cities"
		_content.add_child(_cities)
	if _city_bases == null:
		_city_bases = MultiMeshInstance3D.new()
		_city_bases.name = "CityBases"
		_content.add_child(_city_bases)
	if _city_resource_markers == null:
		_city_resource_markers = MultiMeshInstance3D.new()
		_city_resource_markers.name = "CityResourceMarkers"
		_content.add_child(_city_resource_markers)
	if _dock_rings == null:
		_dock_rings = MultiMeshInstance3D.new()
		_dock_rings.name = "DockRings"
		_content.add_child(_dock_rings)
	if _capital_rings == null:
		_capital_rings = MultiMeshInstance3D.new()
		_capital_rings.name = "CapitalRings"
		_content.add_child(_capital_rings)
	if _armies == null:
		_armies = MultiMeshInstance3D.new()
		_armies.name = "Armies"
		_content.add_child(_armies)
	if _army_bases == null:
		_army_bases = MultiMeshInstance3D.new()
		_army_bases.name = "ArmyCounterBases"
		_content.add_child(_army_bases)
	if _army_symbol_a == null:
		_army_symbol_a = MultiMeshInstance3D.new()
		_army_symbol_a.name = "ArmySymbolsA"
		_content.add_child(_army_symbol_a)
	if _army_symbol_b == null:
		_army_symbol_b = MultiMeshInstance3D.new()
		_army_symbol_b.name = "ArmySymbolsB"
		_content.add_child(_army_symbol_b)
	if _army_morale_backs == null:
		_army_morale_backs = MultiMeshInstance3D.new()
		_army_morale_backs.name = "ArmyMoraleBacks"
		_content.add_child(_army_morale_backs)
	if _army_morale_bars == null:
		_army_morale_bars = MultiMeshInstance3D.new()
		_army_morale_bars.name = "ArmyMoraleBars"
		_content.add_child(_army_morale_bars)
	if _battles == null:
		_battles = MultiMeshInstance3D.new()
		_battles.name = "Battles"
		_content.add_child(_battles)
	if _battle_rings == null:
		_battle_rings = MultiMeshInstance3D.new()
		_battle_rings.name = "BattleRings"
		_content.add_child(_battle_rings)
	if _battle_cross_a == null:
		_battle_cross_a = MultiMeshInstance3D.new()
		_battle_cross_a.name = "BattleCrossA"
		_content.add_child(_battle_cross_a)
	if _battle_cross_b == null:
		_battle_cross_b = MultiMeshInstance3D.new()
		_battle_cross_b.name = "BattleCrossB"
		_content.add_child(_battle_cross_b)
	if _selection == null:
		_selection = MeshInstance3D.new()
		_selection.name = "Selection"
		var ring := TorusMesh.new()
		ring.inner_radius = 0.58
		ring.outer_radius = 0.76
		ring.rings = 20
		ring.ring_segments = 8
		_selection.mesh = ring
		var material := StandardMaterial3D.new()
		material.albedo_color = MAP_GOLD
		material.emission_enabled = true
		material.emission = Color(0.76, 0.24, 0.035)
		material.emission_energy_multiplier = 2.0
		_selection.material_override = material
		_selection.visible = false
		_content.add_child(_selection)
	if _edge_selection == null:
		_edge_selection = MeshInstance3D.new()
		_edge_selection.name = "EdgeSelection"
		_edge_selection.material_override = _line_material(true)
		_content.add_child(_edge_selection)


func _configure_dimensions() -> void:
	var aspect := clampf(state.map_aspect_ratio, 0.5, 2.5)
	var world_span := BASE_WORLD_SPAN * maxf(world_span_scale, 0.5)
	if aspect >= 1.0:
		_world_size = Vector2(
			world_span,
			world_span / aspect
		)
		_mesh_resolution = Vector2i(
			BASE_MESH_RESOLUTION,
			maxi(
				int(round(
					float(BASE_MESH_RESOLUTION) / aspect
				)),
				72
			)
		)
	else:
		_world_size = Vector2(
			world_span * aspect,
			world_span
		)
		_mesh_resolution = Vector2i(
			maxi(
				int(round(
					float(BASE_MESH_RESOLUTION) * aspect
				)),
				72
			),
			BASE_MESH_RESOLUTION
		)


func _configure_camera() -> void:
	_camera_target = Vector3.ZERO
	_camera_distance = clampf(
		_overview_distance_for_viewport(),
		CAMERA_MIN_DISTANCE,
		_camera_max_distance()
	)
	_camera_overview_distance = _camera_distance
	_apply_camera_transform()


func _overview_distance_for_viewport() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	var viewport_aspect := (
		viewport_size.x / maxf(viewport_size.y, 1.0)
	)
	var half_vertical_fov := deg_to_rad(_camera.fov * 0.5)
	var vertical_tangent := maxf(tan(half_vertical_fov), 0.01)
	var vertical_distance := (
		_world_size.y * 0.5 / vertical_tangent
	)
	var horizontal_distance := (
		_world_size.x * 0.5
		/ (vertical_tangent * viewport_aspect)
	)
	# Start as a true orthogonal-looking top-down view; zooming in gradually
	# introduces perspective pitch. Reserve space for HUD and map controls.
	return maxf(vertical_distance, horizontal_distance) * 1.16


func _apply_camera_transform() -> void:
	var focus := _camera_target + Vector3(
		0.0,
		HEIGHT_SCALE * 0.18,
		0.0
	)
	var angle := deg_to_rad(_camera_normal_angle_degrees())
	_camera.position = focus + Vector3(
		0.0,
		_camera_distance * cos(angle),
		_camera_distance * sin(angle)
	)
	_camera.look_at(focus, Vector3(0.0, 0.0, -1.0))
	_update_boundary_lod()


func _update_boundary_lod() -> void:
	if _terrain == null:
		return
	# Political borders are cartographic information, not detail decoration.
	# Keep every layer fully visible at every supported camera distance.
	var lod := boundary_lod_strengths(_camera_distance)
	var province_alpha := float(lod["province"])
	var country_alpha := float(lod["country"])
	_terrain.set_boundary_lod(province_alpha, 1.0, country_alpha)


static func boundary_lod_strengths(camera_distance: float) -> Dictionary:
	# Keep the argument for the public/tested API even though the new style has
	# no zoom-dependent disappearance.
	var _unused_distance := camera_distance
	return {
		"province": 1.0,
		"coast": 1.0,
		"country": 1.0,
	}


func _camera_normal_angle_degrees() -> float:
	var zoom_progress := clampf(
		inverse_lerp(
			_camera_overview_distance,
			CAMERA_MIN_DISTANCE,
			_camera_distance
		),
		0.0,
		1.0
	)
	return lerpf(
		CAMERA_OVERVIEW_NORMAL_ANGLE_DEGREES,
		CAMERA_MAX_NORMAL_ANGLE_DEGREES,
		zoom_progress
	)


func _zoom_camera(factor: float) -> void:
	_camera_distance = clampf(
		_camera_distance * factor,
		CAMERA_MIN_DISTANCE,
		_camera_max_distance()
	)
	_apply_camera_transform()


func _camera_max_distance() -> float:
	return CAMERA_MAX_DISTANCE * maxf(world_span_scale, 1.0)


func _pan_camera(screen_delta: Vector2) -> void:
	var scale := _camera_distance / 720.0
	_camera_target += Vector3(
		-screen_delta.x * scale,
		0.0,
		-screen_delta.y * scale
	)
	_clamp_camera_target()
	_apply_camera_transform()


func _clamp_camera_target() -> void:
	_camera_target.x = clampf(
		_camera_target.x,
		-_world_size.x * 0.42,
		_world_size.x * 0.42
	)
	_camera_target.z = clampf(
		_camera_target.z,
		-_world_size.y * 0.42,
		_world_size.y * 0.42
	)


func _build_static_scene() -> void:
	var water_plane := PlaneMesh.new()
	water_plane.size = _world_size
	_water.mesh = water_plane
	_water.position.y = StrategicTerrainRenderer.WATER_SURFACE_HEIGHT
	# Water color and texture now come directly from the complete Natural Earth
	# surface image on the terrain mesh. Keep the old plane disabled so it can
	# never cover the source imagery with a procedural color layer.
	_water.visible = false


func _start_terrain_generation() -> void:
	if _terrain != null:
		_terrain.queue_free()
		_terrain = null

	_terrain = StrategicTerrainRenderer.new()
	_terrain.name = "StrategicTerrainRenderer"
	add_child(_terrain)
	_terrain.configure(
		_mesh_resolution,
		_world_size,
		HEIGHT_SCALE,
		HEIGHT_STEPS
	)
	var height_texture := load(
		GameState.terrain_map_path()
	) as Texture2D
	_terrain.set_height_texture(
		height_texture,
		state.map_source_region_normalized
	)
	# Packed map source: RGB=satellite color, Alpha=elevation. The same texture
	# drives rendering, terrain height and city/road/province generation.
	_terrain.set_surface_texture(height_texture)
	_terrain.generation_finished.connect(_on_terrain_ready)
	_terrain.call_deferred(
		"generate_from_height_texture",
		height_texture,
		state.map_source_region_normalized,
		TerrainMapGenerator.ALPHA_THRESHOLD,
		TerrainMapGenerator.LUMA_THRESHOLD
	)


func _on_terrain_ready() -> void:
	if _terrain.land_cell_count() <= 0:
		push_error("Copernicus 3D 地形为空")
		return
	_update_province_visuals()
	_terrain.set_province_strength(MapRenderer.effective_map_mode_strength(
		_map_mode, _province_strength
	))
	_build_road_mesh()
	_build_trade_route_mesh()
	_build_river_mesh()
	_build_city_instances()
	_update_city_instances()
	_update_army_instances()
	_update_battle_instances()
	_update_campaign_mesh()
	_rebuild_nation_labels()
	_last_ownership_revision = state.ownership_revision
	_last_diplomacy_revision = state.diplomacy_revision
	_last_diplomatic_view_nation_id = (
		overlay.diplomatic_view_nation_id() if overlay != null else -1
	)
	_last_road_network_revision = state.road_network_revision
	_last_trade_revision = state.trade_revision
	_last_naming_revision = state.naming_revision


func set_province_strength(strength: float) -> void:
	_province_strength = clampf(strength, 0.0, 1.0)
	if _terrain != null:
		_terrain.set_province_strength(MapRenderer.effective_map_mode_strength(
			_map_mode, _province_strength
		))


func set_map_mode(mode: int) -> void:
	var normalized := clampi(
		mode, MapRenderer.MapMode.POLITICAL, MapRenderer.MapMode.TRADE
	)
	if normalized == _map_mode:
		return
	_map_mode = normalized
	# The active fill signature belongs to the previous mode. Resetting it
	# forces a political <-> loyalty texture swap even when numeric values happen
	# to produce an equally sized signature.
	_political_fill_signature = PackedInt64Array()
	if overlay != null and overlay.map_mode() != normalized:
		overlay.set_map_mode(normalized)
	_update_province_visuals()
	_update_city_instances()
	_build_trade_route_mesh()
	_apply_map_mode_visibility()


func map_mode() -> int:
	return _map_mode


func set_elevation_shadow_strength(strength: float) -> void:
	_elevation_shadow_strength = clampf(strength, 0.0, 1.0)
	_apply_terrain_sculpt_light_strength()


func set_vertical_terrain_light_strength(strength: float) -> void:
	_vertical_terrain_light_strength = clampf(strength, 0.0, 1.0)
	_apply_vertical_terrain_light_strength()


func _update_province_visuals() -> void:
	if _terrain == null or _terrain.land_cell_count() <= 0:
		return
	var topology_changed := (
		_boundary_topology.is_empty()
		or _province_topology_ids != state.province_ids
	)
	if topology_changed:
		_boundary_topology = MapRenderer.build_province_boundary_topology(state)
		_province_topology_ids = state.province_ids.duplicate()
		# 省份栅格几何变化会改变标签连通域，即使所有权 revision 未变。
		_nation_label_cache_ownership_revision = -1
	var geometry := MapRenderer.classify_province_boundary_topology(
		state, _boundary_topology
	)
	# Most diplomacy revisions only reclassify country edges, but suzerainty and
	# civil-war changes can also alter province colors. A semantic signature lets
	# ordinary relations keep the existing GPU fill; a topology change always
	# rebuilds it because the same city colors now occupy different pixels.
	var view_nation_id := (
		overlay.diplomatic_view_nation_id() if overlay != null else -1
	)
	var political_signature := MapRenderer.political_fill_signature(
		state, view_nation_id
	)
	var loyalty_signature := (
		MapRenderer.loyalty_fill_signature(state)
		if (
			_map_mode == MapRenderer.MapMode.LOYALTY
			and view_nation_id < 0
		)
		else PackedInt64Array()
	)
	var fill_signature := (
		loyalty_signature
		if (
			_map_mode == MapRenderer.MapMode.LOYALTY
			and view_nation_id < 0
		)
		else political_signature
	)
	var rebuild_fill := (
		topology_changed
		or _province_texture == null
		or fill_signature != _political_fill_signature
	)
	if rebuild_fill:
		var fill_source := (
			MapRenderer.build_loyalty_overlay_image(state)
			if (
				_map_mode == MapRenderer.MapMode.LOYALTY
				and view_nation_id < 0
			)
			else MapRenderer.build_province_overlay_image(
				state, view_nation_id
			)
		)
		var canvas := MapRenderer.build_political_canvas_images(
			state, geometry, false, fill_source
		)
		var image: Image = canvas["terrain_fill"]
		if image != null and not image.is_empty():
			_province_texture = ImageTexture.create_from_image(image)
			if (
				_map_mode == MapRenderer.MapMode.LOYALTY
				and view_nation_id < 0
			):
				_loyalty_texture = _province_texture
			_terrain.set_province_texture(_province_texture)
			_political_fill_signature = fill_signature
			_loyalty_fill_signature = loyalty_signature
	var output_size := (
		state.province_map_size * MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE
	)
	var province_boundary_image: Image = null
	if topology_changed or _province_boundary_texture == null:
		province_boundary_image = MapRenderer._rasterize_soft_boundary_layer(
			geometry["province"], output_size, MapRenderer.LOCAL_BOUNDARY_INK,
			MapRenderer.LOCAL_BOUNDARY_WIDTH_PX,
			MapRenderer.BOUNDARY_ANTIALIAS_PX
		)
		province_boundary_image.generate_mipmaps()
		_province_boundary_texture = ImageTexture.create_from_image(
			province_boundary_image
		)
	if topology_changed or rebuild_fill or _country_boundary_texture == null:
		var country_boundary_image := MapRenderer.build_country_boundary_image(
			state, geometry, true, view_nation_id
		)
		_country_boundary_texture = ImageTexture.create_from_image(
			country_boundary_image
		)
		var country_color_image := MapRenderer.build_country_color_image(
			state, true, view_nation_id
		)
		_country_color_texture = ImageTexture.create_from_image(
			country_color_image
		)
	_terrain.set_boundary_textures(
		_province_boundary_texture, _country_boundary_texture,
		_country_color_texture
	)
	_update_boundary_lod()
	_terrain.set_province_strength(MapRenderer.effective_map_mode_strength(
		_map_mode, _province_strength
	))
	# Political fill and political boundaries now share one terrain material
	# canvas. Keep the legacy MeshInstance empty to prevent a second geometry
	# from drifting away from the painted regions.
	_boundaries.mesh = null
	_boundaries.material_override = null


func _build_road_mesh() -> void:
	var major_tool := SurfaceTool.new()
	major_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var minor_tool := SurfaceTool.new()
	minor_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in state.edges:
		if not MapRenderer.is_edge_visible(edge):
			continue
		var path := edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		)
		var color := _road_color_for_capacity(edge.max_manpower)
		var width := _road_width_for_capacity(edge.max_manpower)
		if edge.kind == Edge.Kind.LANDING:
			color = Color(0.25, 0.075, 0.020, 0.92)
			width = 0.080
		elif edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]:
			color = Color(0.012, 0.105, 0.165, 0.94)
			width = 0.090
		var surface_tool := (
			major_tool
			if edge.max_manpower >= Edge.TERRAIN_STANDARD_MANPOWER
			else minor_tool
		)
		_append_draped_path_ribbon(
			surface_tool,
			path,
			width * 1.58,
			Color(0.055, 0.038, 0.022, 0.54),
			0.105
		)
		_append_draped_path_ribbon(
			surface_tool,
			path,
			width,
			color,
			0.125
		)
	_roads.mesh = major_tool.commit()
	_roads.material_override = _line_material(false)
	_minor_roads.mesh = minor_tool.commit()
	_minor_roads.material_override = _line_material(false)
	_update_map_detail_visibility()


func _build_trade_route_mesh() -> void:
	if _trade_routes == null or _terrain == null:
		return
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emphasized := _map_mode == MapRenderer.MapMode.TRADE
	for route in state.trade_routes:
		var status := int(route.get("status", TradeNetwork.ACTIVE))
		var color := MapRenderer.trade_route_color(route, emphasized)
		var width := TRADE_ROUTE_WIDTH * (1.28 if emphasized else 1.0)
		for map_path in MapRenderer.trade_route_map_paths(state, route):
			if status == TradeNetwork.BLOCKED:
				_append_dashed_draped_path(
					surface_tool, map_path, width, color,
					TRADE_ROUTE_ELEVATION
				)
			else:
				_append_draped_path_ribbon(
					surface_tool, map_path, width, color,
					TRADE_ROUTE_ELEVATION
				)
	_trade_routes.mesh = surface_tool.commit()
	_trade_routes.material_override = _trade_route_material()
	_rebuild_trade_flow_markers()
	_apply_map_mode_visibility()


func _rebuild_trade_flow_markers() -> void:
	_trade_flow_paths.clear()
	var path_indices: Array[int] = []
	var offsets: Array[float] = []
	if _trade_flow_markers == null or _terrain == null or state == null:
		return
	for route in state.trade_routes:
		if int(route.get("status", TradeNetwork.ACTIVE)) == TradeNetwork.BLOCKED:
			continue
		var route_points := PackedVector3Array()
		var flow_path := MapRenderer.trade_route_flow_path(state, route)
		for segment_index in range(flow_path.size() - 1):
			var samples := _draped_world_samples(
				flow_path[segment_index],
				flow_path[segment_index + 1],
				TRADE_FLOW_ELEVATION
			)
			for sample_index in range(samples.size()):
				var sample := samples[sample_index]
				if (
					not route_points.is_empty()
					and route_points[route_points.size() - 1]
						.distance_squared_to(sample) <= 0.000001
				):
					continue
				route_points.append(sample)
		if route_points.size() < 2:
			continue
		var cumulative := PackedFloat32Array()
		cumulative.resize(route_points.size())
		var path_length := 0.0
		for point_index in range(1, route_points.size()):
			path_length += route_points[point_index - 1].distance_to(
				route_points[point_index]
			)
			cumulative[point_index] = path_length
		if path_length <= 0.001:
			continue
		var path_index := _trade_flow_paths.size()
		_trade_flow_paths.append({
			"points": route_points,
			"cumulative": cumulative,
			"length": path_length,
			"color": MapRenderer.trade_route_color(route, true),
		})
		var marker_count := clampi(
			int(ceil(path_length / TRADE_FLOW_MARKER_SPACING)),
			1,
			TRADE_FLOW_MAX_MARKERS_PER_ROUTE
		)
		for marker_index in range(marker_count):
			path_indices.append(path_index)
			offsets.append(
				float(marker_index) / float(marker_count) * path_length
			)
	_trade_flow_path_indices = PackedInt32Array(path_indices)
	_trade_flow_offsets = PackedFloat32Array(offsets)
	_configure_multimesh(
		_trade_flow_markers,
		_trade_flow_marker_mesh(),
		_trade_flow_path_indices.size(),
		_trade_flow_material()
	)
	_update_trade_flow_markers()


func _trade_flow_marker_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A long diamond has a readable tip in local +Z, which is aligned to the
	# route tangent by each instance transform.
	for vertex in [
		Vector3(0.0, 0.0, 0.50),
		Vector3(0.50, 0.0, -0.16),
		Vector3(0.0, 0.0, -0.50),
		Vector3(0.0, 0.0, 0.50),
		Vector3(0.0, 0.0, -0.50),
		Vector3(-0.50, 0.0, -0.16),
	]:
		surface_tool.add_vertex(vertex)
	return surface_tool.commit()


func _trade_flow_material() -> StandardMaterial3D:
	var material := _instance_color_material(false, true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.render_priority = 6
	return material


func _update_trade_flow_markers() -> void:
	if (
		_map_mode != MapRenderer.MapMode.TRADE
		or _trade_flow_markers == null
		or _trade_flow_markers.multimesh == null
	):
		return
	for instance_index in range(_trade_flow_path_indices.size()):
		var path_index := _trade_flow_path_indices[instance_index]
		if path_index < 0 or path_index >= _trade_flow_paths.size():
			continue
		var path: Dictionary = _trade_flow_paths[path_index]
		var length := float(path.get("length", 0.0))
		if length <= 0.001:
			continue
		var distance := fposmod(
			_trade_flow_offsets[instance_index]
				+ _trade_flow_time * TRADE_FLOW_SPEED,
			length
		)
		var pose := _trade_flow_pose_at_distance(path, distance)
		if pose.is_empty():
			continue
		_trade_flow_markers.multimesh.set_instance_transform(
			instance_index, pose["transform"]
		)
		_trade_flow_markers.multimesh.set_instance_color(
			instance_index, path["color"]
		)


func _trade_flow_pose_at_distance(
	path: Dictionary, distance: float
) -> Dictionary:
	var points: PackedVector3Array = path.get(
		"points", PackedVector3Array()
	)
	var cumulative: PackedFloat32Array = path.get(
		"cumulative", PackedFloat32Array()
	)
	if points.size() < 2 or cumulative.size() != points.size():
		return {}
	var segment_index := 0
	while (
		segment_index + 1 < cumulative.size()
		and cumulative[segment_index + 1] < distance
	):
		segment_index += 1
	segment_index = mini(segment_index, points.size() - 2)
	var from := points[segment_index]
	var to := points[segment_index + 1]
	var segment_length := maxf(
		cumulative[segment_index + 1] - cumulative[segment_index],
		0.000001
	)
	var ratio := clampf(
		(distance - cumulative[segment_index]) / segment_length,
		0.0,
		1.0
	)
	var forward := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if forward.length_squared() <= 0.000001:
		return {}
	forward = forward.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var basis := Basis(
		right * TRADE_FLOW_MARKER_WIDTH,
		Vector3.UP,
		forward * TRADE_FLOW_MARKER_LENGTH
	)
	return {
		"transform": Transform3D(basis, from.lerp(to, ratio)),
		"direction": forward,
	}


func _append_dashed_draped_path(
	surface_tool: SurfaceTool,
	path: PackedVector2Array,
	width: float,
	color: Color,
	elevation: float
) -> void:
	for index in range(path.size() - 1):
		var samples := _draped_world_samples(
			path[index], path[index + 1], elevation
		)
		var travelled := 0.0
		for sample_index in range(samples.size() - 1):
			var from := samples[sample_index]
			var to := samples[sample_index + 1]
			var length := from.distance_to(to)
			var midpoint_distance := travelled + length * 0.5
			travelled += length
			if int(floor(midpoint_distance / TRADE_ROUTE_DASH_WORLD_LENGTH)) % 2 != 0:
				continue
			_append_world_segment_quad(
				surface_tool, from, to, width, color
			)


func _append_world_segment_quad(
	surface_tool: SurfaceTool,
	from: Vector3,
	to: Vector3,
	width: float,
	color: Color
) -> void:
	var direction := Vector2(to.x - from.x, to.z - from.z)
	if direction.length_squared() <= 0.000001:
		return
	var perpendicular := direction.normalized().orthogonal() * width
	var offset := Vector3(perpendicular.x, 0.0, perpendicular.y)
	_append_colored_quad(
		surface_tool, from - offset, to - offset,
		to + offset, from + offset, color
	)


func _trade_route_material() -> StandardMaterial3D:
	var material := _line_material(false)
	material.no_depth_test = false
	material.render_priority = 5
	return material


func _apply_map_mode_visibility() -> void:
	var trade_mode := _map_mode == MapRenderer.MapMode.TRADE
	if _roads != null:
		_roads.transparency = 0.70 if trade_mode else 0.0
	if _minor_roads != null:
		_minor_roads.transparency = 0.78 if trade_mode else 0.0
		_minor_roads.visible = _camera_distance <= 62.0
	if _rivers != null:
		_rivers.transparency = 0.46 if trade_mode else 0.0
	if _trade_routes != null:
		_trade_routes.visible = trade_mode
		_trade_routes.transparency = 0.0
	if _trade_flow_markers != null:
		_trade_flow_markers.visible = trade_mode


func _road_width_for_capacity(capacity: int) -> float:
	if capacity >= Edge.WATER_MANPOWER:
		return 0.106
	if capacity >= Edge.TERRAIN_STANDARD_MANPOWER:
		return 0.079
	return 0.036


func _road_color_for_capacity(capacity: int) -> Color:
	if capacity >= Edge.WATER_MANPOWER:
		return Color(0.012, 0.105, 0.165, 0.94)
	if capacity >= Edge.TERRAIN_STANDARD_MANPOWER:
		return Color(0.20, 0.065, 0.018, 0.92)
	return Color(0.085, 0.028, 0.010, 0.78)


func _build_river_mesh() -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for river in state.river_paths:
		for index in range(river.size() - 1):
			_append_world_ribbon(
				surface_tool,
				river[index],
				river[index + 1],
				0.075,
				Color(0.008, 0.095, 0.165, 0.96),
				0.11
			)
	_rivers.mesh = surface_tool.commit()
	_rivers.material_override = _line_material(false)


func _build_city_instances() -> void:
	var base_marker := CylinderMesh.new()
	base_marker.top_radius = 0.34
	base_marker.bottom_radius = 0.39
	base_marker.height = 0.14
	base_marker.radial_segments = 12
	_configure_multimesh(
		_city_bases, base_marker, state.cities.size(),
		_instance_color_material(false, true)
	)
	var city_marker := CylinderMesh.new()
	city_marker.top_radius = 0.25
	city_marker.bottom_radius = 0.30
	city_marker.height = 0.28
	city_marker.radial_segments = 12
	_configure_multimesh(
		_cities, city_marker, state.cities.size(),
		_instance_color_material(false, true)
	)
	var resource_marker := BoxMesh.new()
	resource_marker.size = Vector3(0.23, 0.10, 0.23)
	_configure_multimesh(
		_city_resource_markers, resource_marker,
		state.cities.size(), _instance_color_material(true, true)
	)
	var dock_ring := TorusMesh.new()
	dock_ring.inner_radius = 0.27
	dock_ring.outer_radius = 0.36
	dock_ring.rings = 16
	dock_ring.ring_segments = 6
	_configure_multimesh(
		_dock_rings, dock_ring, state.cities.size(),
		_instance_color_material(true, true)
	)
	var capital_ring := TorusMesh.new()
	capital_ring.inner_radius = 0.34
	capital_ring.outer_radius = 0.48
	capital_ring.rings = 16
	capital_ring.ring_segments = 8
	_configure_multimesh(
		_capital_rings, capital_ring, 0,
		_instance_color_material(true, true)
	)
	_rebuild_city_labels()


func _rebuild_city_labels() -> void:
	_last_detail_visibility_signature.clear()
	for label in _city_labels:
		if is_instance_valid(label):
			label.queue_free()
	_city_labels.clear()
	for city in state.cities:
		if (
			city.is_dock
			or not (
				city.is_capital
				or city.is_food_hub
				or city.is_manpower_hub
				or city.is_crossroads
			)
		):
			continue
		var label := Label3D.new()
		label.text = WorldNaming.city_display_name(state, city.id)
		if city.is_food_hub:
			label.text += " 粮"
		if city.is_manpower_hub:
			label.text += " 人"
		label.font = _map_font
		label.font_size = 28
		label.outline_size = 8
		label.pixel_size = 0.014
		label.modulate = MAP_IVORY
		label.outline_modulate = Color(0.025, 0.018, 0.010, 0.96)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = (
			_terrain.map_to_world(city.map_position)
			+ Vector3(0.0, 0.86, 0.0)
		)
		_content.add_child(label)
		_city_labels.append(label)


func _update_city_instances() -> void:
	if _cities.multimesh == null or _city_bases.multimesh == null:
		return
	_update_capital_rings()
	for city in state.cities:
		var world := _terrain.map_to_world(city.map_position)
		var scale := (
			1.30
			if city.is_capital
			else 0.62 if city.is_dock else 0.78
		)
		var basis := Basis.IDENTITY.scaled(
			Vector3(scale, scale, scale)
		)
		_city_bases.multimesh.set_instance_transform(
			city.id,
			Transform3D(
				basis,
				world + Vector3(0.0, 0.10 * scale, 0.0)
			)
		)
		_city_bases.multimesh.set_instance_color(city.id, MAP_INK)
		_cities.multimesh.set_instance_transform(
			city.id,
			Transform3D(
				Basis.IDENTITY.scaled(
					Vector3(scale * 0.78, scale, scale * 0.78)
				),
				world + Vector3(0.0, 0.23 * scale, 0.0)
			)
		)
		var color := (
			MapRenderer.loyalty_color(city.loyalty)
			if _map_mode == MapRenderer.MapMode.LOYALTY
			else (
				MapRenderer.final_faction_visual_color(
					state, city.owner_nation,
					0.34 if city.at_war else 0.0,
					0.08 if city.is_capital else 0.0
				)
				if city.owner_nation >= 0
				else Color(0.45, 0.45, 0.42)
			)
		)
		_cities.multimesh.set_instance_color(city.id, color)

		var resource_scale := 0.001
		var resource_color := MAP_IVORY
		if city.is_food_hub:
			resource_scale = 1.0
			resource_color = Color(0.82, 0.66, 0.18)
		elif city.is_manpower_hub:
			resource_scale = 1.0
			resource_color = Color(0.78, 0.22, 0.14)
		elif city.is_crossroads:
			resource_scale = 0.78
			resource_color = MAP_IVORY
		_city_resource_markers.multimesh.set_instance_transform(
			city.id,
			Transform3D(
				Basis(Vector3.UP, PI * 0.25).scaled(
					Vector3.ONE * resource_scale * scale
				),
				world + Vector3(0.0, 0.58 * scale, 0.0)
			)
		)
		_city_resource_markers.multimesh.set_instance_color(
			city.id, resource_color
		)
		var dock_scale := scale if city.is_dock else 0.001
		_dock_rings.multimesh.set_instance_transform(
			city.id,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * dock_scale),
				world + Vector3(0.0, 0.34, 0.0)
			)
		)
		_dock_rings.multimesh.set_instance_color(
			city.id, Color(0.24, 0.66, 0.72)
		)


func _update_capital_rings() -> void:
	var capitals: Array[City] = []
	for city in state.cities:
		if city.is_capital and not city.is_dock:
			capitals.append(city)
	_capital_rings.multimesh.instance_count = capitals.size()
	for index in range(capitals.size()):
		var capital := capitals[index]
		var world := _terrain.map_to_world(capital.map_position)
		_capital_rings.multimesh.set_instance_transform(
			index,
			Transform3D(
				Basis.IDENTITY,
				world + Vector3(0.0, 0.19, 0.0)
			)
		)
		_capital_rings.multimesh.set_instance_color(index, MAP_GOLD)


func _rebuild_nation_labels() -> void:
	_last_detail_visibility_signature.clear()
	for label in _nation_labels:
		if is_instance_valid(label):
			label.queue_free()
	_nation_labels.clear()
	_ensure_nation_label_layout_cache()
	for nation in state.nations:
		if not nation.alive:
			continue
		var layout := _nation_label_layout(nation.id)
		if layout.is_empty():
			continue
		if (
			bool(layout.get("hidden", true))
			or not bool(layout.get("inside_mask", false))
			or not bool(layout.get("fits_mask", false))
			or float(layout.get("pixel_size", 0.0)) <= 0.0
		):
			continue
		var text_value := str(layout["text"])
		var anchor: Vector2 = layout["anchor"]
		var label := Label3D.new()
		label.text = text_value
		label.font = _map_font
		label.font_size = NATION_LABEL_FONT_SIZE
		label.outline_size = NATION_LABEL_OUTLINE_SIZE
		label.pixel_size = float(layout["pixel_size"])
		label.modulate = Color(0.075, 0.078, 0.082, 0.86)
		label.outline_modulate = Color(0.62, 0.60, 0.54, 0.18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = true
		label.render_priority = 8
		label.basis = _nation_label_basis()
		label.position = (
			_terrain.map_to_world(anchor)
			+ Vector3(0.0, 0.34, 0.0)
		)
		label.set_meta("nation_id", nation.id)
		label.set_meta("layout", layout)
		_content.add_child(label)
		_nation_labels.append(label)


func _nation_label_layout(nation_id: int) -> Dictionary:
	if (
		state == null
		or _map_font == null
		or nation_id < 0
		or nation_id >= state.nations.size()
	):
		return {}
	_ensure_nation_label_layout_cache()
	if _nation_label_layout_cache.has(nation_id):
		return _nation_label_layout_cache[nation_id]
	return _nation_label_fallback_layout(nation_id)


func _ensure_nation_label_layout_cache() -> void:
	if state == null or _map_font == null:
		return
	var size := state.province_map_size
	var total := size.x * size.y
	var territory_stale := (
		_nation_label_cache_ownership_revision != state.ownership_revision
		or _nation_label_cache_map_size != size
		or _nation_label_cache_nation_count != state.nations.size()
	)
	if territory_stale:
		_rebuild_nation_label_territory_cache(size, total)
	var layout_stale := (
		territory_stale
		or _nation_label_cache_naming_revision != state.naming_revision
		or _nation_label_cache_diplomacy_revision != state.diplomacy_revision
	)
	if not layout_stale:
		return
	_nation_label_layout_cache.clear()
	for nation in state.nations:
		if not nation.alive:
			continue
		var nation_id := int(nation.id)
		var territory: Dictionary = _nation_label_territory_cache.get(
			nation_id, {}
		)
		_nation_label_layout_cache[nation_id] = (
			_nation_label_layout_from_territory(nation_id, territory, size)
		)
	_nation_label_cache_naming_revision = state.naming_revision
	_nation_label_cache_diplomacy_revision = state.diplomacy_revision


func _rebuild_nation_label_territory_cache(
	size: Vector2i, total: int
) -> void:
	_nation_label_territory_cache.clear()
	_nation_label_layout_cache.clear()
	_nation_label_cache_ownership_revision = state.ownership_revision
	_nation_label_cache_map_size = size
	_nation_label_cache_nation_count = state.nations.size()
	_nation_label_territory_index_builds += 1
	_nation_label_territory_index_pixel_visits = 0
	if (
		size.x <= 0
		or size.y <= 0
		or total <= 0
		or state.province_ids.size() != total
	):
		return
	var owner_by_cell := PackedInt32Array()
	owner_by_cell.resize(total)
	owner_by_cell.fill(-1)
	for index in range(total):
		_nation_label_territory_index_pixel_visits += 1
		var province_id := int(state.province_ids[index])
		if province_id < 0 or province_id >= state.cities.size():
			continue
		var owner := int(state.cities[province_id].owner_nation)
		if owner < 0 or owner >= state.nations.size():
			continue
		owner_by_cell[index] = owner
	var visited := PackedByteArray()
	visited.resize(total)
	var largest_components := {}
	for index in range(total):
		_nation_label_territory_index_pixel_visits += 1
		var owner := int(owner_by_cell[index])
		if owner < 0 or visited[index] > 0:
			continue
		var queue: Array[int] = [index]
		var head := 0
		visited[index] = 1
		var component_indices: Array[int] = []
		var min_x := size.x
		var min_y := size.y
		var max_x := -1
		var max_y := -1
		while head < queue.size():
			var current := queue[head]
			head += 1
			component_indices.append(current)
			var x: int = current % size.x
			var y: int = current / size.x
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
			for offset in [
				Vector2i(-1, 0), Vector2i(1, 0),
				Vector2i(0, -1), Vector2i(0, 1),
			]:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or nx >= size.x or ny < 0 or ny >= size.y:
					continue
				var neighbor := ny * size.x + nx
				if visited[neighbor] > 0 or owner_by_cell[neighbor] != owner:
					continue
				visited[neighbor] = 1
				queue.append(neighbor)
		var previous: Dictionary = largest_components.get(owner, {})
		if component_indices.size() > int(previous.get("area", 0)):
			largest_components[owner] = {
				"area": component_indices.size(),
				"indices": component_indices,
				"bounds": Rect2i(
					min_x, min_y, max_x - min_x + 1, max_y - min_y + 1
				),
			}
	for owner_value in largest_components:
		var owner := int(owner_value)
		var component: Dictionary = largest_components[owner]
		var bounds: Rect2i = component["bounds"]
		var local_mask := PackedByteArray()
		local_mask.resize(bounds.size.x * bounds.size.y)
		for cell_value in component["indices"]:
			var cell := int(cell_value)
			var local_x: int = cell % size.x - bounds.position.x
			var local_y: int = cell / size.x - bounds.position.y
			local_mask[local_y * bounds.size.x + local_x] = 1
		var local_rect := _largest_mask_rectangle(
			local_mask, bounds.size.x, bounds.size.y
		)
		if local_rect.size.x <= 0 or local_rect.size.y <= 0:
			continue
		var local_anchor := Vector2i(
			clampi(
				int(floor(float(local_rect.position.x) + float(local_rect.size.x) * 0.5)),
				local_rect.position.x, local_rect.end.x - 1
			),
			clampi(
				int(floor(float(local_rect.position.y) + float(local_rect.size.y) * 0.5)),
				local_rect.position.y, local_rect.end.y - 1
			)
		)
		_nation_label_territory_cache[owner] = {
			"component_area": int(component["area"]),
			"rect": Rect2i(
				bounds.position + local_rect.position, local_rect.size
			),
			"inside_mask": (
				local_mask[local_anchor.y * bounds.size.x + local_anchor.x] > 0
			),
			"rect_inside_component": _rect_fully_inside_mask(
				local_mask, bounds.size.x, bounds.size.y, local_rect
			),
		}


func _nation_label_layout_from_territory(
	nation_id: int, territory: Dictionary, size: Vector2i
) -> Dictionary:
	if territory.is_empty():
		return _nation_label_fallback_layout(nation_id)
	var component_area := int(territory.get("component_area", 0))
	if component_area <= 0:
		return _nation_label_fallback_layout(nation_id)
	var rect: Rect2i = territory.get("rect", Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return _nation_label_fallback_layout(nation_id)
	var rect_inside_component := bool(territory.get(
		"rect_inside_component", false
	))
	if not rect_inside_component:
		return _nation_label_fallback_layout(nation_id)
	var anchor_px := Vector2(
		float(rect.position.x) + float(rect.size.x) * 0.5,
		float(rect.position.y) + float(rect.size.y) * 0.5
	)
	var anchor := Vector2(
		anchor_px.x / float(size.x),
		anchor_px.y / float(size.y)
	)
	var inside_mask := bool(territory.get("inside_mask", false))
	var map_rect := Rect2(
		Vector2(rect.position) / Vector2(size),
		Vector2(rect.size) / Vector2(size)
	)
	var rect_world_size := Vector2(
		float(rect.size.x) / float(size.x) * _world_size.x,
		float(rect.size.y) / float(size.y) * _world_size.y
	)
	var chosen := _nation_label_choose_text(
		nation_id, rect_world_size, NATION_LABEL_FONT_SIZE
	)
	var pixel_size: float = float(chosen.get("pixel_size", 0.0))
	var bbox_world_size := Vector2(
		float(chosen.get("bbox_width", 0.0)) * pixel_size,
		float(chosen.get("bbox_height", 0.0)) * pixel_size
	)
	var fits_mask := (
		rect_inside_component
		and not bool(chosen.get("hidden", true))
		and pixel_size > 0.0
		and bbox_world_size.x
			<= rect_world_size.x * NATION_LABEL_SAFETY
				+ NATION_LABEL_FIT_EPSILON
		and bbox_world_size.y
			<= rect_world_size.y * NATION_LABEL_SAFETY
				+ NATION_LABEL_FIT_EPSILON
	)
	return {
		"text": str(chosen.get("text", "")),
		"glyph_scale": (
			pixel_size / NATION_LABEL_BASE_PIXEL_SIZE
			if pixel_size > 0.0
			else 0.0
		),
		"pixel_size": pixel_size,
		"inside_mask": inside_mask,
		"fits_mask": fits_mask,
		"hidden": bool(chosen.get("hidden", true)),
		"component_area": component_area,
		"rect": rect,
		"map_rect": map_rect,
		"anchor": anchor,
		"bbox_world_size": bbox_world_size,
	}


func _nation_label_basis() -> Basis:
	return Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)


func _nation_label_choose_text(
	nation_id: int, rect_world_size: Vector2, font_size: int
) -> Dictionary:
	var full_name := str(
		WorldNaming.nation_display_name(state, nation_id, false)
	).strip_edges()
	if full_name.is_empty():
		return {
			"text": "",
			"pixel_size": 0.0,
			"bbox_width": 0.0,
			"bbox_height": 0.0,
			"hidden": true,
		}
	var text_size: Vector2 = _map_font.get_string_size(
		full_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	)
	if text_size.x <= 0.0 or text_size.y <= 0.0:
		return {
			"text": full_name,
			"pixel_size": 0.0,
			"bbox_width": 0.0,
			"bbox_height": 0.0,
			"hidden": true,
		}
	var bbox_size := Vector2(
		text_size.x + float(NATION_LABEL_OUTLINE_SIZE * 2),
		text_size.y + float(NATION_LABEL_OUTLINE_SIZE * 2)
	)
	# 地图和详情面板必须展示同一个正式国名。领土再小也只缩放完整名称，
	# 不再跨过可读字号下限后改用城市简称；否则“快王”会只剩“快”，
	# 漏掉“王”并与详情页法理归属不一致。
	var pixel_size: float = clampf(
		minf(
			rect_world_size.x * NATION_LABEL_SAFETY / bbox_size.x,
			rect_world_size.y * NATION_LABEL_SAFETY / bbox_size.y
		),
		0.0, NATION_LABEL_MAX_PIXEL_SIZE
	)
	return {
		"text": full_name,
		"pixel_size": pixel_size,
		"bbox_width": bbox_size.x,
		"bbox_height": bbox_size.y,
		"hidden": pixel_size <= 0.0,
	}


func _largest_mask_rectangle(
	mask: PackedByteArray, width: int, height: int
) -> Rect2i:
	var heights := PackedInt32Array()
	heights.resize(width)
	var best_area := 0
	var best_rect := Rect2i()
	for y in range(height):
		for x in range(width):
			var index: int = y * width + x
			if mask[index] > 0:
				heights[x] += 1
			else:
				heights[x] = 0
		var stack: Array[int] = []
		for x in range(width + 1):
			var current_height: int = 0
			if x < width:
				current_height = heights[x]
			while (
				not stack.is_empty()
				and current_height < heights[stack[stack.size() - 1]]
			):
				var top: int = stack[stack.size() - 1]
				stack.pop_back()
				var rect_height: int = heights[top]
				if rect_height <= 0:
					continue
				var rect_left: int = (
					stack[stack.size() - 1] + 1
					if not stack.is_empty()
					else 0
				)
				var rect_width: int = x - rect_left
				var area: int = rect_height * rect_width
				if area <= best_area:
					continue
				best_area = area
				best_rect = Rect2i(
					rect_left,
					y - rect_height + 1,
					rect_width,
					rect_height
				)
			stack.append(x)
	return best_rect


func _rect_fully_inside_mask(
	mask: PackedByteArray, width: int, height: int, rect: Rect2i
) -> bool:
	if (
		rect.position.x < 0
		or rect.position.y < 0
		or rect.end.x > width
		or rect.end.y > height
	):
		return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if mask[y * width + x] == 0:
				return false
	return true


func _nation_label_fallback_layout(nation_id: int) -> Dictionary:
	var center := Vector2(0.5, 0.5)
	var count := 0
	for city in state.cities:
		if city.owner_nation != nation_id or city.is_dock:
			continue
		center += city.map_position
		count += 1
	if count > 0:
		center /= float(count + 1)
	return {
		"text": str(WorldNaming.nation_display_name(state, nation_id, false)),
		"glyph_scale": 0.0,
		"pixel_size": 0.0,
		"inside_mask": false,
		"fits_mask": false,
		"hidden": true,
		"component_area": 0,
		"rect": Rect2i(),
		"map_rect": Rect2(
			Vector2(
				clampf(center.x - 0.01, 0.0, 0.98),
				clampf(center.y - 0.01, 0.0, 0.98)
			),
			Vector2(0.02, 0.02)
		),
		"anchor": Vector2(
			clampf(center.x, 0.0, 1.0), clampf(center.y, 0.0, 1.0)
		),
		"bbox_world_size": Vector2.ZERO,
	}


func _update_army_instances() -> void:
	if _terrain == null or _terrain.land_cell_count() <= 0:
		return
	var living: Array[Army] = []
	for army in state.armies:
		if army.size > 0:
			living.append(army)
	if _armies.multimesh == null:
		_build_army_counter_meshes()
	var living_ids: Array[int] = []
	for army in living:
		living_ids.append(army.id)
	var rebuild_all := living_ids != _army_instance_ids
	var refresh_appearance := (
		rebuild_all
		or not _army_instances_initialized
		or _last_army_instances_day != state.day
		or not is_equal_approx(
			_last_army_icon_scale, overlay.army_icon_scale()
		)
	)
	if rebuild_all:
		_army_instance_ids = living_ids
		_army_render_positions.clear()
		_army_render_signatures.clear()
		for layer in [
			_army_bases, _armies, _army_symbol_a, _army_symbol_b,
			_army_morale_backs, _army_morale_bars,
		]:
			layer.multimesh.instance_count = living.size()
	for index in range(living.size()):
		var army := living[index]
		var position_may_change := (
			army.on_edge
			or army.state in [Army.State.MOVING, Army.State.RETREATING]
		)
		if not refresh_appearance and not position_may_change:
			continue
		var map_position := overlay.army_map_position(army)
		var position_changed: bool = (
			rebuild_all
			or _army_render_positions.get(army.id) != map_position
		)
		var is_main_role := army.is_main_battle_role()
		var morale_ratio := army.morale_ratio()
		var render_signature: Array = []
		var appearance_changed := rebuild_all
		if refresh_appearance:
			render_signature = [
				is_main_role,
				army.max_size,
				morale_ratio,
				army.starving,
				army.state,
				army.owner_nation,
				overlay.army_icon_scale(),
				state.diplomacy_revision,
				overlay.diplomatic_view_nation_id(),
			]
			appearance_changed = (
				rebuild_all
				or _army_render_signatures.get(army.id) != render_signature
			)
		if not position_changed and not appearance_changed:
			continue
		var world := _terrain.map_to_world(map_position)
		var angle := float(army.id % 11) / 11.0 * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.34
		var scale := overlay.army_icon_scale() * army_role_scale(army)
		# Ground the counter on the terrain surface like city bases and roads
		# instead of hovering above it. The base box is 0.16 tall, so a 0.10
		# lift keeps its underside flush with the map while the stacked face,
		# symbols and morale bar rise from there.
		var origin := world + offset + Vector3(0.0, 0.10, 0.0)
		_set_counter_transform(
			_army_bases, index, origin, scale,
			Vector3(1.30, 1.0, 1.12)
				if is_main_role else Vector3(0.88, 1.0, 0.82)
		)
		_set_counter_transform(
			_armies, index, origin + Vector3(0.0, 0.10, 0.0),
			scale,
			Vector3(1.16, 1.0, 1.0)
				if is_main_role else Vector3(0.90, 1.0, 0.82)
		)
		# 主战军使用醒目的“+”号与金色厚底；填线军使用“×”号与
		# 紧凑黑底。战团中的5000轻军也按 MAIN 外观显示。
		var first_angle := 0.0 if is_main_role else PI * 0.25
		var symbol_basis := Basis(Vector3.UP, first_angle).scaled(
			Vector3(scale, scale, scale)
		)
		var symbol_origin := origin + Vector3(0.0, 0.225, 0.0)
		_army_symbol_a.multimesh.set_instance_transform(
			index, Transform3D(symbol_basis, symbol_origin)
		)
		var second_angle := (
			PI * 0.5 if is_main_role else -PI * 0.25
		)
		_army_symbol_b.multimesh.set_instance_transform(
			index,
			Transform3D(
				Basis(Vector3.UP, second_angle).scaled(
					Vector3(scale, scale, scale)
				),
				symbol_origin
			)
		)
		_set_morale_bar_transform(
			_army_morale_backs, index, origin, scale, 1.0
		)
		_set_morale_bar_transform(
			_army_morale_bars, index, origin, scale, morale_ratio
		)
		if appearance_changed:
			var color := MapRenderer.final_faction_visual_color(
				state, army.owner_nation,
				0.62 if army.starving else 0.0,
				0.06 if army.state == Army.State.FIGHTING else 0.0
			)
			_army_bases.multimesh.set_instance_color(
				index, army_role_base_color(army)
			)
			_armies.multimesh.set_instance_color(index, color)
			_army_symbol_a.multimesh.set_instance_color(
				index, MAP_GOLD if is_main_role else MAP_COUNTER_MARK
			)
			_army_symbol_b.multimesh.set_instance_color(
				index, MAP_GOLD if is_main_role else MAP_COUNTER_MARK
			)
			_army_morale_backs.multimesh.set_instance_color(index, MAP_INK)
			_army_morale_bars.multimesh.set_instance_color(
				index, _morale_color(morale_ratio, army.starving)
			)
		_army_render_positions[army.id] = map_position
		if appearance_changed:
			_army_render_signatures[army.id] = render_signature
	_last_army_instances_day = state.day
	_army_instances_initialized = true
	_last_army_icon_scale = overlay.army_icon_scale()


func _on_runtime_day_committed(_day: int) -> void:
	# MapRenderer 在本节点之前连接同一信号，会先发布位置快照。此处立即
	# 消费完整日状态，避免模拟因积压连续启动下一日时永远错过空闲帧。
	_update_army_instances()


## 模拟推进期间只移动已有实例，位置来自 MapRenderer 的已提交快照。
## 不扫描可变军队集合，也不更新阵营、士气等外观状态。
func _update_army_snapshot_positions() -> void:
	if _army_bases.multimesh == null:
		return
	var count := mini(
		_army_instance_ids.size(),
		_army_bases.multimesh.instance_count
	)
	var layers: Array[MultiMeshInstance3D] = [
		_army_bases, _armies, _army_symbol_a, _army_symbol_b,
		_army_morale_backs, _army_morale_bars,
	]
	for index in range(count):
		var army_id := _army_instance_ids[index]
		var fallback: Vector2 = _army_render_positions.get(
			army_id, Vector2.ZERO
		)
		var map_position := overlay.army_snapshot_position(
			army_id, fallback
		)
		if _army_render_positions.get(army_id) == map_position:
			continue
		var angle := float(army_id % 11) / 11.0 * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.34
		var target_base_origin := (
			_terrain.map_to_world(map_position)
			+ offset
			+ Vector3(0.0, 0.10, 0.0)
		)
		var current_base := _army_bases.multimesh.get_instance_transform(index)
		var translation := target_base_origin - current_base.origin
		for layer in layers:
			var transform := layer.multimesh.get_instance_transform(index)
			transform.origin += translation
			layer.multimesh.set_instance_transform(index, transform)
		_army_render_positions[army_id] = map_position


## 大小滑块只缩放已经发布的实例，避免等待一个可能持续数秒的模拟日。
func _rescale_army_instances(next_scale: float) -> void:
	if _army_bases.multimesh == null or _last_army_icon_scale <= 0.0:
		_last_army_icon_scale = next_scale
		return
	var ratio := next_scale / _last_army_icon_scale
	if is_equal_approx(ratio, 1.0):
		return
	var count := _army_bases.multimesh.instance_count
	var layers: Array[MultiMeshInstance3D] = [
		_army_bases, _armies, _army_symbol_a, _army_symbol_b,
		_army_morale_backs, _army_morale_bars,
	]
	for index in range(count):
		var base_transform := (
			_army_bases.multimesh.get_instance_transform(index)
		)
		var base_origin := base_transform.origin
		for layer in layers:
			var transform := layer.multimesh.get_instance_transform(index)
			transform = scaled_counter_transform(
				transform, base_origin, ratio
			)
			layer.multimesh.set_instance_transform(index, transform)
	_last_army_icon_scale = next_scale


static func scaled_counter_transform(
	transform: Transform3D,
	base_origin: Vector3,
	ratio: float
) -> Transform3D:
	transform.basis = transform.basis.scaled(Vector3.ONE * ratio)
	transform.origin = (
		base_origin + (transform.origin - base_origin) * ratio
	)
	return transform


func _should_update_army_instances() -> bool:
	# MapRenderer only publishes new army position snapshots after the sliced
	# simulation day commits. Rendering during the coroutine exposes partial
	# state and repeats the full army scan on every intermediate frame.
	if sim != null and sim.runtime_day_in_progress():
		return false
	if not _army_instances_initialized or _last_army_instances_day != state.day:
		return true
	if not is_equal_approx(_last_army_icon_scale, overlay.army_icon_scale()):
		return true
	return false


static func army_role_scale(army: Army) -> float:
	if army == null or not army.is_main_battle_role():
		return 0.68
	return 1.18 if army.max_size >= Army.DEFAULT_MAX_SIZE else 1.02


static func army_role_base_color(army: Army) -> Color:
	return MAP_GOLD if army != null and army.is_main_battle_role() else MAP_INK


func _build_army_counter_meshes() -> void:
	var base := BoxMesh.new()
	base.size = Vector3(0.90, 0.16, 0.58)
	_configure_multimesh(
		_army_bases, base, 0, _instance_color_material(false, true)
	)
	var face := BoxMesh.new()
	face.size = Vector3(0.78, 0.13, 0.48)
	_configure_multimesh(
		_armies, face, 0, _instance_color_material(false, true)
	)
	var symbol := BoxMesh.new()
	symbol.size = Vector3(0.46, 0.045, 0.055)
	_configure_multimesh(
		_army_symbol_a, symbol, 0, _instance_color_material(false, true)
	)
	_configure_multimesh(
		_army_symbol_b, symbol, 0, _instance_color_material(false, true)
	)
	var morale_back := BoxMesh.new()
	morale_back.size = Vector3(0.68, 0.045, 0.065)
	_configure_multimesh(
		_army_morale_backs, morale_back, 0,
		_instance_color_material(false, true)
	)
	var morale_bar := BoxMesh.new()
	morale_bar.size = Vector3(0.62, 0.055, 0.040)
	_configure_multimesh(
		_army_morale_bars, morale_bar, 0,
		_instance_color_material(true, true)
	)


func _set_counter_transform(
	layer: MultiMeshInstance3D,
	index: int,
	origin: Vector3,
	scale: float,
	shape_scale: Vector3
) -> void:
	layer.multimesh.set_instance_transform(
		index,
		Transform3D(
			Basis.IDENTITY.scaled(shape_scale * scale), origin
		)
	)


func _set_morale_bar_transform(
	layer: MultiMeshInstance3D,
	index: int,
	origin: Vector3,
	scale: float,
	ratio: float
) -> void:
	var width := maxf(ratio, 0.001)
	var left := -0.31 * scale
	var center_x := left + 0.31 * width * scale
	layer.multimesh.set_instance_transform(
		index,
		Transform3D(
			Basis.IDENTITY.scaled(Vector3(width * scale, scale, scale)),
			origin + Vector3(center_x, 0.225, 0.226 * scale)
		)
	)


func _morale_color(ratio: float, starving: bool) -> Color:
	if starving or ratio < 0.30:
		return MAP_ALERT
	if ratio < 0.62:
		return MAP_GOLD
	return MAP_SUPPLY


func _update_battle_instances() -> void:
	var active: Array[Battle] = []
	for battle in state.battles:
		if not battle.finished:
			active.append(battle)
	if _battles.multimesh == null:
		_build_battle_marker_meshes()
	for layer in [
		_battles, _battle_rings, _battle_cross_a, _battle_cross_b,
	]:
		layer.multimesh.instance_count = active.size()
	for index in range(active.size()):
		var battle := active[index]
		var map_position := _battle_map_position(battle)
		var world := _terrain.map_to_world(map_position)
		var scale := (
			1.12 if battle.kind == Battle.Kind.SIEGE else 1.0
		)
		var origin := world + Vector3(0.0, 1.13, 0.0)
		_battles.multimesh.set_instance_transform(
			index,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * scale),
				origin
			)
		)
		_battle_rings.multimesh.set_instance_transform(
			index, Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * scale), origin
			)
		)
		var cross_origin := origin + Vector3(0.0, 0.28, 0.0)
		_battle_cross_a.multimesh.set_instance_transform(
			index, Transform3D(
				Basis(Vector3.UP, PI * 0.25).scaled(
					Vector3.ONE * scale
				), cross_origin
			)
		)
		_battle_cross_b.multimesh.set_instance_transform(
			index, Transform3D(
				Basis(Vector3.UP, -PI * 0.25).scaled(
					Vector3.ONE * scale
				), cross_origin
			)
		)
		_battles.multimesh.set_instance_color(index, MAP_ALERT)
		_battle_rings.multimesh.set_instance_color(index, MAP_GOLD)
		_battle_cross_a.multimesh.set_instance_color(index, MAP_IVORY)
		_battle_cross_b.multimesh.set_instance_color(index, MAP_IVORY)
		_update_battle_label(index, battle, origin)
	for index in range(active.size(), _battle_labels.size()):
		_battle_labels[index].set_meta("active", false)
		_battle_labels[index].visible = false


func _build_battle_marker_meshes() -> void:
	var center := CylinderMesh.new()
	center.top_radius = 0.34
	center.bottom_radius = 0.42
	center.height = 0.30
	center.radial_segments = 10
	_configure_multimesh(
		_battles, center, 0, _instance_color_material(true, true)
	)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.48
	ring.outer_radius = 0.62
	ring.rings = 18
	ring.ring_segments = 6
	_configure_multimesh(
		_battle_rings, ring, 0, _instance_color_material(true, true)
	)
	var cross := BoxMesh.new()
	cross.size = Vector3(0.72, 0.075, 0.095)
	_configure_multimesh(
		_battle_cross_a, cross, 0, _instance_color_material(true, true)
	)
	_configure_multimesh(
		_battle_cross_b, cross, 0, _instance_color_material(true, true)
	)


func _update_battle_label(
	index: int,
	battle: Battle,
	origin: Vector3
) -> void:
	_ensure_battle_label(index)
	var label := _battle_labels[index]
	if battle.kind == Battle.Kind.SIEGE:
		label.text = "围城 %d%%" % int(round(
			clampf(
				battle.siege_progress
					/ maxf(Combat.SIEGE_PROGRESS_REQUIRED, 1.0),
				0.0, 1.0
			) * 100.0
		))
	else:
		label.text = "会战 · %d回合" % battle.round_no
	label.position = origin + Vector3(0.0, 0.86, 0.0)
	label.set_meta("active", true)
	label.visible = _camera_distance <= 50.0


func _ensure_battle_label(index: int) -> void:
	while _battle_labels.size() <= index:
		var created := Label3D.new()
		created.font = _map_font
		created.font_size = 25
		created.outline_size = 8
		created.pixel_size = 0.0125
		created.modulate = MAP_IVORY
		created.outline_modulate = MAP_INK
		created.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		created.no_depth_test = true
		created.visible = false
		created.set_meta("active", false)
		_content.add_child(created)
		_battle_labels.append(created)


func _clear_battle_labels() -> void:
	for label in _battle_labels:
		if is_instance_valid(label):
			label.queue_free()
	_battle_labels.clear()


func _update_campaign_mesh() -> void:
	if _terrain == null or _terrain.land_cell_count() <= 0:
		return
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for event in state.campaign_visual_events:
		var alpha := MapRenderer.campaign_arrow_alpha(state.day, event)
		if alpha <= 0.0:
			continue
		var target_id := int(event.get("target_city", -1))
		if target_id < 0 or target_id >= state.cities.size():
			continue
		var target := state.cities[target_id].map_position
		for origin_id in event.get("origin_cities", []):
			if origin_id < 0 or origin_id >= state.cities.size():
				continue
			_append_campaign_arrow(
				surface_tool,
				state.cities[origin_id].map_position,
				target,
				alpha,
				int(event.get("wave", 0))
			)
	_campaigns.mesh = surface_tool.commit()
	_campaigns.material_override = _campaign_arrow_material()


func _append_campaign_arrow(
	surface_tool: SurfaceTool,
	from_uv: Vector2,
	to_uv: Vector2,
	alpha: float,
	_wave: int
) -> void:
	var from_metric := Vector2(
		from_uv.x * _world_size.x, from_uv.y * _world_size.y
	)
	var to_metric := Vector2(
		to_uv.x * _world_size.x, to_uv.y * _world_size.y
	)
	var target_delta := to_metric - from_metric
	var source_delta := (
		MapRenderer.CAMPAIGN_ARROW_SOURCE_TIP
		- MapRenderer.CAMPAIGN_ARROW_SOURCE_TAIL
	)
	if target_delta.length_squared() <= 0.000001:
		return
	var source_size := Vector2(CAMPAIGN_ARROW_TEXTURE.get_size())
	var scale := target_delta.length() / source_delta.length()
	var rotation := target_delta.angle() - source_delta.angle()
	var from_height := _terrain.height_at_map_position(from_uv)
	var to_height := _terrain.height_at_map_position(to_uv)
	var arch_height := _campaign_arrow_arch_height(
		from_uv, to_uv, target_delta.length(), from_height, to_height
	)
	for grid_y in range(CAMPAIGN_ARROW_GRID.y):
		var v0 := float(grid_y) / float(CAMPAIGN_ARROW_GRID.y)
		var v1 := float(grid_y + 1) / float(CAMPAIGN_ARROW_GRID.y)
		for grid_x in range(CAMPAIGN_ARROW_GRID.x):
			var u0 := float(grid_x) / float(CAMPAIGN_ARROW_GRID.x)
			var u1 := float(grid_x + 1) / float(CAMPAIGN_ARROW_GRID.x)
			var uv00 := Vector2(u0, v0)
			var uv10 := Vector2(u1, v0)
			var uv01 := Vector2(u0, v1)
			var uv11 := Vector2(u1, v1)
			_append_campaign_texture_triangle(
				surface_tool, uv00, uv10, uv01, source_size,
				from_metric, scale, rotation, from_height, to_height,
				arch_height, alpha
			)
			_append_campaign_texture_triangle(
				surface_tool, uv10, uv11, uv01, source_size,
				from_metric, scale, rotation, from_height, to_height,
				arch_height, alpha
			)


func _append_campaign_texture_triangle(
	surface_tool: SurfaceTool,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2,
	source_size: Vector2, from_metric: Vector2,
	scale: float, rotation: float,
	from_height: float, to_height: float,
	arch_height: float, alpha: float
) -> void:
	for uv in [uv_a, uv_b, uv_c]:
		var typed_uv: Vector2 = uv
		var source_point: Vector2 = typed_uv * source_size
		var world := _campaign_arrow_surface_point(
			source_point, from_metric, scale, rotation,
			from_height, to_height, arch_height
		)
		surface_tool.set_uv(typed_uv)
		surface_tool.set_color(Color(1.0, 1.0, 1.0, 0.94 * alpha))
		surface_tool.add_vertex(world)


func _campaign_arrow_arch_height(
	from_uv: Vector2,
	to_uv: Vector2,
	metric_length: float,
	from_height: float,
	to_height: float
) -> float:
	var arch_height := clampf(
		metric_length * CAMPAIGN_ARROW_ARCH_LENGTH_RATIO,
		CAMPAIGN_ARROW_MIN_ARCH_HEIGHT,
		CAMPAIGN_ARROW_MAX_ARCH_HEIGHT
	)
	# 长箭头跨越高地时提高控制点，但不逐点复制地形起伏。最终曲面
	# 仍是单一平滑拱面；这里只用沿线最高地形决定整体弧高。
	for sample_index in range(1, CAMPAIGN_ARROW_TERRAIN_SAMPLES):
		var progress := (
			float(sample_index)
			/ float(CAMPAIGN_ARROW_TERRAIN_SAMPLES)
		)
		var profile := sin(progress * PI)
		if profile < 0.35:
			continue
		var map_point := from_uv.lerp(to_uv, progress)
		var terrain_height := _terrain.height_at_map_position(
			map_point
		)
		var baseline := lerpf(
			from_height, to_height, progress
		) + CAMPAIGN_ARROW_ENDPOINT_CLEARANCE
		arch_height = maxf(
			arch_height,
			(terrain_height + CAMPAIGN_ARROW_SURFACE_CLEARANCE
				- baseline) / profile
		)
	return minf(arch_height, CAMPAIGN_ARROW_MAX_ARCH_HEIGHT)


func _campaign_arrow_surface_point(
	source_point: Vector2,
	from_metric: Vector2,
	scale: float,
	rotation: float,
	from_height: float,
	to_height: float,
	arch_height: float
) -> Vector3:
	var source_delta := (
		MapRenderer.CAMPAIGN_ARROW_SOURCE_TIP
		- MapRenderer.CAMPAIGN_ARROW_SOURCE_TAIL
	)
	var source_offset := (
		source_point - MapRenderer.CAMPAIGN_ARROW_SOURCE_TAIL
	)
	var progress := clampf(
		source_offset.dot(source_delta)
			/ maxf(source_delta.length_squared(), 0.000001),
		0.0,
		1.0
	)
	var metric_offset := source_offset.rotated(rotation) * scale
	var metric_point := from_metric + metric_offset
	var map_point := Vector2(
		metric_point.x / _world_size.x,
		metric_point.y / _world_size.y
	)
	var curve_height := lerpf(
		from_height, to_height, progress
	) + CAMPAIGN_ARROW_ENDPOINT_CLEARANCE + (
		sin(progress * PI) * arch_height
	)
	var world := _terrain.map_to_world(map_point)
	# 高度只来自一条连续拱线，不逐顶点追随下面的山脊和沟谷。
	world.y = curve_height
	return world


func _append_tapered_draped_path(
	surface_tool: SurfaceTool,
	points: PackedVector2Array,
	start_width: float,
	end_width: float,
	color: Color,
	elevation: float
) -> void:
	for index in range(points.size() - 1):
		var ratio_a := float(index) / float(points.size() - 1)
		var ratio_b := float(index + 1) / float(points.size() - 1)
		var from := _terrain.map_to_world(points[index])
		var to := _terrain.map_to_world(points[index + 1])
		from.y += elevation
		to.y += elevation
		var segment := Vector2(to.x - from.x, to.z - from.z)
		if segment.length_squared() <= 0.000001:
			continue
		var normal := segment.normalized().orthogonal()
		var from_offset := Vector3(normal.x, 0.0, normal.y) * lerpf(
			start_width, end_width, ratio_a
		)
		var to_offset := Vector3(normal.x, 0.0, normal.y) * lerpf(
			start_width, end_width, ratio_b
		)
		_append_colored_quad(
			surface_tool, from - from_offset, to - to_offset,
			to + to_offset, from + from_offset, color
		)


func _append_draped_triangle(
	surface_tool: SurfaceTool,
	a_uv: Vector2,
	b_uv: Vector2,
	c_uv: Vector2,
	color: Color,
	elevation: float
) -> void:
	for uv in [a_uv, b_uv, c_uv]:
		var world := _terrain.map_to_world(uv)
		world.y += elevation
		surface_tool.set_color(color)
		surface_tool.add_vertex(world)


func _update_selection_marker() -> void:
	if overlay == null or _terrain == null:
		return
	var city_id := overlay.selected_city_id()
	if city_id >= 0 and city_id < state.cities.size():
		_selection.position = (
			_terrain.map_to_world(
				state.cities[city_id].map_position
			)
			+ Vector3(0.0, 0.34, 0.0)
		)
		var pulse := 1.0 + sin(_visual_time * 3.2) * 0.08
		_selection.scale = Vector3.ONE * pulse
		_selection.visible = true
		return
	_selection.visible = false


func _update_edge_selection() -> void:
	if overlay == null or _terrain == null:
		return
	var pair := overlay.selected_edge_pair()
	if pair == _last_selected_edge:
		return
	_last_selected_edge = pair
	if pair.x < 0 or pair.y < 0:
		_edge_selection.mesh = null
		return
	var edge := state.edge_of(pair.x, pair.y)
	if edge == null or not MapRenderer.is_edge_visible(edge):
		_edge_selection.mesh = null
		return
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_draped_path_ribbon(
		surface_tool,
		edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		),
		_road_width_for_capacity(edge.max_manpower) * 2.4,
		Color(1.0, 0.72, 0.12, 0.96),
		0.18
	)
	_edge_selection.mesh = surface_tool.commit()


func _update_city_label_visibility() -> void:
	_update_map_detail_visibility()


func _update_map_detail_visibility() -> void:
	if overlay == null:
		return
	var visible := overlay.city_names_visible()
	var nation_visible := overlay.nation_names_visible()
	var signature: Array = [
		visible and _camera_distance <= 40.0,
		nation_visible,
		_camera_distance <= 50.0,
		_camera_distance <= 62.0,
		_map_mode,
	]
	if signature == _last_detail_visibility_signature:
		return
	_last_detail_visibility_signature = signature
	for label in _city_labels:
		label.visible = bool(signature[0])
	for label in _nation_labels:
		label.visible = nation_visible
	for label in _battle_labels:
		label.visible = (
			bool(signature[2]) and bool(label.get_meta("active", false))
		)
	if _minor_roads != null:
		_minor_roads.visible = bool(signature[3])
	_apply_map_mode_visibility()


func _pick_map_feature(screen_position: Vector2) -> void:
	var best_city := -1
	var best_city_distance := INF
	for city in state.cities:
		var world := _terrain.map_to_world(city.map_position)
		if _camera.is_position_behind(world):
			continue
		var distance := _camera.unproject_position(
			world + Vector3(0.0, 0.34, 0.0)
		).distance_to(screen_position)
		if distance < best_city_distance:
			best_city_distance = distance
			best_city = city.id
	if best_city_distance <= MAP_PICK_CITY_PIXELS:
		overlay.select_city(best_city)
		return
	var best_edge: Edge
	var best_edge_distance := INF
	for edge in state.edges:
		if not MapRenderer.is_edge_visible(edge):
			continue
		var samples := PackedVector3Array()
		var path := edge.map_points(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position
		)
		for path_index in range(path.size() - 1):
			var segment_samples := _draped_world_samples(
				path[path_index], path[path_index + 1], 0.125
			)
			for sample_index in range(segment_samples.size()):
				if path_index > 0 and sample_index == 0:
					continue
				samples.append(segment_samples[sample_index])
		for index in range(samples.size() - 1):
			var from := samples[index]
			var to := samples[index + 1]
			if (
				_camera.is_position_behind(from)
				or _camera.is_position_behind(to)
			):
				continue
			var distance := MapRenderer.point_to_segment_distance(
				screen_position,
				_camera.unproject_position(from),
				_camera.unproject_position(to)
			)
			if distance < best_edge_distance:
				best_edge_distance = distance
				best_edge = edge
	if (
		best_edge != null
		and best_edge_distance <= MAP_PICK_EDGE_PIXELS
	):
		overlay.select_edge(best_edge.city_a, best_edge.city_b)
		return
	var map_position := _screen_to_map_position(screen_position)
	var nation_id := MapRenderer.nation_at_map_position(state, map_position)
	if nation_id >= 0:
		overlay.select_nation(nation_id)
	else:
		overlay.clear_map_selection()


## 由相机射线迭代求与高度场的交点。先落到海平面，再按该 UV 的地形高度
## 修正数次，足以用于国家疆域拾取且不依赖额外物理碰撞体。
func _screen_to_map_position(screen_position: Vector2) -> Vector2:
	if _camera == null or _terrain == null:
		return Vector2(-1.0, -1.0)
	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_direction := _camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) <= 0.000001:
		return Vector2(-1.0, -1.0)
	var target_height := 0.0
	var map_position := Vector2(-1.0, -1.0)
	for _iteration in range(4):
		var distance := (target_height - ray_origin.y) / ray_direction.y
		if distance < 0.0:
			return Vector2(-1.0, -1.0)
		map_position = _terrain.world_to_map(
			ray_origin + ray_direction * distance
		)
		if (
			map_position.x < 0.0 or map_position.x >= 1.0
			or map_position.y < 0.0 or map_position.y >= 1.0
		):
			return Vector2(-1.0, -1.0)
		target_height = _terrain.height_at_map_position(map_position)
	return map_position


func _battle_map_position(battle: Battle) -> Vector2:
	if battle.kind == Battle.Kind.SIEGE and battle.city != null:
		return battle.city.map_position
	if battle.edge != null:
		var length := float(maxi(battle.edge.distance, 1))
		return battle.edge.map_position_at(
			clampf(battle.contact_dist_a / length, 0.0, 1.0),
			state.cities[battle.edge.city_a].map_position,
			state.cities[battle.edge.city_b].map_position,
			state.map_aspect_ratio
		)
	if not battle.side_a.is_empty():
		return overlay.army_map_position(battle.side_a[0])
	return Vector2(0.5, 0.5)


func _append_segment_ribbons(
	surface_tool: SurfaceTool,
	segments: PackedVector2Array,
	width: float,
	color: Color,
	elevation: float
) -> void:
	for index in range(0, segments.size() - 1, 2):
		_append_world_ribbon(
			surface_tool,
			segments[index],
			segments[index + 1],
			width,
			color,
			elevation
		)


func _append_world_ribbon(
	surface_tool: SurfaceTool,
	from_uv: Vector2,
	to_uv: Vector2,
	width: float,
	color: Color,
	elevation: float
) -> void:
	var from := _terrain.map_to_world(from_uv)
	var to := _terrain.map_to_world(to_uv)
	var direction := Vector2(to.x - from.x, to.z - from.z)
	if direction.length_squared() <= 0.000001:
		return
	var perpendicular := direction.normalized().orthogonal() * width
	var offset := Vector3(perpendicular.x, 0.0, perpendicular.y)
	from.y += elevation
	to.y += elevation
	var vertices := [
		from - offset,
		to - offset,
		from + offset,
		to - offset,
		to + offset,
		from + offset,
	]
	for vertex in vertices:
		surface_tool.set_color(color)
		surface_tool.add_vertex(vertex)


func _append_colored_quad(
	surface_tool: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	color: Color
) -> void:
	for vertex in [a, b, d, b, c, d]:
		surface_tool.set_color(color)
		surface_tool.add_vertex(vertex)


func _append_draped_ribbon(
	surface_tool: SurfaceTool,
	from_uv: Vector2,
	to_uv: Vector2,
	width: float,
	color: Color,
	elevation: float
) -> void:
	var samples := _draped_world_samples(
		from_uv,
		to_uv,
		elevation
	)
	for segment in range(samples.size() - 1):
		var from := samples[segment]
		var to := samples[segment + 1]
		var direction := Vector2(to.x - from.x, to.z - from.z)
		if direction.length_squared() <= 0.000001:
			continue
		var perpendicular := direction.normalized().orthogonal() * width
		var offset := Vector3(perpendicular.x, 0.0, perpendicular.y)
		for vertex in [
			from - offset,
			to - offset,
			from + offset,
			to - offset,
			to + offset,
			from + offset,
		]:
			surface_tool.set_color(color)
			surface_tool.add_vertex(vertex)


func _append_draped_path_ribbon(
	surface_tool: SurfaceTool,
	path: PackedVector2Array,
	width: float,
	color: Color,
	elevation: float
) -> void:
	for index in range(path.size() - 1):
		_append_draped_ribbon(
			surface_tool, path[index], path[index + 1],
			width, color, elevation
		)


func _draped_world_samples(
	from_uv: Vector2,
	to_uv: Vector2,
	elevation: float
) -> PackedVector3Array:
	var map_length := from_uv.distance_to(to_uv)
	var segment_count := clampi(
		int(ceil(map_length * 96.0)),
		8,
		32
	)
	var samples := PackedVector3Array()
	samples.resize(segment_count + 1)
	for index in range(segment_count + 1):
		var ratio := float(index) / float(segment_count)
		var map_position := from_uv.lerp(to_uv, ratio)
		var world := _terrain.map_to_world(map_position)
		world.y += elevation
		samples[index] = world
	return samples


func _line_material(emissive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		material.emission_enabled = true
		material.emission = Color(0.32, 0.22, 0.06)
		material.emission_energy_multiplier = 0.8
	return material


func _campaign_arrow_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# 箭头是 UI 贴图承载在 3D 曲面上，不参与场景光照。
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = CAMPAIGN_ARROW_TEXTURE
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.025
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.render_priority = 7
	return material


func _instance_color_material(
	emissive: bool,
	unshaded: bool = false
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.82
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emissive:
		material.emission_enabled = true
		material.emission = Color(0.28, 0.12, 0.025)
		material.emission_energy_multiplier = 0.55
	return material


func _configure_multimesh(
	layer: MultiMeshInstance3D,
	mesh: Mesh,
	instance_count: int,
	material: Material
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = instance_count
	layer.multimesh = multimesh
	layer.material_override = material


func _clear_labels() -> void:
	_clear_battle_labels()
	for label in _city_labels:
		if is_instance_valid(label):
			label.queue_free()
	_city_labels.clear()
	for label in _nation_labels:
		if is_instance_valid(label):
			label.queue_free()
	_nation_labels.clear()
