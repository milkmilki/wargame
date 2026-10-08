class_name RiverNavigation
extends RefCounted
## Local terrain windows, in map-height units. Flow classification is untouched.
const MODEL := "local_height_v1"
const SAMPLE_STEP := 0.002
const WINDOW_LENGTH := 0.012
const MAX_LOCAL_HEIGHT := 0.20

static func assess(points: PackedVector2Array, image: Image, aspect: float) -> Dictionary:
	var result := {"model": MODEL, "sample_step": SAMPLE_STEP, "window_length": WINDOW_LENGTH, "max_local_height_difference": 0.0, "navigable": false}
	if points.size() < 2 or image == null or image.is_empty() or not is_finite(aspect) or aspect <= 0.0: return result
	var path := PackedVector2Array()
	for p in points:
		if not p.is_finite() or p.x < 0 or p.y < 0 or p.x > 1 or p.y > 1: return result
		if not path.is_empty() and path[-1].is_equal_approx(p): continue
		while path.size() >= 2:
			var a := path[-1] - path[-2]
			var b := p - path[-1]
			if absf(a.cross(b)) > 1e-8 or a.dot(b) < 0: break
			path.remove_at(path.size() - 1)
		path.append(p)
	if path.size() < 2: return result
	var distances := PackedFloat64Array()
	var heights := PackedFloat64Array()
	var total := 0.0
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var delta := b - a
		var length := Vector2(delta.x * aspect, delta.y).length()
		if length <= 0: continue
		# Sample both sides of DEM pixel crossings: a narrow cliff between
		# vector vertices must not disappear when a reach is simplified.
		var cuts: Array[float] = [0.0, 1.0]
		for axis in range(2):
			var pixels := image.get_width() if axis == 0 else image.get_height()
			var start := a[axis] * pixels
			var end := b[axis] * pixels
			if absf(end - start) < 1e-9: continue
			for boundary in range(int(floor(minf(start, end))) + 1, int(ceil(maxf(start, end)))):
				var t := (boundary - start) / (end - start)
				cuts.append(maxf(0.0, t - 0.001 / absf(end - start)))
				cuts.append(minf(1.0, t + 0.001 / absf(end - start)))
		for step in range(1, int(ceil(length / SAMPLE_STEP))): cuts.append(step * SAMPLE_STEP / length)
		cuts.sort()
		for t in cuts:
			var pixel := Vector2i(a.lerp(b, t) * Vector2(image.get_size())).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
			distances.append(total + t * length)
			heights.append(TerrainMapGenerator.packed_altitude(image.get_pixelv(pixel)))
		total += length
	var low: Array[int] = []
	var high: Array[int] = []
	var low_head := 0
	var high_head := 0
	var maximum := 0.0
	for i in range(heights.size()):
		while low.size() > low_head and heights[low[-1]] >= heights[i]: low.pop_back()
		while high.size() > high_head and heights[high[-1]] <= heights[i]: high.pop_back()
		low.append(i)
		high.append(i)
		while distances[i] - distances[low[low_head]] > WINDOW_LENGTH + 1e-8: low_head += 1
		while distances[i] - distances[high[high_head]] > WINDOW_LENGTH + 1e-8: high_head += 1
		maximum = maxf(maximum, heights[high[high_head]] - heights[low[low_head]])
	result.max_local_height_difference = maximum
	result.navigable = maximum <= MAX_LOCAL_HEIGHT
	return result
