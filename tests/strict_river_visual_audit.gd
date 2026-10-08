extends SceneTree
const Geometry = preload("res://scripts/view/river_province_geometry.gd")
const Banks = preload("res://scripts/core/river_province_constraints.gd")
const TEMPLATE := "res://.dbg/strict-world-12345.json"
const SIZE := Vector2i(2048,2048)
const BUCKETS := 64.0

func _init() -> void: call_deferred("run")

func _near_root(point: Vector2,roots: PackedVector2Array,aspect: float) -> bool:
	for root in roots:
		if ((point-root)*Vector2(aspect,1)).length() <= Banks.SOURCE_RADIUS: return true
	return false

func _distance(point: Vector2,a: Vector2,b: Vector2) -> float:
	var delta := b-a
	if delta.length_squared() == 0: return point.distance_to(a)
	return point.distance_to(a+delta*clampf((point-a).dot(delta)/delta.length_squared(),0,1))

func _local_faces(record: Dictionary,state: GameState,raster: Dictionary,roots: PackedVector2Array) -> Dictionary:
	var p := Vector2(record.position[0],record.position[1])
	var nearest_source := INF
	for root in roots: nearest_source = minf(nearest_source,((p-root)*Vector2(state.map_aspect_ratio,1)).length())
	var points := PackedVector2Array()
	for river in state.river_features:
		if river.id == record.river_id:
			points = river.points
			break
	var segment: int = record.segment
	var direction := ((points[segment+1]-points[segment])*Vector2(SIZE)).normalized()
	var normal := Vector2(-direction.y,direction.x)
	var local: Array = []
	var all_faces: Array = raster.get("refined_regions",[])
	for i in range(all_faces.size()):
		var face: Dictionary = all_faces[i]
		var center: Vector2 = face.center
		if ((center-p)*Vector2(state.province_map_size)).length() > 1.6: continue
		var polygon: Array = []
		for vertex in face.polygon: polygon.append([vertex.x,vertex.y])
		local.append({"id":i,"owner":face.owner,"polygon":polygon,"center":[center.x,center.y]})
	var queries: Array = []
	for offset in [-1.6,-1.2,-0.8,-0.5,-0.35,-0.1,-0.02,0.02,0.1,0.35,0.5,0.8,1.2,1.6]:
		queries.append({"kind":"ideal_offset","offset_pixels":offset,"point":p+normal*offset/Vector2(SIZE)})
	for key in ["pixel_a","pixel_b"]:
		queries.append({"kind":key+"_center","point":(Vector2(record[key][0],record[key][1])+Vector2.ONE*0.5)/Vector2(SIZE)})
	for query in queries:
		var point: Vector2 = query.point
		var hits: Array = []
		for face in local:
			if Geometry2D.is_point_in_polygon(point,all_faces[face.id].polygon): hits.append({"id":face.id,"owner":face.owner})
		query.faces = hits
		query.raster_city = roundi(raster.city_id.get_pixelv(Vector2i(point*Vector2(SIZE))).r)
		query.point = [point.x,point.y]
	return {"river_id":record.river_id,"segment":segment,"position":record.position,"nearest_source_distance":nearest_source,"queries":queries,"faces":local}

func run() -> void:
	var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATE))
	if not definition is Dictionary or not MapDefinition.validate(definition).is_empty():
		printerr("STRICT_VISUAL_AUDIT_FAIL: missing or invalid real-world template")
		quit(1)
		return
	var state := GameState.new()
	state.generate_from_map_definition(definition,12345)
	var source := (load(state.current_terrain_map_path()) as Texture2D).get_image()
	var raster := Geometry.build(state,source,SIZE)
	var ids: Image = raster.city_id
	var land: Image = raster.land_mask
	var constraints := Banks.build(state.river_features,state.province_map_size,state.map_aspect_ratio)
	var roots: PackedVector2Array = constraints.source_roots
	var segments: Array[Dictionary] = []
	var buckets := {}
	var padding := Vector2.ONE*2.0/Vector2(SIZE)
	for feature in MapFeatureContract.major_rivers(state.river_features):
		var points: PackedVector2Array = feature.points
		for i in range(points.size()-1):
			if points[i].distance_squared_to(points[i+1]) < 1e-18: continue
			var segment_id := segments.size()
			segments.append({"a":points[i],"b":points[i+1],"river_id":feature.id,"segment":i})
			var first := Vector2i(((points[i].min(points[i+1])-padding)*BUCKETS).floor())
			var last := Vector2i(((points[i].max(points[i+1])+padding)*BUCKETS).floor())
			for y in range(first.y,last.y+1):
				for x in range(first.x,last.x+1):
					var key := Vector2i(x,y)
					if not buckets.has(key): buckets[key] = []
					buckets[key].append(segment_id)
	var stats := {"segments":segments.size(),"samples":0,"source_exempt":0,"ambiguous":0,"duplicate":0,"off_map":0,"coastal":0,"unassigned_one_bank":0,"unassigned_both_banks":0,"both_valid":0,"same_city":0,"different_city":0,"same_city_same_coarse_cell":0}
	var failures: Array = []
	var unassigned: Array = []
	var seen := {}
	for segment_id in range(segments.size()):
		var segment: Dictionary = segments[segment_id]
		var a: Vector2 = segment.a
		var b: Vector2 = segment.b
		var direction := ((b-a)*Vector2(SIZE)).normalized()
		var normal := Vector2(-direction.y,direction.x)
		var steps := maxi(1,ceili(((b-a)*Vector2(SIZE)).length()/2.0))
		for step in range(steps):
			stats.samples += 1
			var p := a.lerp(b,(step+0.5)/steps)
			if _near_root(p,roots,state.map_aspect_ratio):
				stats.source_exempt += 1
				continue
			var pa := Vector2i((p+normal*1.2/Vector2(SIZE))*Vector2(SIZE))
			var pb := Vector2i((p-normal*1.2/Vector2(SIZE))*Vector2(SIZE))
			if not Rect2i(Vector2i.ZERO,SIZE).has_point(pa) or not Rect2i(Vector2i.ZERO,SIZE).has_point(pb):
				stats.off_map += 1
				continue
			var qa := (Vector2(pa)+Vector2.ONE*0.5)/Vector2(SIZE)
			var qb := (Vector2(pb)+Vector2.ONE*0.5)/Vector2(SIZE)
			# Check actual sampled pixel centres, not ideal offsets: they must
			# straddle this segment with >=half-pixel clearance, exactly one river
			# crossing, and no second channel grazing either bank pixel.
			var reliable := pa != pb and Geometry2D.segment_intersects_segment(qa,qb,a,b) != null
			reliable = reliable and _distance(qa*Vector2(SIZE),a*Vector2(SIZE),b*Vector2(SIZE)) > 0.5 and _distance(qb*Vector2(SIZE),a*Vector2(SIZE),b*Vector2(SIZE)) > 0.5
			for other_id in buckets.get(Vector2i((p*BUCKETS).floor()),[]):
				if other_id == segment_id: continue
				var other: Dictionary = segments[other_id]
				if Geometry2D.segment_intersects_segment(qa,qb,other.a,other.b) != null or _distance(qa*Vector2(SIZE),other.a*Vector2(SIZE),other.b*Vector2(SIZE)) < 0.5 or _distance(qb*Vector2(SIZE),other.a*Vector2(SIZE),other.b*Vector2(SIZE)) < 0.5:
					reliable = false
					break
			if not reliable:
				stats.ambiguous += 1
				continue
			var pair := "%s:%s" % [pa,pb]
			if seen.has(pair):
				stats.duplicate += 1
				continue
			seen[pair] = true
			var city_a := roundi(ids.get_pixelv(pa).r)
			var city_b := roundi(ids.get_pixelv(pb).r)
			var record := {"river_id":segment.river_id,"segment":segment.segment,"position":[p.x,p.y],"pixel_a":[pa.x,pa.y],"pixel_b":[pb.x,pb.y],"city_a":city_a,"city_b":city_b}
			if land.get_pixelv(pa).r < 0.5 or land.get_pixelv(pb).r < 0.5: stats.coastal += 1
			if city_a < 0 or city_b < 0:
				stats["unassigned_both_banks" if city_a < 0 and city_b < 0 else "unassigned_one_bank"] += 1
				if unassigned.size() < 20: unassigned.append(record)
				continue
			stats.both_valid += 1
			if city_a == city_b:
				stats.same_city += 1
				var ca := Vector2i(qa*Vector2(state.province_map_size))
				var cb := Vector2i(qb*Vector2(state.province_map_size))
				if ca == cb: stats.same_city_same_coarse_cell += 1
				record["coarse_a"] = [ca.x,ca.y]
				record["coarse_b"] = [cb.x,cb.y]
				if failures.size() < 20: failures.append(record)
			else: stats.different_city += 1
	var diagnostics: Array = []
	for record in failures: diagnostics.append(_local_faces(record,state,raster,roots))
	var report := {"template":TEMPLATE,"manifest":state.map_source_manifest,"render_size":[SIZE.x,SIZE.y],"root_count":roots.size(),"source_radius":Banks.SOURCE_RADIUS,"stats":stats,"first_same_city":failures,"first_unassigned":unassigned,"local_face_diagnostics":diagnostics}
	FileAccess.open("res://.dbg/strict-river-visual-audit.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print("STRICT_VISUAL_AUDIT_STATS ",JSON.stringify(stats))
	print("STRICT_VISUAL_AUDIT_FIRST_SAME_CITY ",JSON.stringify(failures))
	if stats.both_valid == 0 or stats.same_city > 0:
		printerr("STRICT_VISUAL_AUDIT_FAIL: reliable assigned river banks must have different city IDs")
		quit(1)
	else:
		print("STRICT_VISUAL_AUDIT_OK")
		quit()
