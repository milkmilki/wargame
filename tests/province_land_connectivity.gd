extends SceneTree
## Provinces may spread only through four-connected land. An island without a
## settlement remains unassigned instead of inheriting the nearest mainland.


func _init() -> void:
	var size := Vector2i(7, 3)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	var land := PackedByteArray()
	land.resize(size.x * size.y)
	for y in range(size.y):
		for x in [0, 1, 2, 4, 5, 6]:
			land[y * size.x + x] = 1
	var provinces := TerrainMapGenerator._build_province_raster(
		image,
		land,
		Rect2i(Vector2i.ZERO, size),
		[Vector2i(1, 1)] as Array[Vector2i],
		[] as Array[Array]
	)
	var ids: PackedInt32Array = provinces["ids"]
	var valid := true
	for y in range(size.y):
		for x in range(size.x):
			var province_id := ids[y * size.x + x]
			if x <= 2:
				valid = valid and province_id == 0
			elif x >= 4:
				valid = valid and province_id == -1
			else:
				valid = valid and province_id == -1
	if not valid:
		push_error("PROVINCE_LAND_CONNECTIVITY_FAILED ids=%s" % str(ids))
		quit(1)
		return
	print("PROVINCE_LAND_CONNECTIVITY_OK")
	quit(0)
