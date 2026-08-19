class_name StrategicTerrainRenderer
extends Node3D
## 直接采样 Copernicus 权威高度图，输出带平滑法线的 ArrayMesh，
## 并提供与逻辑地图共用的 UV -> 世界坐标/高度映射。

signal generation_finished

const TERRAIN_SHADER := preload(
	"res://scripts/view/terrain/strategic_terrain.gdshader"
)

var resolution := Vector2i(192, 128)
var world_size := Vector2(64.0, 40.0)
var height_scale: float = 7.0
var height_steps: int = 24
var smoothing_passes: int = 2

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _height_samples := PackedFloat32Array()
var _land_cell_count: int = 0


func _ready() -> void:
	_ensure_render_nodes()


func configure(
	mesh_resolution: Vector2i,
	map_world_size: Vector2,
	terrain_height_scale: float,
	terrain_height_steps: int
) -> void:
	resolution = Vector2i(
		maxi(mesh_resolution.x, 2),
		maxi(mesh_resolution.y, 2)
	)
	world_size = Vector2(
		maxf(map_world_size.x, 1.0),
		maxf(map_world_size.y, 1.0)
	)
	height_scale = maxf(terrain_height_scale, 0.1)
	height_steps = maxi(terrain_height_steps, 1)
	_ensure_render_nodes()
	_material.set_shader_parameter("height_scale", height_scale)


func set_province_texture(texture: Texture2D) -> void:
	_ensure_render_nodes()
	_material.set_shader_parameter("province_texture", texture)


func set_province_strength(strength: float) -> void:
	_ensure_render_nodes()
	_material.set_shader_parameter(
		"province_strength",
		clampf(strength, 0.0, 1.0)
	)


func set_height_texture(
	texture: Texture2D,
	source_region: Rect2
) -> void:
	_ensure_render_nodes()
	_material.set_shader_parameter("height_texture", texture)
	_material.set_shader_parameter(
		"height_source_origin",
		source_region.position
	)
	_material.set_shader_parameter(
		"height_source_size",
		source_region.size
	)


func set_surface_texture(texture: Texture2D) -> void:
	_ensure_render_nodes()
	_material.set_shader_parameter("surface_texture", texture)


func generate_from_height_texture(
	texture: Texture2D,
	source_region: Rect2,
	alpha_threshold: float,
	luma_threshold: float
) -> void:
	_reset()
	set_height_texture(texture, source_region)
	_material.set_shader_parameter(
		"land_alpha_threshold",
		alpha_threshold
	)
	if texture == null:
		generation_finished.emit()
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		generation_finished.emit()
		return
	_height_samples.resize(resolution.x * resolution.y)
	_height_samples.fill(NAN)
	_land_cell_count = 0
	var image_size := Vector2(image.get_size())
	for z in range(resolution.y):
		var v := (float(z) + 0.5) / float(resolution.y)
		for x in range(resolution.x):
			var u := (float(x) + 0.5) / float(resolution.x)
			var source_uv := (
				source_region.position
				+ Vector2(u, v) * source_region.size
			)
			var pixel_position := Vector2i(
				clampi(
					int(floor(source_uv.x * image_size.x)),
					0,
					image.get_width() - 1
				),
				clampi(
					int(floor(source_uv.y * image_size.y)),
					0,
					image.get_height() - 1
				)
			)
			var pixel := image.get_pixelv(pixel_position)
			var luminance := pixel.get_luminance()
			if (
				pixel.a < alpha_threshold
				or luminance <= luma_threshold
			):
				continue
			var altitude := (
				TerrainMapGenerator.altitude_from_luminance(
					luminance
				)
			)
			var discrete_height := clampi(
				int(round(altitude * float(height_steps))),
				0,
				height_steps
			)
			_height_samples[z * resolution.x + x] = (
				float(discrete_height)
				/ float(height_steps)
				* height_scale
			)
			_land_cell_count += 1
	_smooth_height_samples()
	_mesh_instance.mesh = _build_surface_mesh()
	generation_finished.emit()


func mesh_instance() -> MeshInstance3D:
	_ensure_render_nodes()
	return _mesh_instance


func land_cell_count() -> int:
	return _land_cell_count


func map_to_world(map_position: Vector2) -> Vector3:
	var uv := Vector2(
		clampf(map_position.x, 0.0, 1.0),
		clampf(map_position.y, 0.0, 1.0)
	)
	return Vector3(
		(uv.x - 0.5) * world_size.x,
		height_at_map_position(uv),
		(uv.y - 0.5) * world_size.y
	)


func world_to_map(world_position: Vector3) -> Vector2:
	return Vector2(
		world_position.x / world_size.x + 0.5,
		world_position.z / world_size.y + 0.5
	)


func height_at_map_position(map_position: Vector2) -> float:
	if _height_samples.size() != resolution.x * resolution.y:
		return 0.0
	var sample_x := clampf(
		map_position.x,
		0.0,
		1.0
	) * float(resolution.x - 1)
	var sample_z := clampf(
		map_position.y,
		0.0,
		1.0
	) * float(resolution.y - 1)
	var x0 := clampi(int(floor(sample_x)), 0, resolution.x - 1)
	var z0 := clampi(int(floor(sample_z)), 0, resolution.y - 1)
	var x1 := mini(x0 + 1, resolution.x - 1)
	var z1 := mini(z0 + 1, resolution.y - 1)
	var h00 := _sample_height(x0, z0)
	var h10 := _sample_height(x1, z0)
	var h01 := _sample_height(x0, z1)
	var h11 := _sample_height(x1, z1)
	if (
		not is_nan(h00)
		and not is_nan(h10)
		and not is_nan(h01)
		and not is_nan(h11)
	):
		var tx := sample_x - float(x0)
		var tz := sample_z - float(z0)
		return lerpf(
			lerpf(h00, h10, tx),
			lerpf(h01, h11, tx),
			tz
		)
	for radius in range(1, 5):
		for z in range(
			maxi(z0 - radius, 0),
			mini(z0 + radius + 1, resolution.y)
		):
			for x in range(
				maxi(x0 - radius, 0),
				mini(x0 + radius + 1, resolution.x)
			):
				var nearby := _sample_height(x, z)
				if not is_nan(nearby):
					return nearby
	return 0.0


func _reset() -> void:
	_ensure_render_nodes()
	_mesh_instance.mesh = null
	_height_samples = PackedFloat32Array()
	_land_cell_count = 0


func _ensure_render_nodes() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		add_child(_mesh_instance)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = TERRAIN_SHADER
		_material.set_shader_parameter(
			"height_scale",
			height_scale
		)
	_mesh_instance.material_override = _material


func _build_surface_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(resolution.y):
		for x in range(resolution.x):
			var uv := Vector2(
				float(x) / float(resolution.x - 1),
				float(z) / float(resolution.y - 1)
			)
			var height := _sample_height(x, z)
			surface_tool.set_uv(uv)
			surface_tool.add_vertex(Vector3(
				(uv.x - 0.5) * world_size.x,
				_mesh_vertex_height(x, z)
					if is_nan(height)
					else height,
				(uv.y - 0.5) * world_size.y
			))
	for z in range(resolution.y - 1):
		for x in range(resolution.x - 1):
			var i00 := z * resolution.x + x
			var i10 := i00 + 1
			var i01 := i00 + resolution.x
			var i11 := i01 + 1
			surface_tool.add_index(i00)
			surface_tool.add_index(i10)
			surface_tool.add_index(i01)
			surface_tool.add_index(i10)
			surface_tool.add_index(i11)
			surface_tool.add_index(i01)
	surface_tool.generate_normals()
	return surface_tool.commit()


func _mesh_vertex_height(x: int, z: int) -> float:
	# Sea vertices remain in the rectangular mesh. Near the coast they inherit
	# the closest land height so the high-resolution alpha mask cuts a vertical
	# seam instead of exposing low-resolution grid steps.
	for radius in range(1, 5):
		for sample_z in range(
			maxi(z - radius, 0),
			mini(z + radius + 1, resolution.y)
		):
			for sample_x in range(
				maxi(x - radius, 0),
				mini(x + radius + 1, resolution.x)
			):
				var nearby := _sample_height(sample_x, sample_z)
				if not is_nan(nearby):
					return nearby
	return 0.0


func _sample_height(x: int, z: int) -> float:
	if (
		x < 0
		or z < 0
		or x >= resolution.x
		or z >= resolution.y
		or _height_samples.size()
			!= resolution.x * resolution.y
	):
		return NAN
	return _height_samples[z * resolution.x + x]


func _smooth_height_samples() -> void:
	for _pass in range(smoothing_passes):
		var source := _height_samples.duplicate()
		for z in range(resolution.y):
			for x in range(resolution.x):
				var index := z * resolution.x + x
				if is_nan(source[index]):
					continue
				var total := source[index] * 4.0
				var weight := 4.0
				for offset in [
					Vector2i.LEFT,
					Vector2i.RIGHT,
					Vector2i.UP,
					Vector2i.DOWN,
					Vector2i(-1, -1),
					Vector2i(1, -1),
					Vector2i(-1, 1),
					Vector2i(1, 1),
				]:
					var sample_x: int = x + offset.x
					var sample_z: int = z + offset.y
					if (
						sample_x < 0
						or sample_z < 0
						or sample_x >= resolution.x
						or sample_z >= resolution.y
					):
						continue
					var nearby := source[
						sample_z * resolution.x + sample_x
					]
					if is_nan(nearby):
						continue
					var sample_weight := (
						1.0
						if offset.x == 0 or offset.y == 0
						else 0.7
					)
					total += nearby * sample_weight
					weight += sample_weight
				_height_samples[index] = total / weight
