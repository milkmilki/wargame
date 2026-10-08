class_name RiverProvinceGeometry
extends RefCounted
## Refine administrative cells cut by the authoritative vector river. Region
## ownership always originates in province_ids, never a second city Voronoi.
const VERSION := "river_faces_v1"
const Geometry = preload("res://scripts/view/visual_region_geometry.gd")
const Banks = preload("res://scripts/core/river_province_constraints.gd")
static var _cache := {}

static func build(state: GameState, height_image: Image, size: Vector2i) -> Dictionary:
	var key := hash([VERSION, state.map_source_manifest, state.province_map_size, state.province_ids, state.river_features, MapVisualAtlas.visual_city_seed_signature(state), size, height_image.get_data()])
	if _cache.has(key): return _cache[key]
	var coarse_size := state.province_map_size
	var labels := PackedFloat32Array()
	labels.resize(state.province_ids.size())
	for i in range(labels.size()): labels[i] = state.province_ids[i]
	var coarse_ids := Image.create_from_data(coarse_size.x, coarse_size.y, false, Image.FORMAT_RF, labels.to_byte_array())
	var coarse_land := Geometry._build_land_mask(height_image, coarse_size)
	var raster := Geometry.from_labels(height_image, MapVisualAtlas.visual_city_seeds(state), size, {"city_ids": coarse_ids, "land_mask": coarse_land, "revision": key}, coarse_size)
	var cells := {}
	var source_roots: PackedVector2Array = Banks.build(state.river_features, coarse_size, state.map_aspect_ratio).source_roots
	var paths := MapFeatureContract.major_paths(state.river_features)
	for path in paths:
		for i in range(path.size() - 1):
			var a := path[i] * Vector2(coarse_size)
			var b := path[i + 1] * Vector2(coarse_size)
			var first := Vector2i(a.min(b).floor()).clamp(Vector2i.ZERO, coarse_size - Vector2i.ONE)
			var last := Vector2i(a.max(b).floor()).clamp(Vector2i.ZERO, coarse_size - Vector2i.ONE)
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					var cell := Vector2i(x, y)
					var rect := Rect2(Vector2(cell), Vector2.ONE)
					if not _intersects(a, b, rect): continue
					if not cells.has(cell): cells[cell] = []
					cells[cell].append(PackedVector2Array([path[i], path[i + 1]]))
	var refined_faces := 0
	# Include neighboring cells so a river on a coarse cell border has both
	# faces in the same refinement graph, including tiny bends across corners.
	for cell in cells.keys():
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
			var neighbor: Vector2i=cell+offset
			if Rect2i(Vector2i.ZERO,coarse_size).has_point(neighbor) and not cells.has(neighbor): cells[neighbor]=[]
	var all_faces: Array[Dictionary]=[]
	var faces_by_cell := {}
	for cell in cells:
		var origin := Vector2(cell) / Vector2(coarse_size)
		var span := Vector2.ONE / Vector2(coarse_size)
		var faces: Array[PackedVector2Array] = [PackedVector2Array([origin, origin + Vector2(span.x, 0), origin + span, origin + Vector2(0, span.y)])]
		var split_segments: Array = cells[cell].duplicate()
		for root in source_roots:
			var closest := root.clamp(origin,origin+span)
			var distance := root-closest
			distance.x *= state.map_aspect_ratio
			if distance.length()>Banks.SOURCE_RADIUS: continue
			# Isolate the tiny source exemption before applying downstream bank
			# constraints; otherwise one long face erases the exemption as well.
			for k in range(16):
				var a := Vector2(cos(TAU*k/16.0),sin(TAU*k/16.0))*Banks.SOURCE_RADIUS
				var b := Vector2(cos(TAU*(k+1)/16.0),sin(TAU*(k+1)/16.0))*Banks.SOURCE_RADIUS
				a.x /= state.map_aspect_ratio
				b.x /= state.map_aspect_ratio
				split_segments.append(PackedVector2Array([root+a,root+b]))
		for segment in split_segments:
			var split: Array[PackedVector2Array] = []
			for face in faces:
				for sign_value in [1.0, -1.0]:
					var polygon := _half_plane(face, segment[0], segment[1], sign_value)
					if polygon.size() >= 3 and absf(_area(polygon)) > 1e-14: split.append(polygon)
			faces = split
		var anchors: Array[Dictionary] = []
		for y in range(maxi(0, cell.y - 2), mini(coarse_size.y, cell.y + 3)):
			for x in range(maxi(0, cell.x - 2), mini(coarse_size.x, cell.x + 3)):
				var id := state.province_ids[y * coarse_size.x + x]
				if id >= 0: anchors.append({"id": id, "point": (Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(coarse_size)})
		for city in state.land_cities():
			if Vector2i(city.map_position * Vector2(coarse_size)) == cell:
				anchors.append({"id": city.id, "point": city.map_position})
		var records: Array[Dictionary] = []
		for face in faces:
			var center := Vector2.ZERO
			for p in face: center += p
			center /= face.size()
			var owner := -1
			var best := INF
			var choices: Array[Dictionary] = []
			for anchor in anchors:
				var delta: Vector2 = center - anchor.point
				delta.x *= state.map_aspect_ratio
				var no_positions: Array[Vector2] = []
				if TerrainMapGenerator._road_dictionary_crosses_rivers({"map_path": PackedVector2Array([center, anchor.point])}, no_positions, paths): continue
				choices.append({"owner": anchor.id,"cost":delta.length_squared()})
				if delta.length_squared() < best:
					owner = anchor.id
					best = delta.length_squared()
			records.append({"polygon":face,"owner":owner,"choices":choices,"center":center})
			refined_faces += 1
		faces_by_cell[cell]=PackedInt32Array()
		for record in records:
			faces_by_cell[cell].append(all_faces.size())
			all_faces.append(record)
	var bank_pairs := _opposite_faces(paths,all_faces,faces_by_cell,size,coarse_size,source_roots,state.map_aspect_ratio)
	_resolve_face_banks(all_faces,bank_pairs,state)
	for record in all_faces: _paint(record.polygon,record.owner,raster.city_id,raster.land_mask)
	Geometry._fill_region_edges(raster.city_id, raster.region_edge)
	raster.region_distance = Geometry._build_distance_channel(raster.city_id, raster.land_mask, raster.region_edge)
	var coverage := PackedByteArray()
	coverage.resize(size.x * size.y)
	var final_labels: PackedFloat32Array = raster.city_id.get_data().to_float32_array()
	for i in range(coverage.size()): coverage[i] = 255 if final_labels[i] >= 0 else 0
	raster.region_coverage = Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, coverage)
	raster["revision"] = key
	raster["refined_faces"] = refined_faces
	raster["refined_regions"] = all_faces
	# Hydrological rivers use their own vector paths; no generated-boundary
	# river may consume the intermediate coarse polygons after refinement.
	raster["regions"] = []
	raster["topology"] = topology_from_labels(final_labels, size)
	if _cache.size() >= 2: _cache.erase(_cache.keys()[0])
	_cache[key] = raster
	return raster

static func _opposite_faces(paths: Array[PackedVector2Array], faces: Array[Dictionary], by_cell: Dictionary, size: Vector2i, coarse: Vector2i, roots: PackedVector2Array, aspect: float) -> Array[Vector2i]:
	var paired := {}
	var pairs: Array[Vector2i]=[]
	for path in paths:
		for i in range(path.size()-1):
			var delta := (path[i+1]-path[i])*Vector2(size)
			if delta.length()<1e-5: continue
			var normal := delta.orthogonal().normalized()*0.35/Vector2(size)
			var steps := maxi(1,ceili(delta.length()*2.0))
			for sample in range(steps):
				var point := path[i].lerp(path[i+1],(sample+0.5)/steps)
				var exempt := false
				for root in roots:
					var d := point-root
					d.x*=aspect
					if d.length()<=Banks.SOURCE_RADIUS: exempt=true; break
				if exempt: continue
				var a := _face_at(point+normal,faces,by_cell,coarse)
				var b := _face_at(point-normal,faces,by_cell,coarse)
				if a<0 or b<0 or a==b: continue
				var key := Vector2i(mini(a,b),maxi(a,b))
				if paired.has(key): continue
				paired[key]=true
				pairs.append(key)
	return pairs

static func _face_at(point: Vector2, faces: Array[Dictionary], by_cell: Dictionary, coarse: Vector2i) -> int:
	if point.x<0 or point.y<0 or point.x>=1 or point.y>=1: return -1
	for index in by_cell.get(Vector2i(point*Vector2(coarse)),[]):
		if Geometry2D.is_point_in_polygon(point,faces[index].polygon): return index
	return -1

static func _resolve_face_banks(faces: Array[Dictionary], pairs: Array[Vector2i], state: GameState) -> void:
	var changed := true
	while changed:
		changed = false
		for pair in pairs:
			var a: Dictionary=faces[pair[0]]
			var b: Dictionary=faces[pair[1]]
			if a.owner<0 or a.owner!=b.owner: continue
			# A face containing the actual settlement keeps its owner. Otherwise
			# retain the shore nearest the city and remove that claim on the other.
			var city: City=state.cities[a.owner]
			var keep_a:=Geometry2D.is_point_in_polygon(city.map_position,a.polygon)
			var keep_b:=Geometry2D.is_point_in_polygon(city.map_position,b.polygon)
			var change: Dictionary=b if keep_a or (not keep_b and (a.center as Vector2).distance_squared_to(city.map_position)<(b.center as Vector2).distance_squared_to(city.map_position)) else a
			var rejected_owner: int=change.owner
			var next_owner := -1
			var best := INF
			var candidates: Array[Dictionary]=[]
			for choice in change.choices:
				if choice.owner==rejected_owner: continue
				candidates.append(choice)
				if choice.cost<best: next_owner=choice.owner; best=choice.cost
			change.choices=candidates
			change.owner=next_owner
			changed=true
static func topology_from_labels(ids: PackedFloat32Array, size: Vector2i) -> Dictionary:
	var result := {"province": PackedVector2Array(), "coast": PackedVector2Array(), "province_a": PackedInt32Array(), "province_b": PackedInt32Array(), "province_side_a": PackedVector2Array(), "province_side_b": PackedVector2Array(), "coast_province": PackedInt32Array(), "coast_side": PackedVector2Array(), "source_size": size, "contract_version": 2}
	# Merge only collinear runs with identical bank labels. This retains the
	# categorical atlas exactly; country outlines and picking share one source.
	for axis in range(2):
		var rows := size.y if axis == 0 else size.x
		var columns := size.x if axis == 0 else size.y
		for row in range(rows + 1):
			var start := 0
			var old_a := -2
			var old_b := -2
			for column in range(columns + 1):
				var a := -2
				var b := -2
				if column < columns:
					var x := column if axis == 0 else row
					var y := row if axis == 0 else column
					a = int(ids[(y - 1) * size.x + x]) if axis == 0 and y > 0 else (int(ids[y * size.x + x - 1]) if axis == 1 and x > 0 else -1)
					b = int(ids[y * size.x + x]) if row < rows else -1
				if a == old_a and b == old_b: continue
				if column > start and old_a != old_b and (old_a >= 0 or old_b >= 0):
					var p := Vector2(start, row) if axis == 0 else Vector2(row, start)
					var q := Vector2(column, row) if axis == 0 else Vector2(row, column)
					var side := Vector2.UP if axis == 0 else Vector2.LEFT
					if old_a >= 0 and old_b >= 0:
						result.province.append_array(PackedVector2Array([p / Vector2(size), q / Vector2(size)]))
						result.province_a.append(old_a)
						result.province_b.append(old_b)
						result.province_side_a.append(side)
						result.province_side_b.append(-side)
					else:
						result.coast.append_array(PackedVector2Array([p / Vector2(size), q / Vector2(size)]))
						result.coast_province.append(maxi(old_a, old_b))
						result.coast_side.append(side if old_a >= 0 else -side)
				start = column
				old_a = a
				old_b = b
	return result

static func _intersects(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b): return true
	var p := rect.position
	var q := rect.end
	var border := PackedVector2Array([p, Vector2(q.x, p.y), q, Vector2(p.x, q.y)])
	for i in range(4):
		if Geometry2D.segment_intersects_segment(a, b, border[i], border[(i + 1) % 4]) != null: return true
	return false

static func _half_plane(polygon: PackedVector2Array, a: Vector2, b: Vector2, sign_value: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var direction := b - a
	if direction.length_squared() < 1e-20: return polygon
	for i in range(polygon.size()):
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var dp := direction.cross(p - a) * sign_value
		var dq := direction.cross(q - a) * sign_value
		if dp >= 0: result.append(p)
		if (dp < 0 and dq > 0) or (dp > 0 and dq < 0): result.append(p.lerp(q, dp / (dp - dq)))
	return result

static func _area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	var origin := polygon[0]
	for i in range(polygon.size()): area += (polygon[i]-origin).cross(polygon[(i + 1) % polygon.size()]-origin)
	return area * 0.5

static func _paint(polygon: PackedVector2Array, owner: int, ids: Image, land: Image) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon: bounds = bounds.expand(p)
	var size := ids.get_size()
	for y in range(maxi(0, int(floor(bounds.position.y * size.y))), mini(size.y, int(ceil(bounds.end.y * size.y)))):
		var scan := (y + 0.5) / size.y
		var hits: Array[float] = []
		for i in range(polygon.size()):
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan): hits.append(a.x + (scan - a.y) * (b.x - a.x) / (b.y - a.y))
		hits.sort()
		for i in range(0, hits.size() - 1, 2):
			for x in range(maxi(0, int(ceil(hits[i] * size.x - 0.5))), mini(size.x, int(ceil(hits[i + 1] * size.x - 0.5)))):
				ids.set_pixel(x, y, Color(owner if land.get_pixel(x, y).r > 0.5 else -1, 0, 0))
