class_name NationEnvironment
extends RefCounted
## Founding geography is immutable. Classification uses the existing Atlas mesh;
## no simulation randomness or daily map scan is involved.
const VERSION := "environment-v1"
const KINDS := ["farm", "nomad", "sea", "highland", "river", "lake", "forest"]
const LABELS := {"farm":"农耕", "nomad":"游牧", "sea":"海洋", "highland":"高原", "river":"河谷", "lake":"湖泽", "forest":"山林"}

static func classify(features: Dictionary) -> String:
	var biome := int(features.get("biome", 9))
	var elevation := float(features.get("elevation", 0.0))
	if biome in [6,7,8,11] and elevation < 1500.0: return "nomad"
	if elevation > 1300.0: return "highland"
	if bool(features.get("lake", false)): return "lake"
	if bool(features.get("coast", false)):
		var probability := 0.35 if bool(features.get("harbor",false)) else (0.40 if bool(features.get("island",false)) else 0.08)
		if float(features.get("sea_roll",1.0)) < probability: return "sea"
	if bool(features.get("major_river",false)): return "river"
	if int(features.get("coast_distance",127)) > 3 and biome in [4,5,10,14,15]: return "forest"
	return "farm"

static func prepare(data: Dictionary, hierarchy: Dictionary) -> Dictionary:
	var mesh: Dictionary = data.mesh
	var env: Dictionary = data.environment
	var regions: Dictionary = data.regions
	var big_lake := PackedByteArray(); big_lake.resize(mesh.n)
	var seen := PackedByteArray(); seen.resize(mesh.n)
	for cell in range(mesh.n):
		if env.water[cell] != 2 or seen[cell]: continue
		var water_cells: Array[int] = [cell]; seen[cell] = 1
		var head := 0
		while head < water_cells.size():
			var current := water_cells[head]; head += 1
			for slot in range(mesh.adj_start[current],mesh.adj_start[current+1]):
				var neighbor: int = mesh.adj[slot]
				if env.water[neighbor] == 2 and not seen[neighbor]:
					seen[neighbor] = 1; water_cells.append(neighbor)
		if water_cells.size() >= 5:
			for water_cell in water_cells: big_lake[water_cell] = 1
	# Preserve habitat coast distances when available; legacy templates derive the
	# same distances in one multi-source traversal, without rebuilding habitat.
	var coast := PackedInt32Array(env.get("coastDist",PackedInt32Array()))
	if coast.size() != mesh.n:
		coast = PackedInt32Array(); coast.resize(mesh.n); coast.fill(127)
		var queue: Array[int] = []
		for cell in range(mesh.n):
			if env.water[cell] == 1: coast[cell] = 0; queue.append(cell)
		var head := 0
		while head < queue.size():
			var current := queue[head]; head += 1
			for slot in range(mesh.adj_start[current],mesh.adj_start[current+1]):
				var neighbor: int = mesh.adj[slot]
				if coast[neighbor] > coast[current]+1:
					coast[neighbor] = coast[current]+1; queue.append(neighbor)
	var provinces_by_landmass := {}
	for landmass in regions.landmass:
		provinces_by_landmass[landmass] = int(provinces_by_landmass.get(landmass,0))+1
	var profiles := {}
	for center in range(hierarchy.cities.size()):
		var source: Dictionary = hierarchy.cities[center]
		if source.role != "zhou": continue
		var parent: int = source.region; var cell: int = source.cell
		var sea_neighbors := 0; var lake := false
		var major_river: bool = float(env.flux[cell]) >= 6.0*float(env.riverThreshold)
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var neighbor: int = mesh.adj[slot]
			if env.water[neighbor] == 1: sea_neighbors += 1
			if big_lake[neighbor]: lake = true
			if env.water[neighbor] == 0 and float(env.flux[neighbor]) >= 6.0*float(env.riverThreshold): major_river = true
		var agriculture := 0.0; var land_area := 0.0
		for slot in range(regions.cellStart[parent],regions.cellStart[parent+1]):
			var member: int = regions.cells[slot]
			if env.water[member] != 0: continue
			var area: float = mesh.areas[member]; land_area += area
			var suitability: float = env.get("agricultural_potential",env.suitability)[member]
			# Original habitat suitability has a different scale from climate potential.
			suitability /= 110.0 if env.has("agricultural_potential") else 22.0
			agriculture += clampf(suitability,0.0,1.0)*area
		var features := {"biome":int(regions.biome[parent]),"elevation":float(regions.elevation[parent]),
			"lake":lake,"coast":sea_neighbors>0,"harbor":sea_neighbors==1,
			"island":int(provinces_by_landmass[regions.landmass[parent]])<=6,
			"major_river":major_river,"coast_distance":coast[cell],"area":land_area,
			"agriculture":agriculture/maxf(land_area,0.000001)}
		# Stable hash is local to map creation, and independent of simulation RNG.
		var hex := ("%s:%d:%d"%[VERSION,int(data.seed),parent]).sha256_text().left(8)
		features.sea_roll = float(hex.hex_to_int())/4294967296.0
		features.kind = classify(features)
		features.affinities = affinities(features)
		profiles[center] = features
	return {"version":VERSION,"profiles":profiles}

static func affinities(features: Dictionary) -> Dictionary:
	var biome := int(features.get("biome",9))
	return {"farm":clampf(float(features.get("agriculture",0.0)),0.0,1.0),
		"nomad":1.0 if biome in [6,7,8,11,12] else 0.0,
		"highland":clampf(float(features.get("elevation",0.0))/1500.0,0.0,1.0),
		"sea":1.0 if bool(features.get("coast",false)) else 0.0,
		"river":1.0 if bool(features.get("major_river",false)) else 0.0,
		"lake":1.0 if bool(features.get("lake",false)) else 0.0,
		"forest":1.0 if biome in [4,5,9,10,13,14,15] else 0.0}

static func profile(state, city_id: int) -> Dictionary:
	if state.atlas_layout.is_empty(): return {}
	var center: int = state.administrative_center_of(city_id)
	return state.atlas_layout.get("nation_environment",{}).get("profiles",{}).get(center,{})

static func founding_kind(state, city_id: int) -> String:
	return str(profile(state,city_id).get("kind","farm"))

static func affinity(state, nation_id: int, center_id: int) -> float:
	return float(profile(state,center_id).get("affinities",{}).get(state.nations[nation_id].environment_kind,0.0))

static func region_affinity(state, nation_id: int, region_id: int) -> float:
	var profiles: Dictionary = state.atlas_layout.get("nation_environment",{}).get("profiles",{})
	if profiles.is_empty(): return 0.0
	var revision: int = state.region_analysis_revision
	var cache: Dictionary = state.get_meta("environment_regions",{})
	if cache.get("revision",-1) != revision:
		var totals := {}; var areas := {}
		for center in profiles:
			var p: Dictionary = profiles[center]
			var region: int = state.region_ids[int(center)]
			var values: Dictionary = totals.get(region,{})
			for kind in KINDS: values[kind] = float(values.get(kind,0.0))+float(p.affinities[kind])*float(p.area)
			totals[region] = values; areas[region] = float(areas.get(region,0.0))+float(p.area)
		cache = {"revision":revision,"totals":totals,"areas":areas}; state.set_meta("environment_regions",cache)
	return float(cache.totals.get(region_id,{}).get(state.nations[nation_id].environment_kind,0.0))/maxf(float(cache.areas.get(region_id,0.0)),0.000001)
