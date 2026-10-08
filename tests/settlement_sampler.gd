extends SceneTree
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var size := Vector2i(128, 64)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.6))
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	mask.fill(1)
	var field := PackedFloat32Array()
	field.resize(mask.size())
	for i in range(field.size()):
		field[i] = 1.0 if i % size.x < 64 else 0.005
	var zeros := PackedFloat32Array()
	zeros.resize(mask.size())
	var environment := {"size": size, "suitability": field, "heights": zeros, "relief": zeros}
	var sparse := 0
	var fertile := 0
	for seed_value in range(20):
		var result := Sampler.sample(image, mask, environment, 120, 2.0, seed_value)
		assert(result.ok)
		assert(result.positions.size() == 120)
		assert(result.generation_metadata.spacing_scale >= 0.8)
		var occupied := {}
		for j in range(result.pixels.size()):
			var p: Vector2i = result.pixels[j]
			assert(not occupied.has(p))
			occupied[p] = true
			assert(Vector2i(result.positions[j] * Vector2(size)) == p)
			var spacing := 0.060 * sqrt(64.0 / 120.0) / sqrt(field[p.y * size.x + p.x])
			for k in range(j):
				var other: Vector2i = result.pixels[k]
				var other_spacing := 0.060 * sqrt(64.0 / 120.0) / sqrt(field[other.y * size.x + other.x])
				var required: float = (spacing + other_spacing) * 0.5 * result.generation_metadata.spacing_scale
				var delta: Vector2 = (result.positions[j] - result.positions[k]) * Vector2(2.0, 1.0)
				assert(delta.length() + 0.000001 >= required, "spatial hash must enforce every pair's projected spacing")
			if p.x < 64: fertile += 1
			else: sparse += 1
		if seed_value == 3:
			assert(result.positions == Sampler.sample(image, mask, environment, 120, 2.0, seed_value).positions)
	assert(float(sparse) / fertile <= 0.05)
	field.fill(0.0001)
	environment.suitability = field
	var failure := Sampler.sample(image, mask, environment, 500, 2.0, 1)
	assert(not failure.ok and str(failure.error).contains("减少城市数"))
	print("SETTLEMENT_SAMPLER_OK fertile=%d sparse=%d" % [fertile, sparse])
	quit()
