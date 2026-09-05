class_name MapFeatureContract
extends RefCounted
## Versioned natural-feature records shared by imported and procedural maps.
## Authoritative points drive topology and transport. Smoothed paths are derived
## copies for rendering only and must never be written back into these records.

const SCHEMA_VERSION: int = 1
const FEATURE_RIVER := "river"
const FLOW_POINTS_DOWNSTREAM := "points_downstream"
const SOURCE_GENERATED_BOUNDARY := "generated_boundary"
const SOURCE_PROCEDURAL_HYDROLOGY := "procedural_hydrology"
const SOURCE_IMPORTED := "imported"
const VALID_SOURCE_KINDS := [
	SOURCE_GENERATED_BOUNDARY,
	SOURCE_PROCEDURAL_HYDROLOGY,
	SOURCE_IMPORTED,
]
const DEFAULT_SOURCE_WIDTH: float = 0.72
const DEFAULT_MOUTH_WIDTH: float = 1.18
const MAX_RENDER_DEVIATION_PX: float = 0.45


static func make_river(
	river_id: int,
	points: PackedVector2Array,
	source_kind: String = SOURCE_GENERATED_BOUNDARY,
	source_width: float = DEFAULT_SOURCE_WIDTH,
	mouth_width: float = DEFAULT_MOUTH_WIDTH,
	downstream_id: int = -1,
	upstream_ids: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"feature_kind": FEATURE_RIVER,
		"id": river_id,
		"source_kind": source_kind,
		"flow_direction": FLOW_POINTS_DOWNSTREAM,
		"points": points.duplicate(),
		"source_width": source_width,
		"mouth_width": mouth_width,
		"downstream_id": downstream_id,
		"upstream_ids": upstream_ids.duplicate(),
	}


static func from_legacy_river_paths(paths: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for river_id in range(paths.size()):
		var points := _coerce_points(paths[river_id])
		result.append(make_river(river_id, points))
	return result


static func authoritative_paths(rivers: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for river_value in rivers:
		if not river_value is Dictionary:
			continue
		result.append(_coerce_points((river_value as Dictionary).get("points", [])))
	return result


static func validate_rivers(rivers: Array) -> String:
	var ids := {}
	for index in range(rivers.size()):
		if not rivers[index] is Dictionary:
			return "河流 %d 不是结构化记录。" % index
		var river := rivers[index] as Dictionary
		if int(river.get("schema_version", -1)) != SCHEMA_VERSION:
			return "河流 %d 的特征版本不受支持。" % index
		if str(river.get("feature_kind", "")) != FEATURE_RIVER:
			return "河流 %d 的特征类型无效。" % index
		var river_id := int(river.get("id", -1))
		if river_id < 0 or ids.has(river_id):
			return "河流 ID 必须非负且不能重复：%d" % river_id
		ids[river_id] = true
		if str(river.get("flow_direction", "")) != FLOW_POINTS_DOWNSTREAM:
			return "河流 %d 必须按源头到下游排列。" % river_id
		if not VALID_SOURCE_KINDS.has(str(river.get("source_kind", ""))):
			return "河流 %d 的来源类型无效。" % river_id
		var points := _coerce_points(river.get("points", []))
		if points.size() < 2:
			return "河流 %d 至少需要两个点。" % river_id
		for point_index in range(points.size()):
			var point := points[point_index]
			if (
				not is_finite(point.x) or not is_finite(point.y)
				or point.x < 0.0 or point.x > 1.0
				or point.y < 0.0 or point.y > 1.0
			):
				return "河流 %d 含地图范围外坐标。" % river_id
			if point_index > 0 and point.is_equal_approx(points[point_index - 1]):
				return "河流 %d 含连续重复点。" % river_id
		var source_width := float(river.get("source_width", 0.0))
		var mouth_width := float(river.get("mouth_width", 0.0))
		if (
			not is_finite(source_width) or source_width <= 0.0
			or not is_finite(mouth_width) or mouth_width <= 0.0
		):
			return "河流 %d 的宽度必须为正数。" % river_id
		var downstream_id := int(river.get("downstream_id", -1))
		if downstream_id == river_id:
			return "河流 %d 不能流入自身。" % river_id
		var upstream_seen := {}
		for upstream_value in river.get("upstream_ids", PackedInt32Array()):
			var upstream_id := int(upstream_value)
			if upstream_id == river_id or upstream_seen.has(upstream_id):
				return "河流 %d 的上游引用无效。" % river_id
			upstream_seen[upstream_id] = true
	for river_value in rivers:
		var river := river_value as Dictionary
		var river_id := int(river["id"])
		var downstream_id := int(river.get("downstream_id", -1))
		if downstream_id >= 0 and not ids.has(downstream_id):
			return "河流 %d 指向不存在的下游 ID。" % river_id
		for upstream_value in river.get("upstream_ids", PackedInt32Array()):
			if not ids.has(int(upstream_value)):
				return "河流 %d 引用了不存在的上游 ID。" % river_id
	var cycle_error := _validate_downstream_cycles(rivers)
	if not cycle_error.is_empty():
		return cycle_error
	return ""


static func validate_serialized_rivers(records: Array) -> String:
	for index in range(records.size()):
		var value: Variant = records[index]
		if not value is Dictionary:
			return "河流 %d 不是结构化记录。" % index
		var record := value as Dictionary
		for string_key in ["feature_kind", "source_kind", "flow_direction"]:
			if not record.get(string_key) is String:
				return "河流 %d 的 %s 必须是字符串。" % [index, string_key]
		for integer_key in ["schema_version", "id", "downstream_id"]:
			if not _is_integer(record.get(integer_key)):
				return "河流 %d 的 %s 必须是整数。" % [index, integer_key]
		for width_key in ["source_width", "mouth_width"]:
			var width_value: Variant = record.get(width_key)
			if not width_value is int and not width_value is float:
				return "河流 %d 的 %s 必须是数值。" % [index, width_key]
		var upstream_value: Variant = record.get("upstream_ids")
		if not upstream_value is Array:
			return "河流 %d 的 upstream_ids 必须是数组。" % index
		for upstream_id in upstream_value as Array:
			if not _is_integer(upstream_id):
				return "河流 %d 的上游 ID 必须是整数。" % index
		var points_value: Variant = record.get("points")
		if not points_value is Array:
			return "河流 %d 的 points 必须是数组。" % index
		for point_value in points_value as Array:
			if not point_value is Array or (point_value as Array).size() != 2:
				return "河流 %d 的坐标必须是二元数组。" % index
			for coordinate in point_value as Array:
				if not coordinate is int and not coordinate is float:
					return "河流 %d 的坐标必须是数值。" % index
	return validate_rivers(deserialize_rivers(records))


static func serialize_rivers(rivers: Array) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for river_value in rivers:
		var river := river_value as Dictionary
		var serialized_points: Array[Array] = []
		for point in _coerce_points(river.get("points", [])):
			serialized_points.append([point.x, point.y])
		records.append({
			"schema_version": int(river.get("schema_version", SCHEMA_VERSION)),
			"feature_kind": str(river.get("feature_kind", FEATURE_RIVER)),
			"id": int(river.get("id", records.size())),
			"source_kind": str(river.get("source_kind", SOURCE_IMPORTED)),
			"flow_direction": str(river.get("flow_direction", FLOW_POINTS_DOWNSTREAM)),
			"points": serialized_points,
			"source_width": float(river.get("source_width", DEFAULT_SOURCE_WIDTH)),
			"mouth_width": float(river.get("mouth_width", DEFAULT_MOUTH_WIDTH)),
			"downstream_id": int(river.get("downstream_id", -1)),
			"upstream_ids": Array(river.get("upstream_ids", PackedInt32Array())),
		})
	return records


static func deserialize_rivers(records: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(records.size()):
		var value: Variant = records[index]
		if not value is Dictionary:
			result.append(make_river(index, _coerce_points(value), SOURCE_IMPORTED))
			continue
		var record := value as Dictionary
		result.append(make_river(
			int(record.get("id", index)),
			_coerce_points(record.get("points", [])),
			str(record.get("source_kind", SOURCE_IMPORTED)),
			float(record.get("source_width", DEFAULT_SOURCE_WIDTH)),
			float(record.get("mouth_width", DEFAULT_MOUTH_WIDTH)),
			int(record.get("downstream_id", -1)),
			PackedInt32Array(record.get("upstream_ids", []))
		))
	return result


static func width_at_progress(river: Dictionary, progress: float) -> float:
	return lerpf(
		float(river.get("source_width", DEFAULT_SOURCE_WIDTH)),
		float(river.get("mouth_width", DEFAULT_MOUTH_WIDTH)),
		clampf(progress, 0.0, 1.0)
	)


static func build_river_render_path(
	river: Dictionary,
	raster_size: Vector2i,
	subdivisions: int = 4
) -> PackedVector2Array:
	var source := _coerce_points(river.get("points", []))
	if source.size() < 3 or subdivisions <= 1:
		return source.duplicate()
	var result := PackedVector2Array()
	var safe_size := Vector2(maxi(raster_size.x, 1), maxi(raster_size.y, 1))
	for segment in range(source.size() - 1):
		var p0 := source[maxi(segment - 1, 0)]
		var p1 := source[segment]
		var p2 := source[segment + 1]
		var p3 := source[mini(segment + 2, source.size() - 1)]
		for step in range(subdivisions):
			var t := float(step) / float(subdivisions)
			var candidate := _catmull_rom(p0, p1, p2, p3, t)
			var nearest := Geometry2D.get_closest_point_to_segment(
				candidate * safe_size, p1 * safe_size, p2 * safe_size
			)
			var candidate_px := candidate * safe_size
			var delta := candidate_px - nearest
			if delta.length() > MAX_RENDER_DEVIATION_PX:
				candidate_px = nearest + delta.normalized() * MAX_RENDER_DEVIATION_PX
			candidate = candidate_px / safe_size
			if result.is_empty() or not result[-1].is_equal_approx(candidate):
				result.append(candidate)
	result.append(source[-1])
	return result


static func _catmull_rom(
	p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float
) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


static func _coerce_points(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return (value as PackedVector2Array).duplicate()
	var result := PackedVector2Array()
	if not value is Array:
		return result
	for point_value in value as Array:
		if point_value is Vector2:
			result.append(point_value)
		elif point_value is Array and (point_value as Array).size() == 2:
			var point := point_value as Array
			result.append(Vector2(float(point[0]), float(point[1])))
	return result


static func _validate_downstream_cycles(rivers: Array) -> String:
	var downstream_by_id := {}
	for river_value in rivers:
		var river := river_value as Dictionary
		downstream_by_id[int(river["id"])] = int(river.get("downstream_id", -1))
	for start_value in downstream_by_id:
		var start := int(start_value)
		var visited := {}
		var current := start
		while current >= 0:
			if visited.has(current):
				return "河网不能包含下游环：%d" % start
			visited[current] = true
			current = int(downstream_by_id.get(current, -1))
	return ""


static func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	if not value is float:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number)
