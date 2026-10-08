extends SceneTree
## A temperate lowland can support inland settlements without an imported river map.
## Compare the same land with a clear coastward corridor, low hills, or a high ridge.
const EnvModel = preload("res://scripts/core/settlement_environment.gd")
# Keep the coast at x=152 and the physical pixel spacing unchanged, but include
# 48 water cells upwind: this fixture promises ocean supply, not a narrow lake.
const SIZE := Vector2i(200, 80)
const ASPECT := 2.5
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _fixture(barrier_height: float = 0.0, rolling_hills: bool = false) -> Dictionary:
	var heights := PackedFloat32Array()
	var land := PackedByteArray()
	var latitudes := PackedFloat32Array()
	heights.resize(SIZE.x * SIZE.y)
	land.resize(heights.size())
	latitudes.resize(SIZE.y)
	latitudes.fill(35.0)
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var i := y * SIZE.x + x
			land[i] = 1 if x < 152 else 0
			# A gentle continuous fall toward the ocean, well below mountain height.
			heights[i] = 0.02 + maxf(152 - x, 0) * 0.0001
			if x >= 118 and x <= 138:
				var wavelength := 4.0 if rolling_hills else 20.0
				heights[i] += barrier_height * pow(sin(float(x - 118) / wavelength * PI), 2.0)
	return EnvModel.evaluate(heights, land, SIZE, latitudes, ASPECT)

func _mean(field: PackedFloat32Array, first_x: int, last_x: int) -> float:
	var total := 0.0
	var count := 0
	# Keep diagnostics away from the cropped north/south boundaries.
	for y in range(24, 56):
		for x in range(first_x, last_x + 1):
			total += field[y * SIZE.x + x]
			count += 1
	return total / count

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("SETTLEMENT_INLAND_FAIL: ", message)

func _run() -> void:
	var plain := _fixture()
	var hills := _fixture(0.025, true) # Repeated 155 m low hills, not a major barrier.
	var mountain := _fixture(0.65) # Around 4 km, a genuinely high mountain barrier.
	for environment in [plain, hills, mountain]:
		for field in ["temperature", "rainfall", "water", "aridity", "suitability"]:
			for value in environment[field]:
				_check(is_finite(value), "environment fields must remain finite")
		for value in environment.suitability:
			_check(value >= 0.0 and value <= 1.0, "suitability remains within [0, 1]")
	var coastal_suitability := _mean(plain.suitability, 144, 148)
	var inland_suitability := _mean(plain.suitability, 104, 112)
	var hills_suitability := _mean(hills.suitability, 104, 112)
	var plain_rain := _mean(plain.rainfall, 104, 112)
	var hills_rain := _mean(hills.rainfall, 104, 112)
	var mountain_rain := _mean(mountain.rainfall, 104, 112)
	var inland_ratio := inland_suitability / maxf(coastal_suitability, 0.000001)
	var hills_ratio := hills_suitability / maxf(inland_suitability, 0.000001)
	var mountain_ratio := mountain_rain / maxf(plain_rain, 0.000001)
	print("INLAND_DIAGNOSTIC model=%s coast=%.6f inland=%.6f ratio=%.6f hills=%.6f hills_ratio=%.6f rain_plain=%.6f rain_hills=%.6f rain_mountain=%.6f mountain_ratio=%.6f" % [EnvModel.VERSION, coastal_suitability, inland_suitability, inland_ratio, hills_suitability, hills_ratio, plain_rain, hills_rain, mountain_rain, mountain_ratio])
	# Broad tolerance: some maritime advantage is expected, but an unobstructed
	# temperate plain should not lose most of its suitability at moderate distance.
	_check(inland_ratio >= 0.50, "moderately supplied inland plain retains at least half of coastal suitability; actual %.6f" % inland_ratio)
	_check(hills_ratio >= 0.60, "low hills do not create a major rain shadow; actual suitability ratio %.6f" % hills_ratio)
	# Increasing background humidity alone must not erase genuine mountain effects.
	_check(mountain_ratio <= 0.70, "a high ridge still materially reduces lee rainfall; actual ratio %.6f" % mountain_ratio)
	if not _failures.is_empty():
		quit(1)
		return
	print("SETTLEMENT_INLAND_OK")
	quit()
