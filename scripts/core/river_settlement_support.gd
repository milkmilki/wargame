extends RefCounted
## Settlement water access is independent of hydrological discharge and navigation.
const VERSION := "uniform_water_v2"
## Equal-width envelope approximates smaller tributaries absent from the vector network.
const RADIUS := 0.04
const BANK_RISE_FULL := 0.003
const BANK_RISE_LIMIT := 0.04
const BUCKET := 0.0125

static func cache_identity(radius: float = RADIUS) -> String:
	return "%s:%s:%s:%s" % [VERSION, radius, BANK_RISE_FULL, BANK_RISE_LIMIT]

static func build_index(features: Array, aspect: float, radius: float = RADIUS) -> Dictionary:
	var starts := PackedVector2Array()
	var deltas := PackedVector2Array()
	var inverse_lengths := PackedFloat64Array()
	var buckets := {}
	for feature in features:
		var points: PackedVector2Array = feature.points
		for i in range(points.size() - 1):
			var a := points[i] * Vector2(aspect, 1.0)
			var b := points[i + 1] * Vector2(aspect, 1.0)
			var delta := b - a
			if delta.length_squared() < 1e-20: continue
			var id := starts.size()
			starts.append(a)
			deltas.append(delta)
			inverse_lengths.append(1.0 / delta.length_squared())
			var first := Vector2i(((a.min(b) - Vector2.ONE * radius) / BUCKET).floor())
			var last := Vector2i(((a.max(b) + Vector2.ONE * radius) / BUCKET).floor())
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					var key := Vector2i(x, y)
					if not buckets.has(key): buckets[key] = []
					buckets[key].append(id)
	return {"starts": starts, "deltas": deltas, "inverse_lengths": inverse_lengths, "buckets": buckets, "aspect": aspect, "radius": radius}

static func height_at(source: Image, position: Vector2) -> float:
	var pixel := Vector2i(position * Vector2(source.get_size())).clamp(Vector2i.ZERO, source.get_size() - Vector2i.ONE)
	return maxf((source.get_pixelv(pixel).a * 255.0 - 128.0) / 127.0, 0.0)

static func support_at(index: Dictionary, source: Image, position: Vector2) -> float:
	var aspect: float = index.aspect
	var radius: float = index.radius
	var terrain_connected: bool = index.get("terrain_connected",false)
	var p := position * Vector2(aspect, 1.0)
	var candidates: Array = index.buckets.get(Vector2i((p / BUCKET).floor()), [])
	if candidates.is_empty(): return 0.0
	var source_size := source.get_size()
	var source_scale := Vector2(source_size)
	var pixel := Vector2i(position * source_scale).clamp(Vector2i.ZERO, source_size - Vector2i.ONE)
	var height := maxf((source.get_pixelv(pixel).a * 255.0 - 128.0) / 127.0, 0.0)
	var result := 0.0
	var starts: PackedVector2Array = index.starts
	var deltas: PackedVector2Array = index.deltas
	var inverse_lengths: PackedFloat64Array = index.inverse_lengths
	for id in candidates:
		var a := starts[id]
		var delta := deltas[id]
		var ratio := clampf((p - a).dot(delta) * inverse_lengths[id], 0.0, 1.0)
		var nearest := a + delta * ratio
		var distance_squared := p.distance_squared_to(nearest)
		if distance_squared >= radius * radius: continue
		var distance_support := 1.0 - smoothstep(0.0, radius, sqrt(distance_squared))
		if distance_support <= result: continue
		var river_pixel := Vector2i(nearest / Vector2(aspect, 1.0) * source_scale).clamp(Vector2i.ZERO, source_size - Vector2i.ONE)
		var river_height := maxf((source.get_pixelv(river_pixel).a * 255.0 - 128.0) / 127.0, 0.0)
		var rise := maxf(height - river_height, 0.0)
		var strength := distance_support * (1.0 - smoothstep(BANK_RISE_FULL, BANK_RISE_LIMIT, rise))
		# A blocked or weaker candidate cannot change the maximum. Avoid an
		# expensive source-resolution ridge scan until height/distance qualify it.
		if strength <= result: continue
		if terrain_connected and not clear_connection(source,position,nearest/Vector2(aspect,1.0)): continue
		result = strength
	return result

## Conservative AABB coverage: a zero cell cannot contain any supported jitter.
static func potential_cells(index: Dictionary, size: Vector2i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(size.x * size.y)
	var scale := Vector2(size) / Vector2(index.aspect, 1.0)
	var radius: float = index.radius
	var starts: PackedVector2Array = index.starts
	var deltas: PackedVector2Array = index.deltas
	for id in range(starts.size()):
		var a := starts[id]
		var b := a + deltas[id]
		var first := Vector2i(((a.min(b) - Vector2.ONE * radius) * scale).floor()).max(Vector2i.ZERO)
		var last := Vector2i(((a.max(b) + Vector2.ONE * radius) * scale).floor()).min(size - Vector2i.ONE)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1): result[y * size.x + x] = 1
	return result

static func suitability(environment: Dictionary, cell: int, water: float) -> float:
	var moisture := clampf(environment.rainfed[cell] + water * 0.65, 0.0, 1.0)
	return environment.cold[cell] * pow(smoothstep(0.10, 0.65, moisture), 1.5) * environment.flatness[cell] * (0.15 + 0.85 * environment.farmland[cell])

static func clear_connection(source: Image, a: Vector2, b: Vector2) -> bool:
	var size := source.get_size()
	var p := a * Vector2(size)
	var q := b * Vector2(size)
	var ceiling := maxf(height_at(source,a),height_at(source,b)) + BANK_RISE_LIMIT
	var steps := maxi(1,ceili(maxf(absf(q.x-p.x),absf(q.y-p.y))))
	for step in range(steps+1):
		var pixel := Vector2i(p.lerp(q,float(step)/steps)).clamp(Vector2i.ZERO,size-Vector2i.ONE)
		var alpha := source.get_pixelv(pixel).a*255.0
		if alpha <= 128.0 or (alpha-128.0)/127.0 > ceiling: return false
	return true

