class_name StrategicMap3D
extends Node3D
## 3D 战略地图表现层。Renderer 直接从 Copernicus 高度图生成确定性网格，本节点
## 负责连续地形、国家覆色、道路、河流、城市、军队、战斗和相机交互。

const BASE_WORLD_SPAN: float = 64.0
const BASE_MESH_RESOLUTION: int = 256
const HEIGHT_STEPS: int = 64
const HEIGHT_SCALE: float = 4.8
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
const CAMPAIGN_ARROW_TEXTURE := MapRenderer.CAMPAIGN_ARROW_TEXTURE
const CAMPAIGN_ARROW_GRID := Vector2i(24, 16)
const ANTIQUE_OVERLAY_SHADER := preload(
	"res://scripts/view/terrain/antique_overlay.gdshader"
)
const WATER_SHADER := preload(
	"res://scripts/view/terrain/strategic_water.gdshader"
)
const POLITICAL_BOUNDARY_SHADER := preload(
	"res://scripts/view/terrain/political_boundaries.gdshader"
)

var state: GameState
var sim: Simulation
var overlay: MapRenderer

var _terrain: StrategicTerrainRenderer
var _camera: Camera3D
var _content: Node3D
var _water: MeshInstance3D
var _roads: MeshInstance3D
var _minor_roads: MeshInstance3D
var _rivers: MeshInstance3D
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
var _map_font: Font

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
var _last_road_network_revision: int = -1
var _last_selected_edge := Vector2i(-2, -2)
var _province_strength: float = (
	MapRenderer.POLITICAL_MAP_DEFAULT_STRENGTH
)
var _elevation_shadow_strength: float = 0.62
var _visual_time: float = 0.0


func setup(
	game_state: GameState,
	simulation: Simulation,
	overlay_renderer: MapRenderer
) -> void:
	state = game_state
	sim = simulation
	overlay = overlay_renderer
	if _map_font == null:
		_map_font = MapRenderer.create_map_label_font()
	_ensure_scene_nodes()
	_clear_labels()
	_configure_dimensions()
	_configure_camera()
	_build_static_scene()
	_start_terrain_generation()
	_last_day = -1
	_last_ownership_revision = -1
	_last_diplomacy_revision = -1
	_last_road_network_revision = -1
	set_process(true)
	set_process_unhandled_input(true)


func _process(delta: float) -> void:
	if state == null or _terrain == null:
		return
	_visual_time += delta
	if (
		state.ownership_revision != _last_ownership_revision
		or state.diplomacy_revision
			!= _last_diplomacy_revision
	):
		_update_province_visuals()
		_update_city_instances()
		_rebuild_nation_labels()
		_last_ownership_revision = state.ownership_revision
		_last_diplomacy_revision = state.diplomacy_revision
	if state.day != _last_day:
		_update_campaign_mesh()
		_update_battle_instances()
		_last_day = state.day
	if (
		state.road_network_revision
		!= _last_road_network_revision
		and _terrain.land_cell_count() > 0
	):
		_build_road_mesh()
		_last_road_network_revision = state.road_network_revision
	_update_army_instances()
	_update_selection_marker()
	_update_edge_selection()
	_update_city_label_visibility()


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
	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
		sun.light_color = Color(1.0, 0.87, 0.68)
		sun.light_energy = 1.12
		sun.shadow_enabled = true
		add_child(sun)
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
		environment.ambient_light_color = Color(
			0.58,
			0.52,
			0.42
		)
		environment.ambient_light_energy = 0.64
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		world_environment.environment = environment
		add_child(world_environment)
	_ensure_feature_nodes()
	_ensure_antique_overlay()


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
	if aspect >= 1.0:
		_world_size = Vector2(
			BASE_WORLD_SPAN,
			BASE_WORLD_SPAN / aspect
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
			BASE_WORLD_SPAN * aspect,
			BASE_WORLD_SPAN
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
		CAMERA_MAX_DISTANCE
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
		CAMERA_MAX_DISTANCE
	)
	_apply_camera_transform()


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
	_terrain.set_province_strength(_province_strength)
	_terrain.set_elevation_shadow_strength(_elevation_shadow_strength)
	_build_road_mesh()
	_build_river_mesh()
	_build_city_instances()
	_update_city_instances()
	_update_army_instances()
	_update_battle_instances()
	_update_campaign_mesh()
	_rebuild_nation_labels()
	_last_road_network_revision = state.road_network_revision


func set_province_strength(strength: float) -> void:
	_province_strength = clampf(strength, 0.0, 1.0)
	if _terrain != null:
		_terrain.set_province_strength(_province_strength)


func set_elevation_shadow_strength(strength: float) -> void:
	_elevation_shadow_strength = clampf(strength, 0.0, 1.0)
	if _terrain != null:
		_terrain.set_elevation_shadow_strength(
			_elevation_shadow_strength
		)


func _update_province_visuals() -> void:
	if _terrain == null or _terrain.land_cell_count() <= 0:
		return
	var image := MapRenderer.build_smooth_province_overlay_image(state)
	if image != null and not image.is_empty():
		_province_texture = ImageTexture.create_from_image(image)
		_terrain.set_province_texture(_province_texture)
	var geometry := MapRenderer.build_province_boundary_segments(state)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_segment_ribbons(
		surface_tool,
		geometry["province"],
		0.026,
		Color(0.1, 0.12, 0.12, 1.00),
		0.205
	)
	_append_segment_ribbons(
		surface_tool,
		geometry["coast"],
		0.026,
		Color(0.075, 0.085, 0.088, 1.0),
		0.207
	)
	_append_segment_ribbons(
		surface_tool,
		geometry["nation"],
		0.070,
		MapRenderer.BORDER_NEUTRAL,
		0.215
	)
	_append_segment_ribbons(
		surface_tool,
		geometry["alliance"],
		0.070,
		MapRenderer.BORDER_ALLIED,
		0.225
	)
	_append_segment_ribbons(
		surface_tool, geometry["enemy"], 0.078,
		MapRenderer.BORDER_ENEMY, 0.228
	)
	_append_segment_ribbons(
		surface_tool,
		geometry["suzerainty"],
		0.060,
		MapRenderer.BORDER_SUZERAINTY,
		0.230
	)
	_boundaries.mesh = surface_tool.commit()
	_boundaries.material_override = _political_boundary_material()


func _build_road_mesh() -> void:
	var major_tool := SurfaceTool.new()
	major_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var minor_tool := SurfaceTool.new()
	minor_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in state.edges:
		if not MapRenderer.is_edge_visible(edge):
			continue
		var from := state.cities[edge.city_a].map_position
		var to := state.cities[edge.city_b].map_position
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
		_append_draped_ribbon(
			surface_tool,
			from,
			to,
			width * 1.58,
			Color(0.055, 0.038, 0.022, 0.54),
			0.105
		)
		_append_draped_ribbon(
			surface_tool,
			from,
			to,
			width,
			color,
			0.125
		)
	_roads.mesh = major_tool.commit()
	_roads.material_override = _line_material(false)
	_minor_roads.mesh = minor_tool.commit()
	_minor_roads.material_override = _line_material(false)
	_update_map_detail_visibility()


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
	_clear_labels()
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
		label.text = MapRenderer.city_label_text(city)
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
			MapRenderer.final_faction_visual_color(
				state, city.owner_nation,
				0.34 if city.at_war else 0.0,
				0.08 if city.is_capital else 0.0
			)
			if city.owner_nation >= 0
			else Color(0.45, 0.45, 0.42)
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
	for label in _nation_labels:
		if is_instance_valid(label):
			label.queue_free()
	_nation_labels.clear()
	for nation in state.nations:
		if not nation.alive:
			continue
		var layout := _nation_label_layout(nation.id)
		if layout.is_empty():
			continue
		var text_value := str(layout["text"])
		var center: Vector2 = layout["center"]
		var axis: Vector2 = layout["axis"]
		var glyph_scale := float(layout["glyph_scale"])
		var label := Label3D.new()
		label.text = text_value
		label.font = _map_font
		label.font_size = 84
		label.outline_size = 3
		label.pixel_size = 0.026 * glyph_scale
		label.modulate = Color(0.075, 0.078, 0.082, 0.86)
		label.outline_modulate = Color(0.62, 0.60, 0.54, 0.18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = true
		label.render_priority = 8
		var local_x := Vector3(axis.x, 0.0, axis.y)
		var local_y := Vector3(axis.y, 0.0, -axis.x)
		label.basis = Basis(local_x, local_y, Vector3.UP)
		label.position = (
			_terrain.map_to_world(center)
			+ Vector3(0.0, 0.34, 0.0)
		)
		_content.add_child(label)
		_nation_labels.append(label)


func _nation_label_layout(nation_id: int) -> Dictionary:
	var points := PackedVector2Array()
	var center := Vector2.ZERO
	for city in state.cities:
		if city.owner_nation != nation_id or city.is_dock:
			continue
		var metric := Vector2(
			city.map_position.x * _world_size.x,
			city.map_position.y * _world_size.y
		)
		points.append(metric)
		center += metric
	if points.is_empty():
		return {}
	center /= float(points.size())
	var covariance_xx := 0.0
	var covariance_xy := 0.0
	var covariance_yy := 0.0
	for point in points:
		var delta := point - center
		covariance_xx += delta.x * delta.x
		covariance_xy += delta.x * delta.y
		covariance_yy += delta.y * delta.y
	var axis_angle := 0.5 * atan2(
		2.0 * covariance_xy, covariance_xx - covariance_yy
	)
	var axis := Vector2(cos(axis_angle), sin(axis_angle)).normalized()
	if axis.x < 0.0:
		axis = -axis
	var projection_min := INF
	var projection_max := -INF
	for point in points:
		var projection := (point - center).dot(axis)
		projection_min = minf(projection_min, projection)
		projection_max = maxf(projection_max, projection)
	var territory_span := maxf(projection_max - projection_min, 2.0)
	var text_value := "国%d" % nation_id
	return {
		"text": text_value,
		"center": Vector2(
			center.x / _world_size.x, center.y / _world_size.y
		),
		"axis": axis,
		"territory_span": territory_span,
		"glyph_scale": clampf(
			pow(territory_span / 8.0, 0.76), 1.10, 3.10
		),
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
	for layer in [
		_army_bases, _armies, _army_symbol_a, _army_symbol_b,
		_army_morale_backs, _army_morale_bars,
	]:
		layer.multimesh.instance_count = living.size()
	for index in range(living.size()):
		var army := living[index]
		var map_position := overlay.army_map_position(army)
		var world := _terrain.map_to_world(map_position)
		var angle := float(army.id % 11) / 11.0 * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.34
		var scale := overlay.army_icon_scale() * (
			1.02
			if army.max_size >= Army.DEFAULT_MAX_SIZE
			else 0.78
		)
		var origin := world + offset + Vector3(0.0, 0.82, 0.0)
		_set_counter_transform(
			_army_bases, index, origin, scale, Vector3(1.12, 1.0, 1.12)
		)
		_set_counter_transform(
			_armies, index, origin + Vector3(0.0, 0.10, 0.0),
			scale, Vector3.ONE
		)
		var is_heavy := army.max_size >= Army.DEFAULT_MAX_SIZE
		var first_angle := 0.0 if is_heavy else PI * 0.25
		var symbol_basis := Basis(Vector3.UP, first_angle).scaled(
			Vector3(scale, scale, scale)
		)
		var symbol_origin := origin + Vector3(0.0, 0.225, 0.0)
		_army_symbol_a.multimesh.set_instance_transform(
			index, Transform3D(symbol_basis, symbol_origin)
		)
		var second_angle := (
			PI * 0.5 if is_heavy else -PI * 0.25
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
		var morale_ratio := army.morale_ratio()
		_set_morale_bar_transform(
			_army_morale_bars, index, origin, scale, morale_ratio
		)
		var color := MapRenderer.final_faction_visual_color(
			state, army.owner_nation,
			0.62 if army.starving else 0.0,
			0.06 if army.state == Army.State.FIGHTING else 0.0
		)
		_army_bases.multimesh.set_instance_color(index, MAP_INK)
		_armies.multimesh.set_instance_color(index, color)
		_army_symbol_a.multimesh.set_instance_color(
			index, MAP_COUNTER_MARK
		)
		_army_symbol_b.multimesh.set_instance_color(
			index, MAP_COUNTER_MARK
		)
		_army_morale_backs.multimesh.set_instance_color(index, MAP_INK)
		_army_morale_bars.multimesh.set_instance_color(
			index, _morale_color(morale_ratio, army.starving)
		)


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
	_clear_battle_labels()
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
		_add_battle_label(battle, origin)


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


func _add_battle_label(battle: Battle, origin: Vector3) -> void:
	var label := Label3D.new()
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
	label.font = _map_font
	label.font_size = 25
	label.outline_size = 8
	label.pixel_size = 0.0125
	label.modulate = MAP_IVORY
	label.outline_modulate = MAP_INK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = origin + Vector3(0.0, 0.86, 0.0)
	_content.add_child(label)
	_battle_labels.append(label)


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
			_append_campaign_texture_triangle(surface_tool, uv00, uv10, uv01, source_size, from_metric, scale, rotation, alpha)
			_append_campaign_texture_triangle(surface_tool, uv10, uv11, uv01, source_size, from_metric, scale, rotation, alpha)


func _append_campaign_texture_triangle(
	surface_tool: SurfaceTool,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2,
	source_size: Vector2, from_metric: Vector2,
	scale: float, rotation: float, alpha: float
) -> void:
	for uv in [uv_a, uv_b, uv_c]:
		var typed_uv: Vector2 = uv
		var source_point: Vector2 = typed_uv * source_size
		var metric_offset: Vector2 = (
			(source_point - MapRenderer.CAMPAIGN_ARROW_SOURCE_TAIL)
			.rotated(rotation) * scale
		)
		var metric_point: Vector2 = from_metric + metric_offset
		var map_point := Vector2(metric_point.x / _world_size.x, metric_point.y / _world_size.y)
		var world := _terrain.map_to_world(map_point)
		world.y += 0.43
		surface_tool.set_uv(typed_uv)
		surface_tool.set_color(Color(1.0, 1.0, 1.0, 0.94 * alpha))
		surface_tool.add_vertex(world)


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
	_append_draped_ribbon(
		surface_tool,
		state.cities[edge.city_a].map_position,
		state.cities[edge.city_b].map_position,
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
	for label in _city_labels:
		label.visible = visible and _camera_distance <= 40.0
	for label in _nation_labels:
		label.visible = _camera_distance >= 56.0
	for label in _battle_labels:
		label.visible = _camera_distance <= 50.0
	if _minor_roads != null:
		_minor_roads.visible = _camera_distance <= 62.0


func _pick_map_feature(screen_position: Vector2) -> void:
	var best_city := -1
	var best_city_distance := INF
	for city in state.cities:
		if city.is_dock:
			continue
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
		var samples := _draped_world_samples(
			state.cities[edge.city_a].map_position,
			state.cities[edge.city_b].map_position,
			0.125
		)
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
	overlay.clear_map_selection()


func _battle_map_position(battle: Battle) -> Vector2:
	if battle.kind == Battle.Kind.SIEGE and battle.city != null:
		return battle.city.map_position
	if battle.edge != null:
		var length := float(maxi(battle.edge.distance, 1))
		return state.cities[battle.edge.city_a].map_position.lerp(
			state.cities[battle.edge.city_b].map_position,
			clampf(battle.contact_dist_a / length, 0.0, 1.0)
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


func _political_boundary_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = POLITICAL_BOUNDARY_SHADER
	material.render_priority = 4
	return material


func _campaign_arrow_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = CAMPAIGN_ARROW_TEXTURE
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.025
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
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
