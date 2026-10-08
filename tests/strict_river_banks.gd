extends SceneTree
const MODULE_PATH := "res://scripts/core/river_province_constraints.gd"
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")
const SIZE := Vector2i(128,128)
var failures: Array[String] = []
var constraints_model: RefCounted
var generator: Script

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("STRICT_RIVER_BANKS_FAIL: ",message)

func river(id: int, start_y: float, end_y: float, kind: String = "major", downstream: int = -1, upstream: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	return MapFeatureContract.make_river(id,PackedVector2Array([Vector2(0.5,start_y),Vector2(0.5,end_y)]),MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY,0.3,0.9,downstream,upstream,kind,"sea")

func cell(x: int,y: int) -> int: return y*SIZE.x+x

func has_pair(constraints: Dictionary,a: int,b: int) -> bool:
	return constraints.get("opposites",{}).get(a,PackedInt32Array()).has(b)

func grow(features: Array,seeds: Array[Vector2i],constraints: Dictionary) -> Dictionary:
	var image := Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,0.6))
	var land := PackedByteArray()
	land.resize(SIZE.x*SIZE.y)
	land.fill(1)
	var paths: Array[Array] = []
	return generator.callv("_build_province_raster",[image,land,Rect2i(Vector2i.ZERO,SIZE),seeds,paths,1.0,true,Hydro.barriers(features,SIZE),constraints])

func connectivity(ids: PackedInt32Array,seeds: Array[Vector2i],blocked: Dictionary,label: String) -> void:
	for owner in range(seeds.size()):
		var start := cell(seeds[owner].x,seeds[owner].y)
		check(ids[start] == owner,label+" preserves city seed ownership")
		var visited := {start:true}
		var queue := PackedInt32Array([start])
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			var p := Vector2i(current%SIZE.x,current/SIZE.x)
			for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var q: Vector2i = p+step
				if not Rect2i(Vector2i.ZERO,SIZE).has_point(q): continue
				var next := cell(q.x,q.y)
				if ids[next] != owner or visited.has(next) or blocked.has(Hydro.edge_key(current,next,ids.size())): continue
				visited[next] = true
				queue.append(next)
		for i in range(ids.size()):
			if ids[i] == owner and not visited.has(i):
				check(false,label+" assigned province cell is disconnected from its city: %d" % i)
				break

func bank_owners(ids: PackedInt32Array, constraints: Dictionary,label: String) -> void:
	for a in constraints.opposites:
		for b in constraints.opposites[a]:
			if ids[a] >= 0 and ids[a] == ids[b]:
				check(false,label+" one province owns both constrained river banks: %d,%d" % [a,b])
				return

func run() -> void:
	if not ResourceLoader.exists(MODULE_PATH):
		check(false,"RiverProvinceConstraints module missing")
		finish()
		return
	var script := load(MODULE_PATH) as Script
	if script == null or not script.can_instantiate():
		check(false,"constraints module cannot instantiate")
		finish()
		return
	constraints_model = script.new()
	generator = load("res://scripts/core/terrain_map_generator.gd") as Script
	var argument_count := 0
	for method in generator.get_script_method_list():
		if method.name == "_build_province_raster": argument_count = method.args.size()
	if not constraints_model.has_method("build") or argument_count < 9:
		check(false,"build or ninth bank_constraints raster argument missing")
		finish()
		return
	var features: Array = [river(0,0.251,1.0)]
	var constraints: Dictionary = constraints_model.call("build",features,SIZE,1.0)
	check(constraints.has("opposites"),"constraint result exposes opposites")
	if not constraints.has("opposites"):
		finish()
		return
	check(not has_pair(constraints,cell(63,32),cell(64,32)),"true network source has tiny 0.008 exemption")
	check(has_pair(constraints,cell(63,64),cell(64,64)),"middle river has opposite bank constraint")
	check(has_pair(constraints,cell(64,64),cell(63,64)),"opposite bank constraint is symmetric")
	var one_seed: Array[Vector2i] = [Vector2i(48,80)]
	var first := grow(features,one_seed,constraints)
	bank_owners(first.ids,constraints,"one city")
	connectivity(first.ids,one_seed,Hydro.barriers(features,SIZE),"one city")
	check(first.ids[cell(80,20)] == 0,"finite river still permits connected land above its source")
	check(first.ids[cell(63,80)] != first.ids[cell(64,80)] or first.ids[cell(63,80)] < 0,"single city cannot claim both middle banks by detouring around source")
	var two_seeds: Array[Vector2i] = [Vector2i(48,80),Vector2i(80,80)]
	var two := grow(features,two_seeds,constraints)
	bank_owners(two.ids,constraints,"two cities")
	connectivity(two.ids,two_seeds,Hydro.barriers(features,SIZE),"two cities")
	check(two.ids[cell(63,80)] == 0 and two.ids[cell(64,80)] == 1,"two cities establish different owners on opposite middle banks")
	var split: Array = [river(0,0.251,0.501,"major",1),river(1,0.501,1.0,"major",-1,PackedInt32Array([0]))]
	var split_constraints: Dictionary = constraints_model.call("build",split,SIZE,1.0)
	check(has_pair(split_constraints,cell(63,64),cell(64,64)),"internal reach start is not another exempt river source")
	check(split_constraints.opposites.size() == constraints.opposites.size(),"splitting reach does not change constrained cells")
	for a in constraints.opposites:
		for b in constraints.opposites[a]: check(has_pair(split_constraints,a,b),"splitting reach preserves each opposite-bank relation")
	var minor: Array = [river(0,0.251,1.0,"minor")]
	var minor_constraints: Dictionary = constraints_model.call("build",minor,SIZE,1.0)
	check(minor_constraints.get("opposites",{}).is_empty(),"minor river has no strict province bank constraints")
	var minor_result := grow(minor,one_seed,minor_constraints)
	for owner in minor_result.ids:
		if owner != 0:
			check(false,"minor river does not obstruct single-city province growth")
			break
	connectivity(minor_result.ids,one_seed,{},"minor river")
	finish()

func finish() -> void:
	print("STRICT_RIVER_BANKS: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
