class_name StrategicMap3D
extends Node3D
## 3D 战略地图表现层。Gaea 负责从权威高度图生成确定性高度网格，本节点
## 负责连续地形、国家覆色、道路、河流、城市、军队、战斗和相机交互。

const BASE_WORLD_SPAN: float = 64.0
const BASE_MESH_RESOLUTION: int = 192
const HEIGHT_STEPS: int = 28
const HEIGHT_SCALE: float = 4.8
const MAP_PICK_CITY_PIXELS: float = 18.0
const MAP_PICK_EDGE_PIXELS: float = 10.0
const CAMERA_MIN_DISTANCE: float = 24.0
const CAMERA_MAX_DISTANCE: float = 92.0
const CAMERA_DRAG_THRESHOLD: float = 4.0

var state: GameState
var sim: Simulation
var overlay: MapRenderer

var _generator: GaeaGenerator
var _terrain: StrategicTerrainRenderer
var _camera: Camera3D
var _content: Node3D
var _water: MeshInstance3D
var _roads: MeshInstance3D
var _rivers: MeshInstance3D
var _boundaries: MeshInstance3D
var _campaigns: MeshInstance3D
var _cities: MultiMeshInstance3D
var _armies: MultiMeshInstance3D
var _battles: MultiMeshInstance3D
var _selection: MeshInstance3D
var _city_labels: Array[Label3D] = []
var _province_texture: ImageTexture

var _world_size := Vector2(BASE_WORLD_SPAN, BASE_WORLD_SPAN)
var _mesh_resolution := Vector2i(
	BASE_MESH_RESOLUTION,
	BASE_MESH_RESOLUTION
)
var _camera_target := Vector3.ZERO
var _camera_distance: float = 56.0
var _drag_active: bool = false
var _drag_moved: bool = false
var _drag_start := Vector2.ZERO
var _drag_target_start := Vector3.ZERO
var _last_day: int = -1
var _last_ownership_revision: int = -1
var _last_diplomacy_revision: int = -1


func setup(
	game_state: GameState,
	simulation: Simulation,
	overlay_renderer: MapRenderer
) -> void:
	state = game_state
	sim = simulation
	overlay = overlay_renderer
	_ensure_scene_nodes()
	_clear_labels()
	_configure_dimensions()
	_configure_camera()
	_build_static_scene()
	_start_gaea_generation()
	_last_day = -1
	_last_ownership_revision = -1
	_last_diplomacy_revision = -1
	set_process(true)
	set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	if state == null or _terrain == null:
		return
	if (
		state.ownership_revision != _last_ownership_revision
		or state.diplomacy_revision
			!= _last_diplomacy_revision
	):
		_update_province_visuals()
		_update_city_instances()
		_last_ownership_revision = state.ownership_revision
		_last_diplomacy_revision = state.diplomacy_revision
	if state.day != _last_day:
		_update_campaign_mesh()
		_update_battle_instances()
		_last_day = state.day
	_update_army_instances()
	_update_selection_marker()
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
		sun.light_color = Color(1.0, 0.91, 0.76)
		sun.light_energy = 1.45
		sun.shadow_enabled = true
		add_child(sun)
	if get_node_or_null("Environment") == null:
		var world_environment := WorldEnvironment.new()
		world_environment.name = "Environment"
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.035, 0.055, 0.065)
		environment.background_energy_multiplier = 0.75
		environment.ambient_light_source = (
			Environment.AMBIENT_SOURCE_COLOR
		)
		environment.ambient_light_color = Color(
			0.42,
			0.48,
			0.52
		)
		environment.ambient_light_energy = 0.72
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		world_environment.environment = environment
		add_child(world_environment)
	_ensure_feature_nodes()


func _ensure_feature_nodes() -> void:
	if _water == null:
		_water = MeshInstance3D.new()
		_water.name = "Water"
		_content.add_child(_water)
	if _roads == null:
		_roads = MeshInstance3D.new()
		_roads.name = "Roads"
		_content.add_child(_roads)
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
	if _armies == null:
		_armies = MultiMeshInstance3D.new()
		_armies.name = "Armies"
		_content.add_child(_armies)
	if _battles == null:
		_battles = MultiMeshInstance3D.new()
		_battles.name = "Battles"
		_content.add_child(_battles)
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
		material.albedo_color = Color(1.0, 0.72, 0.18)
		material.emission_enabled = true
		material.emission = Color(0.72, 0.26, 0.02)
		material.emission_energy_multiplier = 2.0
		_selection.material_override = material
		_selection.visible = false
		_content.add_child(_selection)


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
		maxf(_world_size.x, _world_size.y) * 0.92,
		CAMERA_MIN_DISTANCE,
		CAMERA_MAX_DISTANCE
	)
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	_camera.position = _camera_target + Vector3(
		0.0,
		_camera_distance * 0.78,
		_camera_distance * 0.62
	)
	_camera.look_at(
		_camera_target + Vector3(0.0, HEIGHT_SCALE * 0.18, 0.0),
		Vector3.UP
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
	water_plane.size = _world_size * 1.28
	_water.mesh = water_plane
	_water.position.y = -0.42
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.055, 0.16, 0.20)
	water_material.roughness = 0.38
	water_material.metallic = 0.08
	_water.material_override = water_material


func _start_gaea_generation() -> void:
	if _generator != null:
		_generator.cancel_generation()
		_generator.queue_free()
		_generator = null
	if _terrain != null:
		_terrain.queue_free()
		_terrain = null

	_generator = GaeaGenerator.new()
	_generator.name = "GaeaHeightGenerator"
	add_child(_generator)
	_terrain = StrategicTerrainRenderer.new()
	_terrain.name = "StrategicTerrainRenderer"
	add_child(_terrain)
	_terrain.generator = _generator
	_terrain.configure(
		_mesh_resolution,
		_world_size,
		HEIGHT_SCALE,
		HEIGHT_STEPS
	)
	_terrain.render_finished.connect(_on_terrain_ready)

	var graph := GaeaGraph.new()
	graph.ensure_initialized()
	var source := StrategicHeightmapNode.new()
	source.arguments = {
		&"texture": load(GameState.TERRAIN_MAP_PATH) as Texture2D,
		&"source_origin": state.map_source_region_normalized.position,
		&"source_size": state.map_source_region_normalized.size,
		&"resolution": _mesh_resolution,
		&"height_steps": HEIGHT_STEPS,
		&"alpha_threshold": TerrainMapGenerator.ALPHA_THRESHOLD,
		&"luma_threshold": TerrainMapGenerator.LUMA_THRESHOLD,
	}
	var source_id := graph.add_node(source, Vector2(-240.0, 0.0))
	var output := graph.get_output_node()
	var connection_error := graph.connect_nodes(
		source_id,
		0,
		output.id,
		0
	)
	assert(
		connection_error == OK,
		"无法连接 Gaea 战略高度图节点"
	)
	var settings := GaeaGenerationSettings.new()
	settings.random_seed_on_generate = false
	settings.seed = 0
	settings.world_size = Vector3i(
		_mesh_resolution.x,
		HEIGHT_STEPS + 1,
		_mesh_resolution.y
	)
	_generator.graph = graph
	_generator.settings = settings
	_generator.generate()


func _on_terrain_ready() -> void:
	if _terrain.land_cell_count() <= 0:
		push_error("Gaea 3D 地形为空")
		return
	_update_province_visuals()
	_build_road_mesh()
	_build_river_mesh()
	_build_city_instances()
	_update_city_instances()
	_update_army_instances()
	_update_battle_instances()
	_update_campaign_mesh()


func _update_province_visuals() -> void:
	if _terrain == null or _terrain.land_cell_count() <= 0:
		return
	var image := MapRenderer.build_province_overlay_image(state)
	if image != null and not image.is_empty():
		_province_texture = ImageTexture.create_from_image(image)
		_terrain.set_province_texture(_province_texture)
	var geometry := MapRenderer.build_province_boundary_segments(state)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_segment_ribbons(
		surface_tool,
		geometry["coast"],
		0.16,
		Color(0.04, 0.035, 0.025),
		0.10
	)
	_append_segment_ribbons(
		surface_tool,
		geometry["province"],
		0.045,
		Color(0.08, 0.07, 0.05, 0.46),
		0.12
	)
	_append_segment_ribbons(
		surface_tool,
		geometry["nation"],
		0.17,
		Color(0.95, 0.66, 0.18),
		0.15
	)
	_append_segment_ribbons(
		surface_tool,
		geometry["alliance"],
		0.11,
		Color(0.16, 0.72, 0.76),
		0.17
	)
	_boundaries.mesh = surface_tool.commit()
	_boundaries.material_override = _line_material(true)


func _build_road_mesh() -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in state.edges:
		if not MapRenderer.is_edge_visible(edge):
			continue
		var from := state.cities[edge.city_a].map_position
		var to := state.cities[edge.city_b].map_position
		var color := Color(0.18, 0.14, 0.09)
		var width := 0.055 + (
			float(edge.max_manpower) / float(Edge.MAX_MANPOWER)
		) * 0.13
		if edge.kind == Edge.Kind.LANDING:
			color = Color(0.56, 0.42, 0.20)
		elif edge.kind == Edge.Kind.RIVER:
			color = Color(0.10, 0.36, 0.52)
			width = 0.14
		_append_world_ribbon(
			surface_tool,
			from,
			to,
			width,
			color,
			0.20
		)
	_roads.mesh = surface_tool.commit()
	_roads.material_override = _line_material(false)


func _build_river_mesh() -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for river in state.river_paths:
		for index in range(river.size() - 1):
			_append_world_ribbon(
				surface_tool,
				river[index],
				river[index + 1],
				0.18,
				Color(0.08, 0.44, 0.62),
				0.14
			)
	_rivers.mesh = surface_tool.commit()
	_rivers.material_override = _line_material(false)


func _build_city_instances() -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.instance_count = state.cities.size()
	var marker := CylinderMesh.new()
	marker.top_radius = 0.24
	marker.bottom_radius = 0.34
	marker.height = 0.42
	marker.radial_segments = 10
	multimesh.mesh = marker
	_cities.multimesh = multimesh
	_cities.material_override = _instance_color_material(false)
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
		label.font_size = 30
		label.outline_size = 7
		label.pixel_size = 0.016
		label.modulate = Color(0.95, 0.90, 0.76)
		label.outline_modulate = Color(0.025, 0.025, 0.02, 0.92)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = (
			_terrain.map_to_world(city.map_position)
			+ Vector3(0.0, 0.92, 0.0)
		)
		_content.add_child(label)
		_city_labels.append(label)


func _update_city_instances() -> void:
	if _cities.multimesh == null:
		return
	for city in state.cities:
		var world := _terrain.map_to_world(city.map_position)
		var scale := (
			1.35
			if city.is_capital
			else 0.58 if city.is_dock else 0.78
		)
		var basis := Basis.IDENTITY.scaled(
			Vector3(scale, scale, scale)
		)
		_cities.multimesh.set_instance_transform(
			city.id,
			Transform3D(
				basis,
				world + Vector3(0.0, 0.34 * scale, 0.0)
			)
		)
		var color := (
			state.nations[city.owner_nation].color
			if city.owner_nation >= 0
			else Color(0.45, 0.45, 0.42)
		)
		if city.is_capital:
			color = color.lightened(0.24)
		_cities.multimesh.set_instance_color(city.id, color)


func _update_army_instances() -> void:
	if _terrain == null or _terrain.land_cell_count() <= 0:
		return
	var living: Array[Army] = []
	for army in state.armies:
		if army.size > 0:
			living.append(army)
	if _armies.multimesh == null:
		var marker := BoxMesh.new()
		marker.size = Vector3(0.72, 0.18, 0.44)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = marker
		_armies.multimesh = multimesh
		_armies.material_override = _instance_color_material(false)
	_armies.multimesh.instance_count = living.size()
	for index in range(living.size()):
		var army := living[index]
		var map_position := overlay.army_map_position(army)
		var world := _terrain.map_to_world(map_position)
		var angle := float(army.id % 11) / 11.0 * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.30
		var scale := (
			0.92
			if army.max_size >= Army.DEFAULT_MAX_SIZE
			else 0.64
		)
		_armies.multimesh.set_instance_transform(
			index,
			Transform3D(
				Basis.IDENTITY.scaled(
					Vector3(scale, scale, scale)
				),
				world + offset + Vector3(0.0, 0.92, 0.0)
			)
		)
		var color := state.nations[army.owner_nation].color
		if army.starving:
			color = color.lerp(Color(0.86, 0.16, 0.08), 0.72)
		elif army.state == Army.State.FIGHTING:
			color = color.lightened(0.28)
		_armies.multimesh.set_instance_color(index, color)


func _update_battle_instances() -> void:
	var active: Array[Battle] = []
	for battle in state.battles:
		if not battle.finished:
			active.append(battle)
	if _battles.multimesh == null:
		var marker := SphereMesh.new()
		marker.radius = 0.32
		marker.height = 0.64
		marker.radial_segments = 12
		marker.rings = 6
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = marker
		_battles.multimesh = multimesh
		_battles.material_override = _instance_color_material(true)
	_battles.multimesh.instance_count = active.size()
	for index in range(active.size()):
		var battle := active[index]
		var map_position := _battle_map_position(battle)
		var world := _terrain.map_to_world(map_position)
		_battles.multimesh.set_instance_transform(
			index,
			Transform3D(
				Basis.IDENTITY,
				world + Vector3(0.0, 1.5, 0.0)
			)
		)
		_battles.multimesh.set_instance_color(
			index,
			Color(0.92, 0.14, 0.06)
		)


func _update_campaign_mesh() -> void:
	if _terrain == null or _terrain.land_cell_count() <= 0:
		return
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for event in state.campaign_visual_events:
		if MapRenderer.campaign_arrow_alpha(state.day, event) <= 0.0:
			continue
		var target_id := int(event.get("target_city", -1))
		if target_id < 0 or target_id >= state.cities.size():
			continue
		var target := state.cities[target_id].map_position
		var nation_id := int(event.get("nation_id", -1))
		var color := (
			state.nations[nation_id].color.lightened(0.25)
			if nation_id >= 0 and nation_id < state.nations.size()
			else Color(0.94, 0.58, 0.16)
		)
		for origin_id in event.get("origin_cities", []):
			if origin_id < 0 or origin_id >= state.cities.size():
				continue
			_append_world_ribbon(
				surface_tool,
				state.cities[origin_id].map_position,
				target,
				0.24,
				color,
				0.42
			)
	_campaigns.mesh = surface_tool.commit()
	_campaigns.material_override = _line_material(true)


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
		_selection.visible = true
		return
	_selection.visible = false


func _update_city_label_visibility() -> void:
	if overlay == null:
		return
	var visible := overlay.city_names_visible()
	for label in _city_labels:
		label.visible = visible


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
		var from := _terrain.map_to_world(
			state.cities[edge.city_a].map_position
		)
		var to := _terrain.map_to_world(
			state.cities[edge.city_b].map_position
		)
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


func _instance_color_material(
	emissive: bool
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.82
	if emissive:
		material.emission_enabled = true
		material.emission = Color(0.45, 0.04, 0.01)
		material.emission_energy_multiplier = 1.3
	return material


func _clear_labels() -> void:
	for label in _city_labels:
		if is_instance_valid(label):
			label.queue_free()
	_city_labels.clear()
