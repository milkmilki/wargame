class_name SettlementEnvironment
extends RefCounted
## Deterministic climate, followed by optional terrain hydrology and water support.
const VERSION := "environment_v1.7"
const ELEVATION_KM := 6.2
const RAIN_BARRIER_START_KM := 2.5
const RAIN_BARRIER_FULL_KM := 3.5
static var _cache: Dictionary = {}
const Hydrology = preload("res://scripts/core/terrain_hydrology.gd")
const VectorHydro = preload("res://scripts/core/vector_hydrology.gd")
const RiverSupport = preload("res://scripts/core/river_settlement_support.gd")
const ValleySupport = preload("res://scripts/core/valley_water_support.gd")

static func build(source: Image, analysis: Image, land: PackedByteArray, latitudes: PackedFloat32Array, aspect: float, identity: String, hydrological: bool = false, network_path: String = "", external_inflow: bool = false, river_settlement_model: String = "flow_weighted", river_radius: float = RiverSupport.RADIUS) -> Dictionary:
	var started := Time.get_ticks_usec()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(source.get_data())
	context.update(analysis.get_data())
	context.update(land)
	context.update(latitudes.to_byte_array())
	context.update((VERSION + identity + str(analysis.get_size()) + str(aspect)).to_utf8_buffer())
	context.update((river_settlement_model + RiverSupport.cache_identity(river_radius)).to_utf8_buffer())
	if river_settlement_model == "valley_v1": context.update(ValleySupport.cache_identity().to_utf8_buffer())
	if hydrological: context.update(Hydrology.VERSION.to_utf8_buffer())
	if not network_path.is_empty(): context.update((VectorHydro.VERSION + str(VectorHydro.network(network_path).network_id) + str(external_inflow)).to_utf8_buffer())
	var key := context.finish().hex_encode()
	if _cache.has(key):
		var cached: Dictionary = _cache[key].duplicate()
		cached["cache_hit"] = true
		cached["elapsed_usec"] = Time.get_ticks_usec() - started
		return cached
	var heights := PackedFloat32Array()
	var size := analysis.get_size()
	heights.resize(land.size())
	var fine_relief := PackedFloat32Array()
	fine_relief.resize(land.size())
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			heights[i] = maxf((analysis.get_pixel(x, y).a * 255.0 - 128.0) / 127.0, 0.0)
			if land[i] == 0:
				continue
			var center := Vector2i((Vector2(x, y) + Vector2(0.5, 0.5)) * Vector2(source.get_size()) / Vector2(size))
			var low := 1.0
			var high := 0.0
			for dy in [-2, 0, 2]:
				for dx in [-2, 0, 2]:
					var p := (center + Vector2i(dx, dy)).clamp(Vector2i.ZERO, source.get_size() - Vector2i.ONE)
					var alpha := source.get_pixelv(p).a * 255.0
					if alpha <= 128.0:
						continue
					var h := (alpha - 128.0) / 127.0
					low = minf(low, h)
					high = maxf(high, h)
			fine_relief[i] = maxf(high - low, 0.0)
	var result := evaluate(heights, land, size, latitudes, aspect, fine_relief, hydrological)
	result["environment_id"] = key
	if hydrological:
		if network_path.is_empty():
			result["drainage_heights"] = Hydrology.drainage_heights(source, size)
			result["hydrology"] = Hydrology.build(result, aspect)
		else:
			# Mean evaporation is not a hard gate that eliminates all episodic
			# runoff in a dry catchment. This does not impose a city-density floor.
			for i in range(result.local_runoff.size()):
				var evaporation := 0.35 + 0.025 * maxf(result.temperature[i] + 5.0, 0.0)
				result.local_runoff[i] = result.rainfall[i] * clampf(0.15 + 0.65 * result.rainfall[i] / evaporation, 0.15, 0.8)
			result["hydrology"] = VectorHydro.build(result, aspect, network_path, external_inflow, source)
		if river_settlement_model in ["uniform_v1","valley_v1"]:
			var support_started := Time.get_ticks_usec()
			result["river_support_index"] = RiverSupport.build_index(result.hydrology.features, aspect, river_radius)
			result["river_support_possible"] = RiverSupport.potential_cells(result.river_support_index, size)
			if river_settlement_model == "valley_v1":
				result.river_support_index["terrain_connected"] = true
				result["valley_support"] = ValleySupport.build(source,result,result.river_support_index,aspect)
				# Connected propagation can reach outside the direct bank radius.
				for i in range(land.size()):
					if result.valley_support.support[i]>0.0: result.river_support_possible[i]=1
			result["water"] = _field(land.size())
			result["suitability"] = _field(land.size())
			var rainfed_suitability := PackedFloat64Array()
			var maximum_suitability := PackedFloat64Array()
			rainfed_suitability.resize(land.size())
			maximum_suitability.resize(land.size())
			for i in range(land.size()):
				if land[i] == 0: continue
				var position := (Vector2(i % size.x, i / size.x) + Vector2.ONE * 0.5) / Vector2(size)
				result.water[i] = RiverSupport.support_at(result.river_support_index, source, position)
				if result.has("valley_support"): result.water[i]=maxf(result.water[i],result.valley_support.support[i])
				result.suitability[i] = RiverSupport.suitability(result, i, result.water[i])
				rainfed_suitability[i] = RiverSupport.suitability(result, i, 0.0)
				maximum_suitability[i] = RiverSupport.suitability(result, i, 1.0)
			result["rainfed_suitability"] = rainfed_suitability
			result["maximum_suitability"] = maximum_suitability
			result["components"] = Hydrology.components(land, size, result.hydrology.blocked_edges)
			result["river_support_usec"] = Time.get_ticks_usec() - support_started
		else:
			_apply_hydrology(result, aspect)
	result["river_settlement_model"] = river_settlement_model
	result["cache_hit"] = false
	result["elapsed_usec"] = Time.get_ticks_usec() - started
	# Bound memory while allowing China/old/new map round-trips.
	if _cache.size() >= 8:
		_cache.erase(_cache.keys()[0])
	_cache[key] = result
	return result.duplicate()

static func evaluate(heights: PackedFloat32Array, land: PackedByteArray, size: Vector2i, latitudes: PackedFloat32Array, aspect: float, fine_relief: PackedFloat32Array = PackedFloat32Array(), climate_only: bool = false) -> Dictionary:
	assert(heights.size() == size.x * size.y and land.size() == heights.size() and latitudes.size() == size.y)
	var count := heights.size()
	var distance := _sea_distance(land, size, aspect)
	var temperature := _field(count)
	var winter := _field(count)
	var continentality := _field(count)
	var cold := _field(count)
	var relief := _field(count)
	var flatness := _field(count)
	var farmland := _field(count)
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			continentality[i] = 1.0 - exp(-distance[i] / 0.12)
			temperature[i] = 28.0 - 0.42 * absf(latitudes[y]) - 6.0 * heights[i] * ELEVATION_KM
			winter[i] = temperature[i] - (4.0 + 14.0 * continentality[i]) * smoothstep(15.0, 55.0, absf(latitudes[y]))
			cold[i] = pow(smoothstep(-25.0, 5.0, winter[i]), 3.0)
			# Beyond 60 degrees even a mild coast has a short growing season.
			cold[i] *= 1.0 - smoothstep(60.0, 75.0, absf(latitudes[y]))
			var lo := heights[i]
			var hi := lo
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx := clampi(x + dx, 0, size.x - 1)
					var yy := clampi(y + dy, 0, size.y - 1)
					var j := yy * size.x + xx
					if land[j] != 0:
						lo = minf(lo, heights[j])
						hi = maxf(hi, heights[j])
			relief[i] = hi - lo
			var local_relief := fine_relief[i] if fine_relief.size() == count else relief[i]
			flatness[i] = 1.0 - smoothstep(0.015, 0.16, local_relief)
	for y in range(size.y):
		for x in range(size.x):
			var usable := 0.0
			var samples := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var xx := x + dx
					var yy := y + dy
					if xx < 0 or yy < 0 or xx >= size.x or yy >= size.y:
						continue
					var j := yy * size.x + xx
					usable += flatness[j] * float(land[j])
					samples += 1
			farmland[y * size.x + x] = usable / maxi(samples, 1)
	var rainfall := _rainfall(heights, land, size, latitudes, aspect)
	var aridity := _field(count)
	var runoff := _field(count)
	var rainfed := _field(count)
	for i in range(count):
		var evaporation := 0.35 + 0.025 * maxf(temperature[i] + 5.0, 0.0)
		var balance := rainfall[i] / evaporation
		aridity[i] = 1.0 - smoothstep(0.08, 0.70, balance)
		rainfed[i] = clampf(balance, 0.0, 1.0)
		runoff[i] = maxf(rainfall[i] - evaporation * 0.20, 0.0)
	if climate_only:
		return {"size": size, "heights": heights, "land": land, "latitudes": latitudes, "temperature": temperature, "winter_temperature": winter, "continentality": continentality, "cold": cold, "rainfall": rainfall, "aridity": aridity, "local_runoff": runoff, "rainfed": rainfed, "flatness": flatness, "farmland": farmland, "relief": relief}
	var flow := accumulate_runoff(heights, land, size, runoff, aspect)
	var water := _field(count)
	var suitability := _field(count)
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			if land[i] == 0:
				continue
			var supply := flow[i]
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < size.x and yy < size.y:
						supply = maxf(supply, flow[yy * size.x + xx] * 0.65)
			water[i] = clampf(log(1.0 + supply) / log(65.0), 0.0, 1.0)
			var moisture := clampf(rainfed[i] + water[i] * 0.65, 0.0, 1.0)
			# Settlement support saturates once supply is adequate. Squaring all
			# moisture values made ordinary inland plains permanently second-rate,
			# while also enlarging their spacing in the weighted city sampler.
			var water_support := pow(smoothstep(0.10, 0.65, moisture), 1.5)
			suitability[i] = cold[i] * water_support * flatness[i] * (0.15 + 0.85 * farmland[i])
	return {"size": size, "heights": heights, "land": land, "latitudes": latitudes, "temperature": temperature, "winter_temperature": winter, "continentality": continentality, "cold": cold, "rainfall": rainfall, "aridity": aridity, "runoff": flow, "water": water, "farmland": farmland, "relief": relief, "suitability": suitability}

static func _apply_hydrology(environment: Dictionary, aspect: float) -> void:
	var size: Vector2i = environment.size
	var hydro: Dictionary = environment.hydrology
	var vertices: Vector2i = hydro.size
	var water := _field(size.x * size.y)
	var suitability := _field(water.size())
	var radius := 0.025
	var rx := int(ceil(radius * size.x / aspect))
	var ry := int(ceil(radius * size.y))
	for node in range(hydro.flow.size()):
		if hydro.flow[node] <= 0.0 or (not hydro.has("dem_size") and hydro.flow[node] < Hydrology.MINOR_FLOW): continue
		# Terminal sea nodes do not water adjacent land from the ocean a second time.
		if hydro.terminal_kind[node] == "sea": continue
		var x := node % vertices.x
		var y := node / vertices.x
		var supply := clampf(log(1.0 + hydro.flow[node] / Hydrology.MINOR_FLOW) / log(17.0), 0.0, 1.0)
		for yy in range(maxi(0, y - ry), mini(size.y, y + ry + 1)):
			for xx in range(maxi(0, x - rx), mini(size.x, x + rx + 1)):
				var i: int = yy * size.x + xx
				if environment.land[i] == 0: continue
				var distance := Vector2((xx + 0.5 - x) * aspect / size.x, (yy + 0.5 - y) / size.y).length()
				if distance >= radius: continue
				var rise := maxf(environment.heights[i] - hydro.heights[node], 0.0)
				var support := supply * (1.0 - smoothstep(0.0, radius, distance)) * (1.0 - smoothstep(0.003, 0.04, rise))
				water[i] = maxf(water[i], support)
	for i in range(water.size()):
		if environment.land[i] == 0: continue
		var moisture := clampf(environment.rainfed[i] + water[i] * 0.65, 0.0, 1.0)
		suitability[i] = environment.cold[i] * pow(smoothstep(0.10, 0.65, moisture), 1.5) * environment.flatness[i] * (0.15 + 0.85 * environment.farmland[i])
	environment.water = water
	environment.suitability = suitability
	environment.components = Hydrology.components(environment.land, size, hydro.blocked_edges)

static func _field(count: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(count)
	return result

static func _sea_distance(land: PackedByteArray, size: Vector2i, aspect: float) -> PackedFloat32Array:
	var result := _field(land.size())
	result.fill(1000.0)
	var dx := aspect / float(size.x)
	var dy := 1.0 / float(size.y)
	for i in range(land.size()):
		if land[i] == 0:
			result[i] = 0.0
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			if x > 0:
				result[i] = minf(result[i], result[i - 1] + dx)
			if y > 0:
				result[i] = minf(result[i], result[i - size.x] + dy)
	for y in range(size.y - 1, -1, -1):
		for x in range(size.x - 1, -1, -1):
			var i := y * size.x + x
			if x + 1 < size.x:
				result[i] = minf(result[i], result[i + 1] + dx)
			if y + 1 < size.y:
				result[i] = minf(result[i], result[i + size.x] + dy)
	return result

static func _rainfall(heights: PackedFloat32Array, land: PackedByteArray, size: Vector2i, latitudes: PackedFloat32Array, aspect: float) -> PackedFloat32Array:
	var result := _field(land.size())
	var seasonal := _field(land.size())
	var water_mask := PackedByteArray()
	water_mask.resize(land.size())
	for i in range(land.size()):
		water_mask[i] = 1 - land[i]
	# Offshore distance is a local water-width proxy. A narrow channel cannot
	# reset a parcel to ocean humidity after a single raster cell.
	var offshore := _sea_distance(water_mask, size, aspect)
	var rain_efficiency := _field(size.y)
	var summer_strength := _field(size.y)
	for y in range(size.y):
		var latitude := absf(latitudes[y])
		# Smooth subtropical subsidence, with no region names or exclusion masks.
		rain_efficiency[y] = 1.0 - 0.82 * exp(-pow((latitude - 27.0) / 7.0, 2.0))
		# In low latitudes easterly transport is already the prevailing term.
		# Do not count it again at full strength as an extra wet season; the
		# seasonal reversal grows toward the temperate transition, then fades.
		summer_strength[y] = smoothstep(18.0, 30.0, latitude) * (1.0 - smoothstep(40.0, 50.0, latitude))
	# Four bounded advection sweeps. Latitude weights vary continuously, so no
	# artificial horizontal climate seam appears where prevailing winds change.
	for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var horizontal: bool = step.x != 0
		var positive: bool = step.x + step.y > 0
		var line_count: int = size.y if horizontal else size.x
		var line_length: int = size.x if horizontal else size.y
		var step_length: float = aspect / size.x if horizontal else 1.0 / size.y
		var recharge := 1.0 - exp(-step_length / 0.08)
		var retention := exp(-step_length)
		var humidity := _field(line_count)
		humidity.fill(0.25)
		for n in range(line_length):
			var offset: int = n if positive else line_length - 1 - n
			var next_humidity := _field(line_count)
			for line in range(line_count):
				var x: int = offset if horizontal else line
				var y: int = line if horizontal else offset
				var i := y * size.x + x
				# Lateral mixing prevents cardinal wind sweeps from painting hard
				# stripes behind coastline corners. Edges reflect, never add ocean.
				var moisture := humidity[line] * 0.6 + humidity[maxi(line - 1, 0)] * 0.2 + humidity[mini(line + 1, line_count - 1)] * 0.2
				var westerly := smoothstep(25.0, 40.0, absf(latitudes[y]))
				var weight: float
				if horizontal:
					weight = lerpf(0.20, 0.50, westerly) if positive else lerpf(0.50, 0.20, westerly)
				else:
					var poleward: bool = (step.y < 0) == (latitudes[y] >= 0.0)
					weight = 0.25 if poleward else 0.05
				if land[i] == 0:
					var breadth := smoothstep(0.0, 0.08, offshore[i])
					next_humidity[line] = moisture + (1.0 - moisture) * recharge * breadth
					continue
				# Low/mid-altitude terrain transports moisture without an orographic
				# deduction. Only mountains around 3000m become an effective barrier;
				# a smooth transition avoids a sharp rainfall seam at one elevation.
				var elevation_km := heights[i] * ELEVATION_KM
				var barrier := smoothstep(RAIN_BARRIER_START_KM, RAIN_BARRIER_FULL_KM, elevation_km)
				var capacity := exp(-elevation_km * barrier * 0.8)
				var condensation := maxf(moisture - capacity, 0.0)
				result[i] += weight * (moisture * 0.95 * rain_efficiency[y] + condensation * 2.0)
				# A moist growing season can support settlements even when the
				# prevailing annual flow is dry. Only actual transported water
				# activates this support; subtropical latitude alone never does.
				var warm_onshore: bool = (horizontal and not positive) or (not horizontal and ((step.y < 0) == (latitudes[y] >= 0.0)))
				if warm_onshore:
					var available := moisture - condensation
					# Poleward seasonal transport is weaker than the main moist
					# easterly flow; it must not overwhelm the dry subtropical belt.
					var seasonal_flow := 1.0 if horizontal else 0.35
					var summer_rain := available * smoothstep(0.35, 0.65, available) * 0.95 * summer_strength[y] * seasonal_flow
					seasonal[i] = maxf(seasonal[i], summer_rain)
				# Broad weather systems reach inland plains before losing all water.
				next_humidity[line] = (moisture - condensation) * retention
			humidity = next_humidity

	for i in range(result.size()):
		result[i] = maxf(result[i], seasonal[i])
	return result


## Route flats toward an existing lower outlet, but retain genuinely closed basins.
## Every downstream edge decreases (height, flat-rank), so accumulation is acyclic.
static func accumulate_runoff(heights: PackedFloat32Array, land: PackedByteArray, size: Vector2i, rain: PackedFloat32Array, aspect: float) -> PackedFloat32Array:
	var count := heights.size()
	var downstream := PackedInt32Array()
	downstream.resize(count)
	downstream.fill(-1)
	var rank := PackedInt32Array()
	rank.resize(count)
	rank.fill(-1)
	var queue := PackedInt32Array()
	var order: Array[int] = []
	var steps: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			if land[i] == 0:
				continue
			order.append(i)
			var best := 0.0
			for step in steps:
				var p := Vector2i(x, y) + step
				if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y:
					continue
				var j := p.y * size.x + p.x
				var h := heights[j] if land[j] != 0 else -1.0
				var length := aspect / size.x if step.x != 0 else 1.0 / size.y
				var slope := (heights[i] - h) / length
				if slope > best:
					best = slope
					downstream[i] = j
			if downstream[i] >= 0:
				rank[i] = 0
				queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var p := Vector2i(i % size.x, i / size.x)
		for step in steps:
			var q := p + step
			if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y:
				continue
			var j := q.y * size.x + q.x
			if land[j] != 0 and rank[j] < 0 and heights[j] == heights[i]:
				downstream[j] = i
				rank[j] = rank[i] + 1
				queue.append(j)
	order.sort_custom(func(a: int, b: int) -> bool:
		if heights[a] != heights[b]:
			return heights[a] > heights[b]
		if rank[a] != rank[b]:
			return rank[a] > rank[b]
		return a < b
	)
	var result := rain.duplicate()
	for i in order:
		var j := downstream[i]
		if j >= 0 and land[j] != 0:
			result[j] += result[i]
	return result
