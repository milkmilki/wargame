extends SceneTree
const Env = preload("res://scripts/core/settlement_environment.gd")
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
const SOURCE := "res://assets/terrain/eurasia_uniform_river_map_source.json"
const RADII := [0.025,0.04,0.06,0.08,0.12]
const SEEDS := [2342006650,12345,23456,34567,45678]
const WINDOWS := [Rect2(103,28,5,5),Rect2(106,33,6,3),Rect2(108,29,10,8),Rect2(0,20,30,9),Rect2(40,20,10,9)]
const NAMES := ["sichuan","guanzhong","central_china","sahara","arabia"]
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var source := (load(MapSource.texture_path(SOURCE)) as Texture2D).get_image()
	var analysis := source.duplicate()
	analysis.resize(256,256,Image.INTERPOLATE_NEAREST)
	var land: PackedByteArray = TerrainMapGenerator._all_land_geometry(analysis).mask
	var latitudes := PackedFloat32Array()
	for y in range(256): latitudes.append(MapSource.latitude_at_y((y+.5)/256.0,18,57,SOURCE))
	var aspect := MapSource.aspect_ratio(SOURCE)
	var regions := PackedInt32Array()
	regions.resize(land.size())
	regions.fill(-1)
	for i in range(land.size()):
		var ll := MapSource.map_to_lonlat((i%256+.5)/256.0,(i/256+.5)/256.0,SOURCE)
		for r in range(WINDOWS.size()):
			if WINDOWS[r].has_point(Vector2(ll[0],ll[1])):
				regions[i] = r
				break
	var frozen: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/river_settlement_fixed_samples.json"))
	var fixed := {}
	for r in range(5):
		for i in frozen.samples[r]: fixed[int(i)] = r
	var results := []
	var original_features: Array = []
	DirAccess.make_dir_recursive_absolute("res://.dbg/radius-sweep")
	for radius in RADII:
		var started := Time.get_ticks_usec()
		var environment := Env.build(source,analysis,land,latitudes,aspect,"web_mercator",true,MapSource.hydrology_network(SOURCE),true,"uniform_v1",radius)
		var reserved := TerrainMapGenerator._reserve_hydrology_docks(environment,analysis,aspect,500)
		var environment_ms := (Time.get_ticks_usec()-started)/1000.0
		if original_features.is_empty(): original_features=environment.hydrology.features.duplicate(true)
		else: assert(environment.hydrology.features==original_features,"radius must not alter river geometry/classes")
		var counts := [0,0,0,0,0]
		var fixed_counts := [0,0,0,0,0]
		var coverage := [0,0,0,0,0]
		var habitable := [0,0,0,0,0]
		var area := [0,0,0,0,0]
		var samples := []
		var sampling_ms := []
		for i in range(land.size()):
			var r := regions[i]
			if r < 0 or land[i] == 0: continue
			area[r] += 1
			if environment.water[i] >= .5: coverage[r] += 1
			if environment.suitability[i] >= .3: habitable[r] += 1
		for seed_value in SEEDS:
			var sampled := Sampler.sample(source,land,environment,500,aspect,seed_value,reserved)
			assert(sampled.ok,str(sampled))
			sampling_ms.append(sampled.generation_metadata.sampling_usec/1000.0)
			var points := []
			for i in range(sampled.pixels.size()):
				var pixel: Vector2i=sampled.pixels[i]
				var cell := pixel.y*256+pixel.x
				var r := regions[cell]
				if r >= 0: counts[r] += 1
				if fixed.has(cell): fixed_counts[fixed[cell]] += 1
				points.append([sampled.positions[i].x,sampled.positions[i].y])
			samples.append(points)
			print("RADIUS_SAMPLE radius=",radius," seed=",seed_value," counts=",counts)
		var output := {"radius":radius,"size":[256,256],"aspect":aspect,"seed":SEEDS[0],"positions":samples[0],"samples":samples,"rivers":[]}
		for key in ["land","heights","water","suitability","rainfed","cold","flatness","farmland"]: output[key]=Array(environment[key])
		for river in environment.hydrology.features:
			var points := []
			for p in river.points: points.append([p.x,p.y])
			output.rivers.append({"points":points,"class":river.river_class})
		FileAccess.open("res://.dbg/radius-sweep/fields-%03d.json"%roundi(radius*1000),FileAccess.WRITE).store_string(JSON.stringify(output))
		var result := {"radius":radius,"cities":counts,"fixed_cities":fixed_counts,"water_cells":coverage,"habitable_cells":habitable,"land_cells":area,"environment_ms":environment_ms,"sampling_ms":sampling_ms}
		results.append(result)
		print("RADIUS_RESULT ",JSON.stringify(result))
	FileAccess.open("res://.dbg/radius-sweep/summary.json",FileAccess.WRITE).store_string(JSON.stringify({"names":NAMES,"seeds":SEEDS,"results":results},"  "))
	print("RADIUS_SWEEP_OK")
	quit()
