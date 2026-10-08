extends SceneTree
## Ocean fetch and latitude must distinguish dry interiors from moist coastal plains.
## No location names, regional masks, or observed climate data enter these fixtures.
const EnvModel = preload("res://scripts/core/settlement_environment.gd")
const SIZE := Vector2i(160, 80)
const ASPECT := 2.0
const COAST_X := 112
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _fixture(latitude: float, sea_width: int) -> Dictionary:
	var heights := PackedFloat32Array()
	var land := PackedByteArray()
	var latitudes := PackedFloat32Array()
	heights.resize(SIZE.x * SIZE.y)
	land.resize(heights.size())
	latitudes.resize(SIZE.y)
	latitudes.fill(latitude)
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var i := y * SIZE.x + x
			# All alternatives have exactly the same target lowland and coast position.
			# Only the upwind water width changes: none, one narrow cell, or open sea.
			land[i] = 0 if x >= COAST_X and x < COAST_X + sea_width else 1
			heights[i] = 0.02 + maxf(COAST_X - x, 0) * 0.0001
	return EnvModel.evaluate(heights, land, SIZE, latitudes, ASPECT)

func _mean(field: PackedFloat32Array) -> float:
	var total := 0.0
	var count := 0
	# Observe inland from the shared shore, away from every clipped map boundary.
	for y in range(24, 56):
		for x in range(88, 97):
			total += field[y * SIZE.x + x]
			count += 1
	return total / count

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("SETTLEMENT_DRY_BELT_FAIL: ", message)

func _run() -> void:
	var subtropical_ocean := _fixture(28.0, SIZE.x - COAST_X)
	var subtropical_channel := _fixture(28.0, 1)
	var subtropical_interior := _fixture(28.0, 0)
	var temperate_interior := _fixture(40.0, 0)
	var temperate_ocean := _fixture(40.0, SIZE.x - COAST_X)
	var ocean_rain := _mean(subtropical_ocean.rainfall)
	var channel_rain := _mean(subtropical_channel.rainfall)
	var narrow_ratio := channel_rain / maxf(ocean_rain, 0.000001)
	var dry_subtropical := _mean(subtropical_interior.suitability)
	var dry_temperate := _mean(temperate_interior.suitability)
	var dry_ratio := dry_subtropical / maxf(dry_temperate, 0.000001)
	var wet_subtropical := _mean(subtropical_ocean.suitability)
	var wet_temperate := _mean(temperate_ocean.suitability)
	var wet_ratio := wet_subtropical / maxf(wet_temperate, 0.000001)
	print("DRY_BELT_DIAGNOSTIC model=%s ocean_rain=%.6f channel_rain=%.6f narrow_ratio=%.6f dry_subtropical=%.6f dry_temperate=%.6f dry_ratio=%.6f wet_subtropical=%.6f wet_temperate=%.6f wet_ratio=%.6f" % [EnvModel.VERSION, ocean_rain, channel_rain, narrow_ratio, dry_subtropical, dry_temperate, dry_ratio, wet_subtropical, wet_temperate, wet_ratio])
	_check(narrow_ratio <= 0.75, "one-cell water body supplies materially less downwind rain than open sea; actual ratio %.6f" % narrow_ratio)
	_check(dry_ratio <= 0.50, "subtropical interior without strong ocean supply is substantially less suitable than temperate interior; actual ratio %.6f" % dry_ratio)
	# A latitude-only exclusion would pass the dry check but destroy these wet plains.
	_check(wet_subtropical >= 0.20, "subtropical inland plain with substantial ocean supply remains habitable; actual %.6f" % wet_subtropical)
	_check(wet_ratio >= 0.50, "humid subtropical plain is not categorically excluded relative to a temperate counterpart; actual ratio %.6f" % wet_ratio)
	if not _failures.is_empty():
		quit(1)
		return
	print("SETTLEMENT_DRY_BELT_OK")
	quit()
