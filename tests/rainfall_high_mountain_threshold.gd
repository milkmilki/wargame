extends SceneTree
const EnvModel := preload("res://scripts/core/settlement_environment.gd")

func _init() -> void:
	var size := Vector2i(96, 32)
	var land := PackedByteArray()
	var heights := PackedFloat32Array()
	var latitudes := PackedFloat32Array()
	land.resize(size.x * size.y)
	land.fill(1)
	heights.resize(land.size())
	heights.fill(50.0 / 6200.0)
	latitudes.resize(size.y)
	latitudes.fill(35.0)
	for y in range(size.y):
		for x in range(24): land[y * size.x + x] = 0
	var reference := EnvModel._rainfall(heights, land, size, latitudes, 2.0)
	var failures := 0
	for altitude in [500.0, 1500.0, 2400.0]:
		var ridge := heights.duplicate()
		for y in range(size.y):
			for x in range(28, 33): ridge[y * size.x + x] = altitude / 6200.0
		var result := EnvModel._rainfall(ridge, land, size, latitudes, 2.0)
		var error := 0.0
		for i in range(result.size()): error = maxf(error, absf(result[i] - reference[i]))
		if error > 0.000001:
			printerr("LOW_MOUNTAIN_RAIN_FAIL altitude=", altitude, " maximum_difference=", error)
			failures += 1
	var high := heights.duplicate()
	for y in range(size.y):
		for x in range(28, 33): high[y * size.x + x] = 3000.0 / 6200.0
	var high_rain := EnvModel._rainfall(high, land, size, latitudes, 2.0)
	var windward := size.x * 16 + 28
	var leeward := size.x * 16 + 38
	if high_rain[windward] <= reference[windward] or high_rain[leeward] >= reference[leeward]:
		printerr("HIGH_MOUNTAIN_RAIN_FAIL: 3000m ridge must retain windward rain and lee drying")
		failures += 1
	if high_rain != EnvModel._rainfall(high, land, size, latitudes, 2.0):
		printerr("HIGH_MOUNTAIN_RAIN_FAIL: deterministic rainfall")
		failures += 1
	print("RAINFALL_HIGH_MOUNTAIN_THRESHOLD: %d failures" % failures)
	quit(1 if failures else 0)
