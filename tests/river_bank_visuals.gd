extends SceneTree
const MODULE_PATH := "res://scripts/view/river_province_geometry.gd"
const MANIFEST := "res://assets/terrain/eurasia_strict_river_map_source.json"
const COARSE := Vector2i(32,32)
var failures: Array[String] = []
var model: RefCounted

func _init() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_BANK_VISUALS_FAIL: ",message)

func fixture() -> GameState:
	var state := GameState.new()
	state.map_source_manifest = MANIFEST
	state.map_aspect_ratio = 1.0
	state.province_map_size = COARSE
	state.province_ids.resize(COARSE.x*COARSE.y)
	for y in range(COARSE.y):
		for x in range(COARSE.x):
			state.province_ids[y*COARSE.x+x] = 0 if x < 16 else 1
			if x < 8 and y >= 16: state.province_ids[y*COARSE.x+x] = 2
	var positions := [Vector2(0.35,0.45),Vector2(0.8,0.5),Vector2(0.1,0.9)]
	for i in range(positions.size()):
		var city := City.new()
		city.id = i
		city.owner_nation = i
		city.map_position = positions[i]
		state.cities.append(city)
		var nation := Nation.new()
		nation.id = i
		state.nations.append(nation)
	# The river stays between coarse cell centres while visibly deviating from
	# their shared x=.5 grid edge. Visual banks must follow this exact polyline.
	var points := PackedVector2Array([Vector2(0.489,0),Vector2(0.511,0.2),Vector2(0.489,0.4),Vector2(0.511,0.6),Vector2(0.489,0.8),Vector2(0.511,1)])
	state._set_river_features([MapFeatureContract.make_river(0,points,MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)])
	return state

func height_image(size: int) -> Image:
	var result := Image.create(size,size,false,Image.FORMAT_RGBA8)
	result.fill(Color(1,1,1,0.6))
	for y in range(size/8):
		for x in range(size/8): result.set_pixel(x,y,Color(1,1,1,0.4))
	return result

func build(state: GameState,source: Image,size: int) -> Dictionary:
	var result: Dictionary = model.call("build",state,source,Vector2i(size,size))
	for key in ["city_id","land_mask","region_edge","region_coverage","region_distance","regions","topology"]:
		check(result.has(key),"visual geometry exposes "+key)
	return result

func pixel(position: Vector2,image: Image) -> Vector2i:
	return Vector2i(position*Vector2(image.get_size())).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE)

func pick(result: Dictionary,position: Vector2) -> int:
	var ids: Image = result.city_id
	return roundi(ids.get_pixelv(pixel(position,ids)).r)

func filled(result: Dictionary,position: Vector2) -> bool:
	var coverage: Image = result.region_coverage
	return coverage.get_pixelv(pixel(position,coverage)).r > 0.5

func assert_banks(result: Dictionary,points: PackedVector2Array,size: int) -> void:
	for segment in range(points.size()-1):
		var direction := (points[segment+1]-points[segment]).normalized()
		var left := Vector2(-direction.y,direction.x)
		for t in [0.25,0.5,0.75]:
			var center := points[segment].lerp(points[segment+1],t)
			# 1.25 pixels before rounding leaves >=.75 pixels of bank clearance.
			var a := center+left*(1.25/size)
			var b := center-left*(1.25/size)
			check(pick(result,a) == 0 and pick(result,b) == 1,"actual curved river separates fill/pick sides size=%d segment=%d t=%s" % [size,segment,t])
			check(filled(result,a) and filled(result,b),"both legal banks retain polygon fill")

func run() -> void:
	if not ResourceLoader.exists(MODULE_PATH):
		check(false,"river province visual geometry module missing")
		finish()
		return
	var script := load(MODULE_PATH) as Script
	if script == null or not script.can_instantiate():
		check(false,"river province visual geometry cannot instantiate")
		finish()
		return
	model = script.new()
	if not model.has_method("build"):
		check(false,"build API missing")
		finish()
		return
	var state := fixture()
	var original_ids := state.province_ids.duplicate()
	var original_rivers := state.river_features.duplicate(true)
	for size in [64,256]:
		var source := height_image(size)
		var result := build(state,source,size)
		if not result.has("city_id") or not result.has("region_coverage"): continue
		assert_banks(result,state.river_features[0].points,size)
		check(pick(result,Vector2(0.06,0.06)) == -1 and not filled(result,Vector2(0.06,0.06)),"terrain sea remains unassigned and unfilled")
		# City 0 is closer here, but the legal, connected territory belongs to 2.
		var inherited := Vector2(0.22,0.55)
		check(inherited.distance_to(state.cities[0].map_position) < inherited.distance_to(state.cities[2].map_position),"fixture really contains non-nearest-city ownership")
		check(pick(result,inherited) == 2,"far-from-river province ownership survives visual refinement")
		var repeat := build(state,source,size)
		check(result.city_id.get_data() == repeat.city_id.get_data() and result.region_coverage.get_data() == repeat.region_coverage.get_data(),"repeated build preserves visual and picking content")
	check(state.province_ids == original_ids and state.river_features == original_rivers,"visual build never rewrites simulation provinces or rivers")
	var source := height_image(256)
	var baseline := build(state,source,256)
	# Extend city 2's connected land by one cell column, away from any river.
	for y in range(16,32): state.province_ids[y*32+8] = 2
	var changed_ids := build(state,source,256)
	check(pick(baseline,Vector2(8.5/32,18.5/32)) == 0 and pick(changed_ids,Vector2(8.5/32,18.5/32)) == 2,"province ID edits invalidate cached visual ownership")
	state.province_ids = original_ids.duplicate()
	var shifted: PackedVector2Array = state.river_features[0].points.duplicate()
	for i in range(shifted.size()): shifted[i].x -= 0.006
	state.river_features[0].points = shifted
	var changed_river := build(state,source,256)
	check(changed_river.city_id.get_data() != baseline.city_id.get_data(),"river geometry edits invalidate cached bank geometry")
	state.river_features = original_rivers.duplicate(true)
	state.river_features[0].river_class = "minor"
	var minor := build(state,source,256)
	check(pick(minor,Vector2(0.505,0.58)) == 1,"minor river cannot move original x=.5 province boundary")
	var root_state := fixture()
	root_state.province_ids.fill(0)
	root_state.river_features[0].points = PackedVector2Array([Vector2(0.5,0.5),Vector2(0.5,1)])
	var root := build(root_state,source,256)
	check(pick(root,Vector2(0.495,0.501)) == 0 and pick(root,Vector2(0.505,0.501)) == 0,"true source neighborhood may keep the same province on both banks")
	finish()

func finish() -> void:
	print("RIVER_BANK_VISUALS: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
