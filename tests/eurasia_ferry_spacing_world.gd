extends SceneTree
const SOURCE := "res://assets/terrain/eurasia_hydrology_map_source.json"
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1; printerr("FERRY_WORLD_FAIL: ",message)
func run() -> void:
	var seed_value := int(OS.get_environment("FERRY_TEST_SEED"))
	if seed_value==0: seed_value=1107871845
	var baseline_path := "res://.dbg/road-fix-after-%d.json" % seed_value
	var before := GameState.new()
	if FileAccess.file_exists(baseline_path):
		before.generate_from_map_definition(JSON.parse_string(FileAccess.get_file_as_string(baseline_path)),seed_value)
	else:
		MapSource.load_manifest(SOURCE)
		MapSource._cache[SOURCE].erase("ferry_interval")
		check(before.generate_world(seed_value,40,500,"",{},seed_value,"",SOURCE),"baseline generation")
	MapSource._cache.erase(SOURCE)
	var interval_override := OS.get_environment("FERRY_TEST_INTERVAL")
	if not interval_override.is_empty():
		MapSource.load_manifest(SOURCE)
		MapSource._cache[SOURCE]["ferry_interval"] = float(interval_override)
	var state := GameState.new()
	check(state.generate_world(seed_value,40,500,"",{},seed_value,"",SOURCE),state.last_generation_error)
	if failures: quit(1); return
	check(state.land_cities().size()==500 and state.nations.size()==40,"500 cities / 40 nations")
	check(state.province_ids==before.province_ids,"unchanged province IDs")
	for i in range(500): check(state.cities[i].map_position==before.cities[i].map_position,"unchanged city placement")
	check(JSON.stringify(MapFeatureContract.serialize_rivers(state.river_features))==JSON.stringify(MapFeatureContract.serialize_rivers(before.river_features)),"unchanged river network")
	var stats: Dictionary = state.generation_metadata.ferry_spacing
	check(stats.total==state.cities.size()-500 and stats.total==stats.regular+stats.necessary,"regular and necessary counts are separate and exact")
	check(stats.total<before.cities.size()-500,"fewer ferries in actual world")
	check(stats.maximum_per_river==5,"formal source enables hard five cap")
	for count in stats.river_counts.values(): check(int(count)<=5,"final total includes supplements within cap")
	check(state.territory_structure_valid(),"valid territory topology")
	var features: Array = state.river_features
	var points: Array[Vector2] = []
	for city in state.cities: points.append(city.map_position)
	var boats := 0
	for edge in state.edges:
		if edge.kind in [Edge.Kind.LAND,Edge.Kind.LANDING]:
			check(not TerrainMapGenerator._road_dictionary_crosses_rivers({"map_path":edge.map_path},points,MapFeatureContract.major_paths(features)),"no illegal river crossing")
		if edge.kind==Edge.Kind.RIVER:
			boats+=1; check(not edge.river_reaches.is_empty(),"explicit river route references")
	for city in state.cities:
		if not city.is_dock: continue
		var banks := 0
		for neighbor in state.neighbors(city.id):
			if state.edge_of(city.id,neighbor).kind==Edge.Kind.LANDING: banks+=1
		check(banks==2,"two legal banks per ferry")
	# No sea shortcuts for the Eurasian west / central / east acceptance.
	var anchors: Array[int] = []
	for box in [Rect2(.06,.15,.2,.55),Rect2(.43,.15,.2,.7),Rect2(.74,.18,.2,.68)]:
		var best := -1; var distance := INF
		for city in state.land_cities():
			if box.has_point(city.map_position) and city.map_position.distance_to(box.get_center())<distance: best=city.id; distance=city.map_position.distance_to(box.get_center())
		anchors.append(best)
	check(not anchors.has(-1),"all geographic anchors present")
	if not anchors.has(-1):
		var queue: Array[int] = [anchors[0]]; var seen := {anchors[0]:true}; var head := 0
		while head<queue.size():
			var current := queue[head]; head+=1
			for neighbor in state.neighbors(current):
				if state.edge_of(current,neighbor).kind!=Edge.Kind.SEA and not seen.has(neighbor): seen[neighbor]=true; queue.append(neighbor)
		check(seen.has(anchors[1]) and seen.has(anchors[2]),"west / central / east connected without sea")
	var saved := MapDefinition.from_state(state)
	# Reconstruct quotas from persisted river geometry and landing positions,
	# independently of the generator's diagnostic labels.
	var river_groups: Dictionary = TerrainMapGenerator.FerrySpacing.river_groups(features)
	var actual_counts := {}
	for city in state.cities:
		if not city.is_dock: continue
		var matched := false
		for feature in MapFeatureContract.major_rivers(features):
			var path: PackedVector2Array = feature.points
			for j in range(path.size()-1):
				if Geometry2D.get_closest_point_to_segment(city.map_position,path[j],path[j+1]).distance_to(city.map_position)>1e-6: continue
				var group: String = river_groups[int(feature.id)]
				actual_counts[group]=int(actual_counts.get(group,0))+1
				matched=true; break
			if matched: break
		check(matched,"each ferry belongs to a major river")
	for count in actual_counts.values(): check(int(count)<=5,"geometry-based per-river cap")
	check(MapDefinition.validate(saved).is_empty(),"template validates")
	var restored := GameState.new(); restored.generate_from_map_definition(saved,seed_value)
	check(restored.cities.size()==state.cities.size() and restored.province_ids==state.province_ids,"template retains layout and sparse ferry count")
	for i in range(state.edges.size()): check(restored.edges[i].map_path==state.edges[i].map_path,"template retains exact routes")
	check(state.generation_metadata.road_path_simplification.changed_roads>0,"road visibility simplification stays enabled")
	# A second generation exercises the new layout cache, distinct from legacy.
	var again := GameState.new(); check(again.generate_world(seed_value,40,500,"",{},seed_value,"",SOURCE),"cached regeneration")
	check(MapDefinition.from_state(again)==saved,"deterministic cached generation")
	FileAccess.open("res://.dbg/ferry-spacing-%d.json" % seed_value,FileAccess.WRITE).store_string(JSON.stringify(saved))
	print("FERRY_WORLD seed=",seed_value," before=",before.cities.size()-500," after=",stats," river_links=",boats)
	var visual_dir := OS.get_environment("FERRY_VISUAL_DIR")
	if not visual_dir.is_empty():
		root.size = Vector2i(1800,1000)
		DirAccess.make_dir_recursive_absolute(visual_dir)
		for entry in [{"name":"before","state":before},{"name":"after","state":state}]:
			var simulation := Simulation.new(); root.add_child(simulation)
			simulation.setup(entry.state); simulation.paused=true
			var overlay := MapRenderer.new(); root.add_child(overlay)
			overlay.setup(entry.state,simulation)
			overlay.set_world_layer_visible(false)
			overlay.set_city_names_visible(false); overlay.set_nation_names_visible(false)
			var view := StrategicMap3D.new(); root.add_child(view)
			view.setup(entry.state,simulation,overlay)
			while view._terrain==null or view._terrain.land_cell_count()==0: await process_frame
			view.set_map_mode(MapRenderer.MapMode.POLITICAL)
			var overview := view._camera_distance
			var china_uv := MapSource.lonlat_to_map(110,33,SOURCE)
			for detail in [{"name":"full","uv":Vector2(.5,.5),"zoom":1.0},{"name":"china","uv":Vector2(china_uv[0],china_uv[1]),"zoom":.3}]:
				var center := view._terrain.map_to_world(detail.uv)
				view._camera_target=Vector3(center.x,0,center.z); view._camera_distance=overview*detail.zoom
				view._apply_camera_transform()
				await process_frame; await process_frame; await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(visual_dir.path_join("ferries-%s-%s.png" % [entry.name,detail.name]))==OK,"actual rendered ferry preview")
			view.free(); overlay.free(); simulation.free()
	print("EURASIA_FERRY_SPACING_WORLD: %d failures" % failures)
	quit(1 if failures else 0)
