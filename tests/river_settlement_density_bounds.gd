extends SceneTree
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
const Support = preload("res://scripts/core/river_settlement_support.gd")
const Valley = preload("res://scripts/core/valley_water_support.gd")
const SIZE := Vector2i(64, 32)
const ASPECT := 2.0
var failures: Array[String] = []
var sampler: RefCounted

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_DENSITY_BOUNDS_FAIL: ", message)

func floats(value: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(SIZE.x * SIZE.y)
	result.fill(value)
	return result

func fixture(mode: String, all_good: bool = false) -> Dictionary:
	var source := Image.create(512, 256, false, Image.FORMAT_RGBAF)
	source.fill(Color(1,1,1,0.6))
	var mask := PackedByteArray()
	mask.resize(SIZE.x * SIZE.y)
	mask.fill(1)
	var rain := floats(0.0)
	var raw := floats(0.0)
	for i in range(mask.size()):
		if all_good or i % SIZE.x >= SIZE.x / 2:
			rain[i] = 1.0
			raw[i] = 1.0
		# Excluded mask cells remain deliberately dry land in the texture. The
		# explicit legal-land mask must still win after a density floor is applied.
		if i / SIZE.x < 2: mask[i] = 0
	var river := MapFeatureContract.make_river(0, PackedVector2Array([Vector2(0,0.518),Vector2(1,0.518)]), MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)
	# A transport barrier is supplied independently of water scoring. This keeps
	# the low half raw=0 while exercising the real jitter bank-side restriction.
	var water_index := Support.build_index([], ASPECT)
	var latitudes := PackedFloat32Array()
	latitudes.resize(SIZE.y)
	latitudes.fill(35.0)
	var env := {"size":SIZE,"land":mask,"latitudes":latitudes,"relief":floats(0.0),"rainfed":rain,"cold":floats(1.0),"flatness":floats(1.0),"farmland":floats(1.0),"suitability":raw,"water":floats(0.0),"river_settlement_model":mode,"river_support_index":water_index,"hydrology":{"features":[river]}}
	# Exercise the no-water fast path as well as the final jitter-time check.
	env.river_support_possible = PackedByteArray()
	env.river_support_possible.resize(mask.size())
	env.rainfed_suitability = PackedFloat64Array(Array(raw))
	env.maximum_suitability = PackedFloat64Array(Array(floats(1.0)))
	if mode == "valley_v1": env.valley_support = Valley.build(source,env,water_index,ASPECT)
	return {"source":source,"mask":mask,"env":env,"river":river}

func sample(f: Dictionary, seed_value: int, count: int, bounds: Dictionary, docks: Array = []) -> Dictionary:
	return sampler.call("sample",f.source,f.mask,f.env,count,ASPECT,seed_value,docks,bounds)

func validate(result: Dictionary, f: Dictionary, count: int, docks: Array = []) -> void:
	check(bool(result.get("ok",false)), "sampling succeeds: " + str(result.get("error","")))
	if not result.get("ok",false): return
	check(result.positions.size() == count, "requested city count")
	var seen := {}
	for k in range(result.positions.size()):
		var p: Vector2 = result.positions[k]
		var cell: Vector2i = result.pixels[k]
		var i := cell.y * SIZE.x + cell.x
		check(f.mask[i] != 0, "density floor never legalizes excluded land/sea mask")
		check(not seen.has(cell), "province seed cells remain unique")
		seen[cell] = true
		check(Vector2i(p * Vector2(SIZE)) == cell, "jitter stays in its own seed cell")
		var center := (Vector2(cell) + Vector2.ONE * 0.5) / Vector2(SIZE)
		check(Geometry2D.segment_intersects_segment(center,p,f.river.points[0],f.river.points[1]) == null, "jitter cannot cross main river")
		for dock in docks:
			check(((p-dock.position)*Vector2(ASPECT,1)).length()+0.000001 >= TerrainMapGenerator.minimum_dock_city_spacing_for_count(count), "reserved dock clearance survives density floor")

func mode_test(mode: String, minimum: float = 0.05) -> void:
	var f := fixture(mode)
	var original: PackedFloat32Array = f.env.suitability.duplicate()
	var counts := [0,0]
	var docks: Array = [{"position":Vector2(0.75,0.65)}]
	f.env["local_crossings"] = mode == "flow_weighted"
	for seed_value in range(20):
		var result := sample(f,seed_value,64,{"minimum":minimum,"maximum":1.0},docks)
		validate(result,f,64,docks)
		if seed_value == 0:
			var repeated := sample(f,seed_value,64,{"minimum":minimum,"maximum":1.0},docks)
			check(result.get("positions",[])==repeated.get("positions",[]),"same seed and bounds reproduce positions")
		if result.get("ok",false):
			for cell in result.pixels: counts[0 if cell.x < SIZE.x/2 else 1] += 1
	check(counts[0] > 0 and counts[0] < counts[1], "zero-raw legal land participates but remains sparser than equal-area good land")
	check(f.env.suitability == original, "sampling bounds do not overwrite original environment scores")
	var legacy := sample(f,137,64,{})
	validate(legacy,f,64)
	if legacy.get("ok",false):
		for cell in legacy.pixels: check(cell.x >= SIZE.x/2, "default empty bounds preserve zero-score exclusion")
	var good := fixture(mode,true)
	var capped := sample(good,137,64,{"minimum":0.05,"maximum":0.5})
	validate(capped,good,64)
	if capped.get("ok",false):
		var minimum_spacing := 0.060 / sqrt(0.5) * float(capped.generation_metadata.spacing_scale)
		for a in range(capped.positions.size()):
			for b in range(a):
				check(((capped.positions[a]-capped.positions[b])*Vector2(ASPECT,1)).length()+0.000001 >= minimum_spacing, "maximum .5 controls actual spatial spacing")
	for bounds in [{"minimum":-0.01,"maximum":1.0},{"minimum":0.05,"maximum":1.01},{"minimum":0.8,"maximum":0.5},{"minimum":0.0,"maximum":0.0}]:
		var invalid := sample(f,137,64,bounds)
		check(not bool(invalid.get("ok",true)), "invalid or zero-capacity bounds fail cleanly: %s" % bounds)
	print("DENSITY_BOUNDS_DIAGNOSTIC model=%s low=%d high=%d" % [mode,counts[0],counts[1]])

func run() -> void:
	var manifest := "res://assets/terrain/eurasia_valley_river_map_source.json"
	check(MapSource.validate_manifest(manifest).is_empty(),"candidate manifest validates")
	check(MapSource.settlement_density_bounds(manifest)=={"minimum":0.05,"maximum":1.0},"candidate enables chosen 5% floor and 100% ceiling")
	check(MapSource.settlement_density_bounds()=={"minimum":0.0,"maximum":1.0},"legacy manifest preserves defaults")
	for invalid in [null, [], {"minimum":"0.05"}, {"minimum":NAN}, {"maximum":INF}]:
		check(not MapSource.validate_density_bounds(invalid).is_empty(),"malformed/non-finite density rejected")
	sampler = Sampler.new()
	var argument_count := 0
	for method in sampler.get_method_list():
		if method.name == "sample": argument_count = method.args.size()
	if argument_count < 8:
		check(false,"Sampler.sample has no optional density_bounds argument")
		finish()
		return
	mode_test("uniform_v1")
	mode_test("valley_v1")
	mode_test("flow_weighted", 0.02)
	check(MapSource.settlement_density_bounds("res://assets/terrain/eurasia_transport_map_source.json") == {"minimum":0.02,"maximum":1.0}, "new transport scene uses 2% floor")
	finish()

func finish() -> void:
	print("RIVER_SETTLEMENT_DENSITY_BOUNDS: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
