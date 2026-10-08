extends SceneTree
const EnvModel = preload("res://scripts/core/settlement_environment.gd")
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var size := Vector2i(160, 80)
	var heights := PackedFloat32Array()
	var land := PackedByteArray()
	var latitudes := PackedFloat32Array()
	heights.resize(size.x * size.y)
	heights.fill(0.03)
	land.resize(heights.size())
	land.fill(1)
	latitudes.resize(size.y)
	latitudes.fill(35)
	for y in range(size.y):
		for x in range(60):
			if x < 10 or x % 16 < 3: land[y * size.x + x] = 0
		for x in range(65, 70): heights[y * size.x + x] = 0.6
	var warm := EnvModel.evaluate(heights, land, size, latitudes, 4.0)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.6))
	var wet_cells := 0
	var dry_cells := 0
	for i in range(land.size()):
		if land[i] == 0: continue
		if warm.aridity[i] < 0.4 and warm.farmland[i] > 0.9: wet_cells += 1
		if warm.aridity[i] > 0.9 and warm.water[i] < 0.2 and warm.farmland[i] > 0.9: dry_cells += 1
	assert(wet_cells > 100 and dry_cells > 100)
	var wet_cities := 0
	var dry_cities := 0
	for seed_value in range(20):
		var sampled := Sampler.sample(image, land, warm, 100, 4.0, seed_value)
		assert(sampled.ok)
		for pixel in sampled.pixels:
			var i: int = pixel.y * size.x + pixel.x
			if warm.aridity[i] < 0.4 and warm.farmland[i] > 0.9: wet_cities += 1
			if warm.aridity[i] > 0.9 and warm.water[i] < 0.2 and warm.farmland[i] > 0.9: dry_cities += 1
	var dry_ratio := (float(dry_cities) / dry_cells) / (float(wet_cities) / wet_cells)
	print("DRY_DISTRIBUTION ratio=", dry_ratio, " wet=", wet_cities, "/", wet_cells, " dry=", dry_cities, "/", dry_cells)
	assert(dry_ratio <= 0.10)
	# Equal-area coastal flat bands, one temperate and one polar.
	heights.fill(0.03)
	# Both bands border the same broad eastern ocean. Narrow three-cell inlets
	# are no longer an unlimited water source and cannot stand in for an ocean.
	for i in range(land.size()): land[i] = 0 if i % size.x >= 96 else 1
	for y in range(size.y): latitudes[y] = 35.0 if y < 40 else 75.0
	var cold := EnvModel.evaluate(heights, land, size, latitudes, 2.0)
	var temperate_count := 0
	var polar_count := 0
	for seed_value in range(20):
		var sampled := Sampler.sample(image, land, cold, 100, 2.0, seed_value)
		assert(sampled.ok)
		for p in sampled.pixels:
			if p.y < 40: temperate_count += 1
			else: polar_count += 1
	var cold_ratio := float(polar_count) / temperate_count
	assert(cold_ratio <= 0.05)
	print("ENVIRONMENT_DISTRIBUTION_OK seeds=20 dry_density_ratio=%.5f cold_density_ratio=%.5f wet_cities=%d dry_cities=%d" % [dry_ratio, cold_ratio, wet_cities, dry_cities])
	quit()
