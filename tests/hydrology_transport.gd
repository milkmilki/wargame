extends SceneTree
const Transport = preload("res://scripts/core/river_transport.gd")
func _init() -> void:
	var join := Vector2(0.5, 0.5)
	var features: Array[Dictionary] = []
	features.append(MapFeatureContract.make_river(0, PackedVector2Array([Vector2(0.2, 0.2), join]), "procedural_hydrology", 0.7, 0.8, 2))
	features.append(MapFeatureContract.make_river(1, PackedVector2Array([Vector2(0.8, 0.2), join]), "procedural_hydrology", 0.7, 0.8, 2))
	features.append(MapFeatureContract.make_river(2, PackedVector2Array([join, Vector2(0.5, 0.9)]), "procedural_hydrology", 0.8, 1.0, -1, PackedInt32Array([0, 1])))
	features.append(MapFeatureContract.make_river(3, PackedVector2Array([Vector2(0.1, 0.7), join]), "procedural_hydrology", 0.2, 0.3, -1, PackedInt32Array(), "minor"))
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.6))
	var docks := []
	for i in range(3): docks.append({"city_id": i, "river_id": i, "river_progress": 0.5, "position": features[i].points[0].lerp(features[i].points[1], 0.5)})
	var roads := Transport.build(features, docks, image, 2.879)
	assert(roads.size() == 3, "Junction must join all three nearest docks")
	for road in roads:
		assert(road.river_reaches.size() == 2)
		assert(road.map_path[0].is_equal_approx(docks[road.a].position))
		assert(road.map_path[-1].is_equal_approx(docks[road.b].position))
		for reach in road.river_reaches: assert(reach.river_id != 3)
	# A dock inside an arm must stop a route before it reaches farther docks.
	docks.append({"city_id": 3, "river_id": 0, "river_progress": 0.75, "position": features[0].points[0].lerp(join, 0.75)})
	roads = Transport.build(features, docks, image, 2.879)
	for road in roads:
		if road.a == 0: assert(road.b == 3)
	print("HYDROLOGY_TRANSPORT_OK")
	quit()
