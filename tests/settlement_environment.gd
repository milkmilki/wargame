extends SceneTree
## Causal fixtures for a procedural environment with no external climate data.
const EnvModel = preload("res://scripts/core/settlement_environment.gd")
func _init() -> void:
	call_deferred("_run")
func _fixture(size: Vector2i, latitude: float, ocean: bool = true) -> Dictionary:
	var heights := PackedFloat32Array()
	var land := PackedByteArray()
	heights.resize(size.x * size.y)
	heights.fill(0.03)
	land.resize(heights.size())
	land.fill(1)
	if ocean:
		for y in range(size.y):
			for x in range(6):
				land[y * size.x + x] = 0
	var latitudes := PackedFloat32Array()
	latitudes.resize(size.y)
	latitudes.fill(latitude)
	return {"heights": heights, "land": land, "latitudes": latitudes}
func _run() -> void:
	var size := Vector2i(96, 48)
	var plain := _fixture(size, 35)
	var warm := EnvModel.evaluate(plain.heights, plain.land, size, plain.latitudes, 2.0)
	var mountain: PackedFloat32Array = plain.heights.duplicate()
	for y in range(size.y):
		for x in range(28, 33):
			mountain[y * size.x + x] = 0.55
	var shadow := EnvModel.evaluate(mountain, plain.land, size, plain.latitudes, 2.0)
	var row := 24 * size.x
	assert(shadow.rainfall[row + 28] > shadow.rainfall[row + 38], "windward rain must exceed leeward rain")
	assert(shadow.rainfall[row + 38] < warm.rainfall[row + 38], "mountain must dry its lee")
	var below := plain.latitudes.duplicate() as PackedFloat32Array
	var above := plain.latitudes.duplicate() as PackedFloat32Array
	below.fill(29.9)
	above.fill(30.1)
	var below_rain := EnvModel._rainfall(mountain, plain.land, size, below, 2.0)
	var above_rain := EnvModel._rainfall(mountain, plain.land, size, above, 2.0)
	for i in range(below_rain.size()):
		assert(absf(below_rain[i] - above_rain[i]) < 0.03, "wind transition must not produce a latitude seam")
	var polar := _fixture(size, 75)
	var cold := EnvModel.evaluate(polar.heights, polar.land, size, polar.latitudes, 2.0)
	assert(cold.suitability[row + 20] < warm.suitability[row + 20] * 0.05)
	var inland := _fixture(size, 55, false)
	var maritime := _fixture(size, 55, true)
	var interior := EnvModel.evaluate(inland.heights, inland.land, size, inland.latitudes, 2.0)
	var coast := EnvModel.evaluate(maritime.heights, maritime.land, size, maritime.latitudes, 2.0)
	assert(coast.winter_temperature[row + 7] > interior.winter_temperature[row + 7])
	assert(interior.continentality[row] == interior.continentality[row + size.x - 1], "cropped borders are not oceans")
	# A descending valley must collect upstream rain; a closed pit stays a sink.
	var hills := PackedFloat32Array()
	hills.resize(15)
	for y in range(3):
		for x in range(5):
			hills[y * 5 + x] = 0.5 - x * 0.08 + abs(y - 1) * 0.02
	var rain := PackedFloat32Array()
	rain.resize(15)
	rain.fill(1.0)
	var all_land := PackedByteArray()
	all_land.resize(15)
	all_land.fill(1)
	var flow := EnvModel.accumulate_runoff(hills, all_land, Vector2i(5, 3), rain, 1.0)
	assert(flow[9] > rain[9] * 5.0, "downstream valley accumulates upstream supply")
	hills.fill(0.5)
	hills[7] = 0.1
	flow = EnvModel.accumulate_runoff(hills, all_land, Vector2i(5, 3), rain, 1.0)
	assert(flow[7] > rain[7], "closed basin retains inflow")
	assert(warm == EnvModel.evaluate(plain.heights, plain.land, size, plain.latitudes, 2.0))
	print("SETTLEMENT_ENVIRONMENT_OK")
	quit()
