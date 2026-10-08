extends SceneTree
const MODULE_PATH := "res://scripts/core/valley_water_support.gd"
const RiverSupport = preload("res://scripts/core/river_settlement_support.gd")
const SIZE := Vector2i(96, 48)
const ASPECT := 2.0
var failures: Array[String] = []
var model: RefCounted

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_SETTLEMENT_VALLEY_FAIL: ", message)

func position(x: float, y: float = 24.0) -> Vector2:
	return (Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(SIZE)

func fixture(kind: String = "plain", latitude: float = 35.0, offset: int = 0, river_class: String = "minor") -> Dictionary:
	var source := Image.create(SIZE.x * 4, SIZE.y * 4, false, Image.FORMAT_RGBAF)
	source.fill(Color(1, 1, 1, (128.0 + 12.7) / 255.0))
	var land := PackedByteArray()
	land.resize(SIZE.x * SIZE.y)
	land.fill(1)
	var relief := PackedFloat32Array()
	relief.resize(land.size())
	var latitudes := PackedFloat32Array()
	latitudes.resize(SIZE.y)
	latitudes.fill(latitude)
	if kind in ["ridge", "sea"]:
		# A complete north-south barrier prevents an end-run within the budget.
		for y in range(SIZE.y):
			if kind == "sea": land[y * SIZE.x + 26 + offset] = 0
		for y in range(source.get_height()):
			for x in range((26 + offset) * 4, (27 + offset) * 4):
				source.set_pixel(x, y, Color(1, 1, 1, (128.0 + 127.0 * 0.2) / 255.0 if kind == "ridge" else 0.4))
	if kind == "thin_ridge":
		# This ridge lies BETWEEN the river and a nearby analysis-cell centre.
		# Both endpoints are low; direct seeding must still inspect connectivity.
		for y in range(source.get_height()):
			source.set_pixel((25 + offset) * 4, y, Color(1, 1, 1, (128.0 + 127.0 * 0.2) / 255.0))
	var river_x := position(24 + offset).x
	var feature := MapFeatureContract.make_river(0, PackedVector2Array([Vector2(river_x, 0), Vector2(river_x, 1)]), MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY, 0.3, 0.9, -1, PackedInt32Array(), river_class, "sea")
	feature.flow = 0.5 if river_class == "minor" else 10000.0
	var river_index := RiverSupport.build_index([feature], ASPECT)
	var environment := {"size": SIZE, "land": land, "latitudes": latitudes, "relief": relief}
	var result: Dictionary = model.call("build", source, environment, river_index, ASPECT)
	check(result.has("support") and result.has("heights") and result.has("size") and result.has("aspect"), "field exposes support, heights, size and aspect")
	if result.has("support"):
		check(result.support.size() == land.size(), "one support value per analysis cell")
		for value in result.support:
			if not is_finite(value) or value < 0.0 or value > 1.00001:
				check(false, "support must remain finite in [0,1]")
				break
	return {"field": result, "source": source, "river_index": river_index}

func sample(f: Dictionary, p: Vector2) -> float:
	return float(model.call("support_at", f.field, f.source, p))

func run() -> void:
	if not ResourceLoader.exists(MODULE_PATH):
		check(false, "valley support module missing")
		finish()
		return
	var script := load(MODULE_PATH) as Script
	if script == null or not script.can_instantiate():
		check(false, "valley support module cannot instantiate")
		finish()
		return
	model = script.new()
	if not model.has_method("build") or not model.has_method("support_at"):
		check(false, "build/support_at API missing")
		finish()
		return
	var plain := fixture()
	var query := position(28)
	var value := sample(plain, query)
	check(RiverSupport.support_at(plain.river_index, plain.source, query) == 0.0, "plain query is outside original near-bank radius")
	check(value > 0.05, "connected low plain receives useful extra water beyond near-bank radius")
	check(sample(plain, position(40)) == 0.0, "finite propagation budget does not irrigate distant plain")
	var ridge := fixture("ridge")
	var sea := fixture("sea")
	check(sample(ridge, query) < value * 0.1, "same-distance far bank across high ridge remains dry")
	check(sample(sea, query) == 0.0, "sea barrier cannot transport valley water onto separate land")
	var thin := fixture("thin_ridge")
	check(sample(thin, position(25)) == 0.0, "low point behind intervening ridge cannot be directly seeded from nearby river")
	var translated := fixture("plain", 35.0, 28)
	check(absf(sample(translated, position(56)) - value) < 0.0001, "translating longitude preserves same connected valley supply")
	var major := fixture("plain", 35.0, 0, "major")
	check(absf(sample(major, query) - value) < 0.0001, "main versus tributary class and discharge do not change extra supply")
	check(absf(sample(plain, position(28, 16)) - sample(plain, position(28, 32))) < 0.0001, "equivalent upstream and downstream banks receive equal support")
	var subtropical := fixture("plain", 27.0)
	var subtropical_value := sample(subtropical, query)
	check(subtropical_value >= value * 0.80 and subtropical_value <= value * 1.01, "27-degree belt only weakly reduces identical valley water relative to 35 degrees")
	print("VALLEY_SUPPORT_DIAGNOSTIC plain=%.6f ridge=%.6f sea=%.6f subtropical=%.6f" % [value, sample(ridge,query), sample(sea,query), subtropical_value])
	finish()

func finish() -> void:
	print("RIVER_SETTLEMENT_VALLEY: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
