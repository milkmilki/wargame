extends SceneTree
const EnvModel = preload("res://scripts/core/settlement_environment.gd")
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
const Support = preload("res://scripts/core/river_settlement_support.gd")
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_SETTLEMENT_SAMPLING_FAIL: ", message)

func field(count: int, value: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(count)
	result.fill(value)
	return result

func source_image(height: float = 0.1) -> Image:
	var image := Image.create(1024, 1024, false, Image.FORMAT_RGBAF)
	image.fill(Color(1, 1, 1, (128.0 + 127.0 * height) / 255.0))
	return image

func feature(id: int, y: float, kind: String = "minor") -> Dictionary:
	return MapFeatureContract.make_river(id, PackedVector2Array([Vector2(0, y), Vector2(1, y)]), MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY, 0.3, 0.9, -1, PackedInt32Array(), kind, "sea")

func environment(size: Vector2i, aspect: float, features: Array, polar: bool = false) -> Dictionary:
	var count := size.x * size.y
	var land := PackedByteArray()
	land.resize(count)
	land.fill(1)
	var latitude := field(size.y, 35.0)
	if polar:
		for y in range(size.y * 2 / 3, size.y): latitude[y] = 75.0
	var env := EnvModel.evaluate(field(count, 0.1), land, size, latitude, aspect, PackedFloat32Array(), true)
	# Controlled moisture isolates river access from rainfall transport, while
	# temperature/terrain are evaluated by the real environment model.
	env.rainfed = field(count, 0.0)
	env.water = field(count, 1.0)
	env.suitability = field(count, 1.0)
	env.river_settlement_model = "uniform_v1"
	env.river_support_index = Support.build_index(features, aspect)
	env.hydrology = {"features": features}
	return env

func validate_result(result: Dictionary, size: Vector2i, label: String) -> void:
	check(bool(result.ok), label + ": " + str(result.get("error", "")))
	if not result.ok: return
	var cells := {}
	for i in range(result.positions.size()):
		var p: Vector2 = result.positions[i]
		var pixel: Vector2i = result.pixels[i]
		check(not cells.has(pixel), label + " unique province seed cell")
		cells[pixel] = true
		check(Vector2i(p * Vector2(size)) == pixel, label + " final point remains in its seed cell")

func jitter_test() -> void:
	var size := Vector2i(16, 16)
	var center := Vector2(8.5, 8.5) / 16.0
	var env := environment(size, 1.0, [feature(0, center.y)])
	var mask := PackedByteArray()
	mask.resize(256)
	mask[8 * 16 + 8] = 1
	var flat := source_image()
	var terrace := source_image(0.2)
	for y in range(542, 547):
		for x in range(1024): terrace.set_pixel(x, y, Color(1, 1, 1, (128.0 + 12.7) / 255.0))
	var accepted := 0
	var rejected := 0
	for seed_value in range(20):
		var low := Sampler.sample(flat, mask, env, 1, 1.0, seed_value)
		validate_result(low, size, "low bank seed=%d" % seed_value)
		var result := Sampler.sample(terrace, mask, env, 1, 1.0, seed_value)
		if not result.ok:
			rejected += 1
			continue
		accepted += 1
		var p: Vector2 = result.positions[0]
		check(Support.support_at(env.river_support_index, terrace, p) > 0.0, "jittered high terrace cannot borrow centre valley support")
		check(p.distance_to(center) > 0.000001, "accepted position is actually jittered")
	check(accepted > 0 and rejected > 0, "mixed fine valley fixture exercises both accepted low banks and rejected high banks")
	print("RIVER_JITTER_DIAGNOSTIC accepted=%d rejected=%d" % [accepted, rejected])

func distribution_test() -> void:
	var size := Vector2i(80, 40)
	var aspect := 4.0
	var features: Array = []
	for id in range(5): features.append(feature(id, 0.1 + 0.2 * id, "major"))
	var env := environment(size, aspect, features)
	var image := source_image()
	var upstream := 0
	var downstream := 0
	for seed_value in range(20):
		var result := Sampler.sample(image, env.land, env, 100, aspect, seed_value)
		validate_result(result, size, "uniform river seed=%d" % seed_value)
		if not result.ok: continue
		for p in result.positions:
			if p.x < 0.5: upstream += 1
			else: downstream += 1
	var imbalance := absf(float(upstream - downstream)) / maxf((upstream + downstream) * 0.5, 1.0)
	check(imbalance <= 0.10, "equal-area upstream/downstream density difference <=10%%, actual=%s" % imbalance)
	var first := Sampler.sample(image, env.land, env, 100, aspect, 137)
	var again := Sampler.sample(image, env.land, env, 100, aspect, 137)
	validate_result(first, size, "deterministic fixture")
	check(first.get("positions") == again.get("positions") and first.get("pixels") == again.get("pixels"), "same seed gives identical final points and cells")
	var corridor := PackedByteArray()
	corridor.resize(size.x * size.y)
	corridor.fill(1)
	env.hydrology.dock_corridor = corridor
	var components := PackedInt32Array()
	components.resize(corridor.size())
	env.components = components
	var with_corridor := Sampler.sample(image, env.land, env, 100, aspect, 137)
	validate_result(with_corridor, size, "major river corridor")
	check(first.get("positions") == with_corridor.get("positions"), "uniform mode does not inflate spacing inside major river corridor")
	var docks: Array = [{"position": Vector2(0.5, 0.5)}]
	var reserved := Sampler.sample(image, env.land, env, 100, aspect, 137, docks)
	validate_result(reserved, size, "reserved dock")
	if reserved.ok:
		var clearance := TerrainMapGenerator.minimum_dock_city_spacing_for_count(100)
		for p in reserved.positions:
			check(((p - docks[0].position) * Vector2(aspect, 1)).length() + 0.000001 >= clearance, "final jitter point clears reserved dock")
	print("RIVER_DENSITY_DIAGNOSTIC upstream=%d downstream=%d imbalance=%.5f" % [upstream, downstream, imbalance])

func dry_cold_test() -> void:
	var size := Vector2i(96, 60)
	var env := environment(size, 3.0, [], true)
	for y in range(size.y):
		for x in range(size.x):
			env.rainfed[y * size.x + x] = 0.0 if y >= 20 and y < 40 else 0.8
	var image := source_image()
	var counts := [0, 0, 0]
	for seed_value in range(20):
		var result := Sampler.sample(image, env.land, env, 100, 3.0, seed_value)
		validate_result(result, size, "dry/cold seed=%d" % seed_value)
		if not result.ok: continue
		for p in result.pixels: counts[mini(p.y / 20, 2)] += 1
	var dry_ratio := float(counts[1]) / maxi(counts[0], 1)
	var cold_ratio := float(counts[2]) / maxi(counts[0], 1)
	check(counts[0] > 0, "warm wet reference contains cities")
	check(dry_ratio <= 0.10, "dry without river density <=10% of wet plain")
	check(cold_ratio <= 0.05, "75-degree cold density <=5% of wet temperate plain")
	print("RIVER_DRY_COLD_DIAGNOSTIC counts=%s dry_ratio=%.5f cold_ratio=%.5f" % [counts, dry_ratio, cold_ratio])

func run() -> void:
	jitter_test()
	distribution_test()
	dry_cold_test()
	print("RIVER_SETTLEMENT_SAMPLING: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
