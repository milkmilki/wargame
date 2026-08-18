@tool
class_name StrategicHeightmapNode
extends GaeaNodeResource
## 将现有权威高度图转换为 Gaea Map。每个有效地表采样只写一个单元，
## cell.y 保存离散高度；连续表面由 StrategicTerrainRenderer 重建。


func _get_title() -> String:
	return "Strategic Heightmap"


func _get_description() -> String:
	return "Samples the authoritative terrain texture into a Gaea height grid."


func _get_arguments_list() -> Array[StringName]:
	return [
		&"texture",
		&"source_origin",
		&"source_size",
		&"resolution",
		&"height_steps",
		&"alpha_threshold",
		&"luma_threshold",
	]


func _get_argument_type(arg_name: StringName) -> GaeaValue.Type:
	match arg_name:
		&"texture":
			return GaeaValue.Type.TEXTURE
		&"source_origin", &"source_size":
			return GaeaValue.Type.VECTOR2
		&"resolution":
			return GaeaValue.Type.VECTOR2I
		&"height_steps":
			return GaeaValue.Type.INT
		&"alpha_threshold", &"luma_threshold":
			return GaeaValue.Type.FLOAT
	return GaeaValue.Type.NULL


func _get_argument_default_value(arg_name: StringName) -> Variant:
	match arg_name:
		&"source_origin":
			return Vector2.ZERO
		&"source_size":
			return Vector2.ONE
		&"resolution":
			return Vector2i(192, 128)
		&"height_steps":
			return 24
		&"alpha_threshold":
			return TerrainMapGenerator.ALPHA_THRESHOLD
		&"luma_threshold":
			return TerrainMapGenerator.LUMA_THRESHOLD
	return super(arg_name)


func _get_output_ports_list() -> Array[StringName]:
	return [&"heightmap"]


func _get_output_port_type(_output_name: StringName) -> GaeaValue.Type:
	return GaeaValue.Type.MAP


func _get_data(
	_output_port: StringName,
	pouch: GaeaGenerationPouch
) -> GaeaValue.Map:
	var result := GaeaValue.Map.new()
	var texture := _get_arg(&"texture", pouch) as Texture2D
	if texture == null:
		return result
	var image := texture.get_image()
	if image == null or image.is_empty():
		return result

	var source_origin: Vector2 = _get_arg(
		&"source_origin",
		pouch
	)
	var source_size: Vector2 = _get_arg(&"source_size", pouch)
	var resolution: Vector2i = _get_arg(&"resolution", pouch)
	var height_steps := maxi(
		int(_get_arg(&"height_steps", pouch)),
		1
	)
	var alpha_threshold := float(
		_get_arg(&"alpha_threshold", pouch)
	)
	var luma_threshold := float(
		_get_arg(&"luma_threshold", pouch)
	)
	var surface_material := StrategicHeightMaterial.new()
	var image_size := Vector2(image.get_size())

	for x in _get_axis_range(Vector3i.AXIS_X, pouch.area):
		if x < 0 or x >= resolution.x:
			continue
		var u := (
			(float(x) + 0.5)
			/ float(maxi(resolution.x, 1))
		)
		for z in _get_axis_range(Vector3i.AXIS_Z, pouch.area):
			if z < 0 or z >= resolution.y:
				continue
			var v := (
				(float(z) + 0.5)
				/ float(maxi(resolution.y, 1))
			)
			var source_uv := (
				source_origin
				+ Vector2(u, v) * source_size
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
			var height := clampi(
				int(round(altitude * float(height_steps))),
				0,
				height_steps
			)
			result.set_cell(
				Vector3i(x, height, z),
				surface_material
			)
	return result
