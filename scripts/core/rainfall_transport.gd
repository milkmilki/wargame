extends RefCounted
## Shared rainfall transport extracted from SettlementEnvironment environment_v1.7.
## Defaults retain the regional model exactly; globe options adapt distance/wrap.
const VERSION := "legacy_monsoon_global_v1"
const ELEVATION_KM := 6.2
const RAIN_BARRIER_START_KM := 2.5
const RAIN_BARRIER_FULL_KM := 3.5

static func _field(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(count); return out

static func build(heights: PackedFloat32Array, land: PackedByteArray, size: Vector2i, latitudes: PackedFloat32Array, aspect: float, options: Dictionary = {}) -> PackedFloat32Array:
	return build_fields(heights,land,size,latitudes,aspect,options).rainfall

static func _sea_distance(land: PackedByteArray, size: Vector2i, aspect: float, latitudes: PackedFloat32Array = PackedFloat32Array(), latitude_distance: bool = false) -> PackedFloat32Array:
	var result := _field(land.size())
	result.fill(1000.0)
	var dx := aspect / float(size.x)
	var dy := 1.0 / float(size.y)
	for i in range(land.size()):
		if land[i] == 0:
			result[i] = 0.0
	for y in range(size.y):
		var row_dx := dx*maxf(.05,cos(deg_to_rad(latitudes[y]))) if latitude_distance else dx
		for x in range(size.x):
			var i := y * size.x + x
			if x > 0:
				result[i] = minf(result[i], result[i - 1] + row_dx)
			if y > 0:
				result[i] = minf(result[i], result[i - size.x] + dy)
	for y in range(size.y - 1, -1, -1):
		var row_dx := dx*maxf(.05,cos(deg_to_rad(latitudes[y]))) if latitude_distance else dx
		for x in range(size.x - 1, -1, -1):
			var i := y * size.x + x
			if x + 1 < size.x:
				result[i] = minf(result[i], result[i + 1] + row_dx)
			if y + 1 < size.y:
				result[i] = minf(result[i], result[i + size.x] + dy)
	return result

static func build_fields(heights: PackedFloat32Array, land: PackedByteArray, size: Vector2i, latitudes: PackedFloat32Array, aspect: float, options: Dictionary = {}) -> Dictionary:
	var result := _field(land.size())
	var seasonal := _field(land.size())
	var water_mask := PackedByteArray()
	water_mask.resize(land.size())
	for i in range(land.size()):
		water_mask[i] = 1 - land[i]
	# Offshore distance is a local water-width proxy. A narrow channel cannot
	# reset a parcel to ocean humidity after a single raster cell.
	var wrap_x: bool = options.get("wrap_x",false)
	var distance_scale: float = options.get("distance_scale",1.)
	var latitude_distance: bool = options.get("latitude_distance",false)
	var offshore: PackedFloat32Array
	if wrap_x:
		var expanded := PackedByteArray(); expanded.resize(land.size()*3)
		for y in range(size.y):
			for x in range(size.x*3): expanded[y*size.x*3+x] = water_mask[y*size.x+x%size.x]
		var field := _sea_distance(expanded,Vector2i(size.x*3,size.y),aspect*3,latitudes,latitude_distance)
		offshore = _field(land.size())
		for y in range(size.y):
			for x in range(size.x): offshore[y*size.x+x] = field[y*size.x*3+size.x+x]*distance_scale
	else:
		offshore = _sea_distance(water_mask,size,aspect,latitudes,latitude_distance)
		if distance_scale!=1.:
			for i in range(offshore.size()): offshore[i] *= distance_scale
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
		var step_length: float = (aspect / size.x if horizontal else 1.0 / size.y)*distance_scale
		var recharge := 1.0 - exp(-step_length / 0.08)
		var retention := exp(-step_length)
		var humidity := _field(line_count)
		humidity.fill(0.25)
		var cycles := 3 if wrap_x and horizontal else 1
		for n in range(line_length*cycles):
			var record := n>=line_length*(cycles-1)
			var offset: int = n%line_length if positive else line_length - 1 - n%line_length
			var next_humidity := _field(line_count)
			for line in range(line_count):
				var x: int = offset if horizontal else line
				var y: int = line if horizontal else offset
				var i := y * size.x + x
				# Lateral mixing prevents cardinal wind sweeps from painting hard
				# stripes behind coastline corners. Edges reflect, never add ocean.
				var left := posmod(line-1,line_count) if wrap_x and not horizontal else maxi(line-1,0)
				var right := (line+1)%line_count if wrap_x and not horizontal else mini(line+1,line_count-1)
				var moisture := humidity[line] * 0.6 + humidity[left] * 0.2 + humidity[right] * 0.2
				var row_step := step_length*maxf(.05,cos(deg_to_rad(latitudes[y]))) if horizontal and latitude_distance else step_length
				var recharge_here := 1.-exp(-row_step/.08) if latitude_distance and horizontal else recharge
				var retention_here := exp(-row_step) if latitude_distance and horizontal else retention
				var westerly := smoothstep(25.0, 40.0, absf(latitudes[y]))
				var weight: float
				if horizontal:
					weight = lerpf(0.20, 0.50, westerly) if positive else lerpf(0.50, 0.20, westerly)
				else:
					var poleward: bool = (step.y < 0) == (latitudes[y] >= 0.0)
					weight = 0.25 if poleward else 0.05
				if land[i] == 0:
					var breadth := smoothstep(0.0, 0.08, offshore[i])
					next_humidity[line] = moisture + (1.0 - moisture) * recharge_here * breadth
					continue
				# Low/mid-altitude terrain transports moisture without an orographic
				# deduction. Only mountains around 3000m become an effective barrier;
				# a smooth transition avoids a sharp rainfall seam at one elevation.
				var elevation_km := heights[i] * ELEVATION_KM
				var barrier := smoothstep(RAIN_BARRIER_START_KM, RAIN_BARRIER_FULL_KM, elevation_km)
				var capacity := exp(-elevation_km * barrier * 0.8)
				var condensation := maxf(moisture - capacity, 0.0)
				if record: result[i] += weight * (moisture * 0.95 * rain_efficiency[y] + condensation * 2.0)
				# A moist growing season can support settlements even when the
				# prevailing annual flow is dry. Only actual transported water
				# activates this support; subtropical latitude alone never does.
				var warm_onshore: bool = (horizontal and not positive) or (not horizontal and ((step.y < 0) == (latitudes[y] >= 0.0)))
				if warm_onshore and record:
					var available := moisture - condensation
					# Poleward seasonal transport is weaker than the main moist
					# easterly flow; it must not overwhelm the dry subtropical belt.
					var seasonal_flow := 1.0 if horizontal else 0.35
					var summer_rain := available * smoothstep(0.35, 0.65, available) * 0.95 * summer_strength[y] * seasonal_flow
					seasonal[i] = maxf(seasonal[i], summer_rain)
				# Broad weather systems reach inland plains before losing all water.
				next_humidity[line] = (moisture - condensation) * retention_here
			humidity = next_humidity

	var annual := result.duplicate()
	for i in range(result.size()):
		result[i] = maxf(result[i], seasonal[i])
	return {"rainfall":result,"annual":annual,"seasonal":seasonal}

