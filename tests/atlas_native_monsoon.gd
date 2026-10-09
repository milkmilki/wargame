extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("MONSOON_FAIL ",message)
func _initialize() -> void:
	var model = load("res://scripts/core/rainfall_transport.gd")
	if not model: print("MONSOON_FAIL missing reusable rainfall model"); quit(1); return
	var fixture: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/atlas_legacy_rainfall.json"))
	var size := Vector2i(64,32); var lat := PackedFloat32Array(); lat.resize(size.y)
	for y in range(size.y): lat[y] = 60.-y*1.8
	for sample in fixture:
		var land := PackedByteArray(); land.resize(size.x*size.y); var heights := PackedFloat32Array(); heights.resize(land.size())
		for y in range(size.y):
			for x in range(size.x):
				var i := y*size.x+x; land[i] = 1 if x>12 and x<52 else 0
				heights[i] = (3000. if sample.kind==1 and x>=28 and x<=32 else 2400. if sample.kind==2 and x>=28 and x<=32 else 50.)/6200.
				if sample.kind==3 and x>=40 and x<=41: land[i] = 0
		check(model.build(heights,land,size,lat,2.3)==PackedFloat32Array(sample.rain),"legacy defaults changed "+str(sample.kind))
	# A cyclic shift must not create rainfall at the arbitrary date-line cut.
	var land := PackedByteArray(); land.resize(size.x*size.y); var heights := PackedFloat32Array(); heights.resize(land.size()); lat.fill(35.)
	for y in range(size.y):
		for x in range(size.x): land[y*size.x+x] = 1 if x>=15 and x<48 else 0
	var options := {"wrap_x":true,"distance_scale":5.,"latitude_distance":true}
	var before: PackedFloat32Array = model.build(heights,land,size,lat,2.,options)
	var shifted := land.duplicate()
	for y in range(size.y):
		for x in range(size.x): shifted[y*size.x+(x+17)%size.x] = land[y*size.x+x]
	var after: PackedFloat32Array = model.build(heights,shifted,size,lat,2.,options)
	var error := 0.
	for y in range(size.y):
		for x in range(size.x): error = maxf(error,absf(before[y*size.x+x]-after[y*size.x+(x+17)%size.x]))
	check(error<1e-6,"date-line rainfall seam "+str(error))
	check(Array(before).max()>.1,"ocean did not transport moisture")
	var wet: Dictionary = model.build_fields(heights,land,size,lat,2.,options)
	check(wet.seasonal[16*size.x+47]>wet.seasonal[16*size.x+30],"summer moisture must decrease inland")
	check(wet.rainfall[16*size.x+47]>wet.annual[16*size.x+47],"summer moisture never supports onshore settlements")
	var dry_land := land.duplicate(); dry_land.fill(1)
	var dry: Dictionary = model.build_fields(heights,dry_land,size,lat,2.,options)
	check(Array(dry.seasonal).max()==0.,"summer support invented moisture without a water source")
	check(Array(dry.rainfall).max()<Array(before).max(),"removing ocean did not reduce moisture")
	print("ATLAS_NATIVE_MONSOON failures=",failures); quit(1 if failures else 0)
