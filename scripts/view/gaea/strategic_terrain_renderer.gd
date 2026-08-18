@tool
class_name StrategicTerrainRenderer
extends GaeaRenderer
## Gaea 自定义连续地形 Renderer：消费高度单元 Map，输出带平滑法线的
## ArrayMesh，并提供与逻辑地图共用的 UV -> 世界坐标/高度映射。

const TERRAIN_SHADER := preload(
	"res://scripts/view/gaea/strategic_terrain.gdshader"
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
	super()
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


func _render(grid: GaeaGrid) -> void:
	_ensure_render_nodes()
	var surface := grid.get_layer(0) as GaeaValue.Map
	_height_samples.resize(resolution.x * resolution.y)
	_height_samples.fill(NAN)
	_land_cell_count = 0
	if surface == null:
		_mesh_instance.mesh = null
		return
	for cell in surface.get_cells():
		if (
			cell.x < 0
			or cell.z < 0
			or cell.x >= resolution.x
			or cell.z >= resolution.y
		):
			continue
		_height_samples[cell.z * resolution.x + cell.x] = (
			float(cell.y) / float(height_steps) * height_scale
		)
		_land_cell_count += 1
	_smooth_height_samples()
	_mesh_instance.mesh = _build_surface_mesh()


func _erase_area(_area: AABB) -> void:
	_reset()


func _reset() -> void:
	_ensure_render_nodes()
	_mesh_instance.mesh = null
	_height_samples = PackedFloat32Array()
	_land_cell_count = 0


func _ensure_render_nodes() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "GaeaTerrainMesh"
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
				0.0 if is_nan(height) else height,
				(uv.y - 0.5) * world_size.y
			))
	for z in range(resolution.y - 1):
		for x in range(resolution.x - 1):
			var i00 := z * resolution.x + x
			var i10 := i00 + 1
			var i01 := i00 + resolution.x
			var i11 := i01 + 1
			if (
				is_nan(_height_samples[i00])
				or is_nan(_height_samples[i10])
				or is_nan(_height_samples[i01])
				or is_nan(_height_samples[i11])
			):
				continue
			surface_tool.add_index(i00)
			surface_tool.add_index(i10)
			surface_tool.add_index(i01)
			surface_tool.add_index(i10)
			surface_tool.add_index(i11)
			surface_tool.add_index(i01)
	surface_tool.generate_normals()
	return surface_tool.commit()


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
