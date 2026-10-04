extends SceneTree

const GEOMETRY := preload("res://scripts/view/visual_region_geometry.gd")


func _init() -> void:
	var height := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	height.fill(Color(1.0, 1.0, 1.0, 0.78))
	var seeds: Array[Dictionary] = [
		{"city_id": 0, "position": Vector2(0.25, 0.25)},
		{"city_id": 1, "position": Vector2(0.75, 0.25)},
		{"city_id": 2, "position": Vector2(0.5, 0.75)},
	]
	var result := GEOMETRY.build_visual_region_geometry(
		height, seeds, Vector2i(256, 256)
	)
	var ids: Image = result["city_id"]
	var edge: Image = result["region_edge"]
	var uncovered := 0
	var missing_edges := 0
	for y in range(1, 255):
		for x in range(1, 255):
			var id := int(round(ids.get_pixel(x, y).r))
			if id < 0:
				uncovered += 1
			if id >= 0 and (
				id != int(round(ids.get_pixel(x + 1, y).r))
				or id != int(round(ids.get_pixel(x, y + 1).r))
			):
				if edge.get_pixel(x, y).r < 0.5:
					missing_edges += 1
	if uncovered > 0 or missing_edges > 0:
		push_error("VISUAL_REGION_SEAMS_FAILED uncovered=%d missing_edges=%d" % [
			uncovered, missing_edges,
		])
		quit(1)
		return
	print("VISUAL_REGION_SEAMS_OK")
	quit(0)
