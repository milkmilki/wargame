extends SceneTree
const View := preload("res://scripts/view/province_id_view.gd")
var errors := 0

func check(value: bool, label: String) -> void:
	if not value:
		errors += 1
		printerr("PROVINCE_ID_VIEW_FAIL: ", label)

func _init() -> void:
	var state := GameState.new()
	state.map_source_manifest = "res://assets/terrain/eurasia_hydrology_map_source.json"
	state.province_map_size = Vector2i(4, 4)
	# An intentionally non-Voronoi layout, including a legitimate blank cell.
	state.province_ids = PackedInt32Array([0, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1, 1, -1, 0, 0, 1])
	for i in range(2):
		var city := City.new()
		city.id = i
		city.owner_nation = i
		city.loyalty = 20.0 + i * 70.0
		city.map_position = Vector2(0.25 + i * 0.5, 0.5)
		state.cities.append(city)
		var nation := Nation.new()
		nation.id = i
		nation.color = Color.RED if i == 0 else Color.BLUE
		state.nations.append(nation)
	state.region_ids = PackedInt32Array([0, 1])
	state.recognized_city_owners = PackedInt32Array([0, 1])
	state.region_colors = PackedColorArray([Color.GREEN, Color.YELLOW])
	state.administrative_region_ids = PackedInt32Array([0, 1])
	state.administrative_region_colors = PackedColorArray([Color.CYAN, Color.MAGENTA])
	var original := state.province_ids.duplicate()
	var result := View.build(state, null, Vector2i(32, 32))
	for y in range(32):
		for x in range(32):
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / 32.0
			var expected := original[int(uv.y * 4) * 4 + int(uv.x * 4)]
			check(int(result.city_id.get_pixel(x, y).r) == expected, "categorical fill matches saved IDs")
			check(state.province_city_at(uv) == expected, "point lookup matches fill")
			check(MapRenderer.nation_at_map_position(state, uv) == expected, "political picking matches fill")
	check(state.province_ids == original, "display never changes territory")
	var masks := {"province_id": result.city_id, "land_mask": result.land_mask, "edge_mask": result.region_edge}
	for mode in [MapRenderer.MapMode.POLITICAL, MapRenderer.MapMode.LOYALTY, MapRenderer.MapMode.TRADE, MapRenderer.MapMode.REGION]:
		var fill := MapRenderer.build_region_fill_image_from_masks(state, masks, -1, mode)
		var colors := [fill.get_pixel(3, 3), fill.get_pixel(27, 3)]
		check(colors[0] != colors[1], "each mode colors its two regions differently")
		for y in range(2, 32, 8):
			for x in range(2, 32, 8):
				var id := int(result.city_id.get_pixel(x, y).r)
				check(fill.get_pixel(x, y).a == 0.0 if id < 0 else fill.get_pixel(x, y) == colors[id], "all mode fills follow same territory")
	var topology := View.topology(state)
	for i in range(topology.province_a.size()):
		var middle: Vector2 = (topology.province[i * 2] + topology.province[i * 2 + 1]) * 0.5
		check(state.province_city_at(middle + topology.province_side_a[i] * 0.001) == topology.province_a[i], "border side A matches fill")
		check(state.province_city_at(middle + topology.province_side_b[i] * 0.001) == topology.province_b[i], "border side B matches fill")
	state.province_ids[0] = 1
	var edited := View.build(state, null, Vector2i(32, 32))
	check(edited.city_id.get_pixel(0, 0).r == 1.0, "edited grid invalidates display")
	check(result.city_id.get_pixel(0, 0).r == 0.0, "historical image stays unchanged")
	check(MapSource.uses_province_ids(state.map_source_manifest), "Eurasia uses logical grid")
	check(not MapSource.uses_province_ids(MapSource.DEFAULT_MANIFEST), "China behavior unchanged")
	check(state.province_city_at(Vector2(-0.1, 0.5)) == -1, "outside map")
	print("PROVINCE_ID_VIEW: %d failures" % errors)
	quit(1 if errors else 0)
