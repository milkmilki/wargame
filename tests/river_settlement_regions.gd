extends SceneTree
const Env = preload("res://scripts/core/settlement_environment.gd")
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
const Support = preload("res://scripts/core/river_settlement_support.gd")
const OLD := "res://assets/terrain/eurasia_hydrology_map_source.json"
var NEW: String = OS.get_environment("HYDROLOGY_SOURCE") if not OS.get_environment("HYDROLOGY_SOURCE").is_empty() else "res://assets/terrain/eurasia_uniform_river_map_source.json"
const SEEDS := [2342006650, 12345, 23456, 34567, 45678, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
const WINDOWS := [Rect2(103,28,5,5), Rect2(106,33,6,3), Rect2(108,29,10,8), Rect2(0,20,30,9), Rect2(40,20,10,9)]
const NAMES := ["sichuan", "guanzhong", "central_china", "sahara", "arabia"]
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var source := (load(MapSource.texture_path(NEW)) as Texture2D).get_image()
	var analysis := source.duplicate()
	analysis.resize(256,256,Image.INTERPOLATE_NEAREST)
	var land: PackedByteArray = TerrainMapGenerator._all_land_geometry(analysis).mask
	var latitudes := PackedFloat32Array()
	for y in range(256): latitudes.append(MapSource.latitude_at_y((y+.5)/256.0,18,57,NEW))
	var aspect := MapSource.aspect_ratio(NEW)
	var old := Env.build(source,analysis,land,latitudes,aspect,"web_mercator",true,MapSource.hydrology_network(OLD),true)
	var current := Env.build(source,analysis,land,latitudes,aspect,"web_mercator",true,MapSource.hydrology_network(NEW),true,MapSource.river_settlement_model(NEW))
	assert(old.hydrology.features == current.hydrology.features and old.hydrology.flow == current.hydrology.flow)
	var reserved := TerrainMapGenerator._reserve_hydrology_docks(current,analysis,aspect,500)
	var regions := PackedInt32Array()
	regions.resize(land.size())
	regions.fill(-1)
	var eligible := PackedByteArray()
	eligible.resize(land.size())
	var dry := PackedByteArray()
	dry.resize(land.size())
	var area := [0,0,0,0,0]
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/river_settlement_fixed_samples.json"))
	assert(FileAccess.get_sha256(MapSource.texture_path(NEW)) == frozen.texture_sha256)
	assert(FileAccess.get_sha256(MapSource.hydrology_network(NEW)) == frozen.network_sha256)
	for r in range(5):
		for i in frozen.samples[r]: eligible[int(i)] = 1
	var expanded_area := [0,0,0,0,0]
	var suitability_old := [0.0,0.0,0.0,0.0,0.0]
	var suitability_new := suitability_old.duplicate()
	for i in range(land.size()):
		if land[i] == 0: continue
		var ll := MapSource.map_to_lonlat((i%256+.5)/256.0,(i/256+.5)/256.0,NEW)
		for r in range(WINDOWS.size()):
			if WINDOWS[r].has_point(Vector2(ll[0],ll[1])):
				regions[i] = r
				break
		var r := regions[i]
		if r < 0: continue
		# Original 0.025-radius samples remain frozen when coverage expands.
		if eligible[i]:
			area[r] += 1
			suitability_old[r] += old.suitability[i]
			suitability_new[r] += current.suitability[i]
		if current.water[i] >= 0.5 and old.cold[i] >= 0.7 and old.flatness[i] >= 0.8 and old.farmland[i] >= 0.5: expanded_area[r] += 1
		var position := Vector2((i%256+.5)/256.0,(i/256+.5)/256.0)
		var bucket := Vector2i((position * Vector2(aspect,1.0) / Support.BUCKET).floor())
		if not current.river_support_index.buckets.has(bucket) and current.water[i] == 0.0 and old.water[i] == 0.0 and old.aridity[i] > 0.9:
			dry[i] = 1
			assert(absf(old.suitability[i]-current.suitability[i]) < 0.00001, "river-free dry cells must retain their score")
	var counts := [[0,0,0,0,0],[0,0,0,0,0]]
	var totals := [[0,0,0,0,0],[0,0,0,0,0]]
	var dry_counts := [[0,0,0,0,0],[0,0,0,0,0]]
	var output := {"samples": [], "eligible": Array(eligible), "regions": Array(regions), "area": area}
	for mode in range(2):
		var env: Dictionary = old if mode == 0 else current
		for seed_value in SEEDS:
			var sampled := Sampler.sample(source,land,env,500,aspect,seed_value,[] if mode == 0 else reserved,{} if mode == 0 else MapSource.settlement_density_bounds(NEW))
			assert(sampled.ok, str(sampled))
			for pixel in sampled.pixels:
				var i: int = pixel.y*256+pixel.x
				var r := regions[i]
				if r < 0: continue
				totals[mode][r] += 1
				if eligible[i]: counts[mode][r] += 1
				if dry[i]: dry_counts[mode][r] += 1
			if seed_value == 2342006650:
				var record := {"mode": mode, "positions": []}
				for p in sampled.positions: record.positions.append([p.x,p.y])
				output.samples.append(record)
		print("UNIFORM_REGIONS_PHASE mode=", mode, " counts=", counts[mode], " total=",totals[mode])
	output.merge({"counts":counts,"totals":totals,"dry_counts":dry_counts,"expanded_area":expanded_area})
	output["map_source"] = NEW
	output["density_bounds"] = MapSource.settlement_density_bounds(NEW)
	var output_path := OS.get_environment("REGIONS_OUTPUT")
	FileAccess.open("res://.dbg/uniform-regions.json" if output_path.is_empty() else output_path,FileAccess.WRITE).store_string(JSON.stringify(output))
	var failed := false
	print("UNIFORM_EXPANDED_ELIGIBLE_CELLS ", expanded_area)
	for r in range(5):
		print("UNIFORM_REGION name=%s eligible=%d old=%d new=%d all_old=%d all_new=%d dry_old=%d dry_new=%d suitability=%.5f->%.5f" % [NAMES[r],area[r],counts[0][r],counts[1][r],totals[0][r],totals[1][r],dry_counts[0][r],dry_counts[1][r],suitability_old[r]/maxi(area[r],1),suitability_new[r]/maxi(area[r],1)])
		if r < 2 and (area[r] == 0 or counts[1][r] < maxi(1,counts[0][r]*2) or suitability_new[r] <= suitability_old[r]): failed = true
	if failed:
		printerr("UNIFORM_REGIONS_FAIL: inland river-bank density must double")
		quit(1)
	else:
		print("UNIFORM_REGIONS_OK seeds=20")
		quit()
