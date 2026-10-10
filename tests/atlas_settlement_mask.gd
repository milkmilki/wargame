extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func run():
	var path := "res://scripts/atlas/settlement_mask.gd"
	if not FileAccess.file_exists(path):
		check(false,"geographic settlement mask is implemented")
	else:
		var mask = load(path)
		var settings: Dictionary = mask.EURASIA.duplicate()
		var points := [Vector2(12.5,41.9),Vector2(116.4,39.9),Vector2(0,20),Vector2(145,55),
			Vector2(-15,35),Vector2(-74,40.7),Vector2(110,19),Vector2(150,40),Vector2(10,-30)]
		var mesh := {"n":points.size(),"width":2048.,"height":1024.,"x":PackedFloat32Array(),"y":PackedFloat32Array()}
		for point in points:
			mesh.x.append((point.x+180.)/360.*2048.);mesh.y.append((90.-point.y)/180.*1024.)
		var suit := PackedFloat32Array();suit.resize(points.size());suit.fill(8.)
		var capacity := suit.duplicate(); var fields := {"suitability":suit,"capacity":capacity}
		var original := var_to_bytes(fields)
		mask.apply(mesh,fields,{})
		check(var_to_bytes(fields)==original,"missing mask retains legacy values exactly")
		var off: Dictionary = settings.duplicate();off.enabled=false
		mask.apply(mesh,fields,off)
		check(var_to_bytes(fields)==original,"disabled mask retains all values exactly")
		mask.apply(mesh,fields,settings)
		for index in range(points.size()):
			var inside := index<5
			check(fields.suitability[index]==(8. if inside else 0.),"suitability clips point %s"%points[index])
			check(fields.capacity[index]==(8. if inside else 0.),"capacity clips point %s"%points[index])
		check(suit[-1]==8. and capacity[-1]==8.,"mask does not mutate the source packed arrays")
		var invalid: Dictionary = settings.duplicate();invalid.south=60.
		check(not mask.validate(invalid).is_empty(),"inverted latitude limits are rejected")
		invalid=settings.duplicate();invalid.west=INF
		check(not mask.validate(invalid).is_empty(),"non-finite longitude is rejected")
		check(not mask.validate("bad").is_empty(),"wrong option type is rejected")
		var wrap: Dictionary=settings.duplicate();wrap.west=170.;wrap.east=-170.
		check(mask.contains(179.,40.,wrap) and mask.contains(-179.,40.,wrap) and not mask.contains(0.,40.,wrap),"longitude limits support the date line")
		var cache=load("res://scripts/atlas/startup_cache.gd")
		var key: String=cache.key_for(1,1.,{"settlement_mask":mask.normalize(settings)},"same-code")
		check(key!=cache.key_for(1,1.,{},"same-code"),"mask cannot reuse global startup data")
		check(key!=cache.key_for(1,1.,{"settlement_mask":mask.normalize(off)},"same-code"),"disabled state gets a different startup key")
	for message in failures: printerr("ATLAS_SETTLEMENT_MASK_FAIL ",message)
	print("ATLAS_SETTLEMENT_MASK checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
