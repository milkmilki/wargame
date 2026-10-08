extends SceneTree
const MODULE_PATH := "res://scripts/core/river_navigation.gd"
var failures: Array[String] = []
var model: RefCounted

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_NAVIGATION_LOCAL_FAIL: ",message)

func packed(height: float) -> Color:
	return Color(1,1,1,(128.0+127.0*height)/255.0)

func image_with_height(width: int,height: float) -> Image:
	var result := Image.create(width,8,false,Image.FORMAT_RGBA8)
	result.fill(packed(height))
	return result

func assess(points: PackedVector2Array,image: Image,aspect: float = 1.0) -> Dictionary:
	return model.call("assess",points,image,aspect)

func valid_record(result: Dictionary,label: String) -> void:
	check(result.get("model","") == "local_height_v1",label+" records navigation model")
	check(absf(float(result.get("sample_step",-1))-0.002) < 0.000001,label+" records sampling step")
	check(absf(float(result.get("window_length",-1))-0.012) < 0.000001,label+" records local window length")
	var maximum := float(result.get("max_local_height_difference",NAN))
	check(is_finite(maximum) and maximum >= 0.0,label+" exposes finite maximum local difference")

func run() -> void:
	if not ResourceLoader.exists(MODULE_PATH):
		check(false,"RiverNavigation module missing")
		finish()
		return
	var script := load(MODULE_PATH) as Script
	if script == null or not script.can_instantiate():
		check(false,"RiverNavigation module cannot instantiate")
		finish()
		return
	model = script.new()
	if not model.has_method("assess"):
		check(false,"assess API missing")
		finish()
		return
	var path := PackedVector2Array([Vector2(0.05,0.5),Vector2(0.95,0.5)])
	var ramp := image_with_height(1024,0.1)
	for x in range(ramp.get_width()):
		for y in range(ramp.get_height()):
			ramp.set_pixel(x,y,packed(0.1+0.7*float(x)/1023.0))
	var gentle := assess(path,ramp)
	valid_record(gentle,"long gentle slope")
	check(bool(gentle.get("navigable",false)),"long gentle slope remains navigable despite total fall >0.2")
	check(float(gentle.get("max_local_height_difference",1)) < 0.03,"local window measures gentle slope rather than whole-reach fall")
	var cliff := image_with_height(4096,0.1)
	# This one-pixel obstacle is narrower than the nominal 0.002 sampling step
	# and absent from the polyline vertices. Both reach endpoints remain low.
	for y in range(cliff.get_height()): cliff.set_pixel(2031,y,packed(0.8))
	var blocked := assess(path,cliff)
	valid_record(blocked,"one-pixel interior cliff")
	check(not bool(blocked.get("navigable",true)),"equal endpoints do not hide a one-pixel interior cliff")
	check(float(blocked.get("max_local_height_difference",0)) > 0.6,"original DEM pixel sampling captures the interior cliff")
	var subdivided := PackedVector2Array([path[0],Vector2(0.21,0.5),Vector2(0.403,0.5),Vector2(0.501,0.5),Vector2(0.7,0.5),path[1]])
	var reversed := path.duplicate()
	reversed.reverse()
	for source in [ramp,cliff]:
		var base := assess(path,source)
		for variant in [subdivided,reversed]:
			var result := assess(variant,source)
			check(result.get("navigable") == base.get("navigable"),"collinear subdivision/direction preserves navigation decision")
			check(absf(float(result.get("max_local_height_difference",INF))-float(base.get("max_local_height_difference",0))) <= 1.0/127.0+0.00001,"collinear subdivision/direction preserves local difference within one DEM quantization level")
	var flat := image_with_height(64,0.1)
	for invalid_path in [PackedVector2Array(),PackedVector2Array([Vector2(0.5,0.5)]),PackedVector2Array([Vector2(0.5,0.5),Vector2(0.5,0.5)]),PackedVector2Array([Vector2(-0.1,0.5),Vector2(0.5,0.5)]),PackedVector2Array([Vector2(NAN,0.5),Vector2(0.5,0.5)])]:
		check(not bool(assess(invalid_path,flat).get("navigable",true)),"empty, degenerate or invalid river geometry is not navigable")
	for aspect in [0.0,-1.0,NAN,INF]:
		check(not bool(assess(path,flat,aspect).get("navigable",true)),"invalid aspect is not navigable")
	check(not bool(assess(path,Image.new()).get("navigable",true)),"empty DEM is not navigable")
	check(not bool(assess(path,null).get("navigable",true)),"missing DEM is not navigable")
	print("RIVER_NAVIGATION_DIAGNOSTIC gentle=",gentle," cliff=",blocked)
	finish()

func finish() -> void:
	print("RIVER_NAVIGATION_LOCAL: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
