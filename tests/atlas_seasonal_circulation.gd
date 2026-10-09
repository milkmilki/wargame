extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("CIRCULATION_FAIL ",message)
func _initialize() -> void:
	var model = load("res://scripts/atlas/seasonal_circulation.gd")
	if not model: print("CIRCULATION_FAIL missing model"); quit(1); return
	var size := Vector2i(72,36); var zero := PackedFloat32Array(); zero.resize(size.x*size.y)
	var wind: Dictionary = model.wind_fields(zero,size,0.)
	check(wind.u[15*size.x+20]<0,"tropical trade winds missing")
	check(wind.u[9*size.x+20]>0,"European latitude westerlies missing")
	check(wind.v[15*size.x+20]<0 and wind.v[20*size.x+20]>0,"trade winds must converge toward equator")
	var land := PackedByteArray(); land.resize(zero.size()); land.fill(1)
	var sealed: Dictionary = model.build_fields(zero,land,size,{"spinup_steps":40})
	check(Array(sealed.annual).max()==0.,"rain without water source")
	for y in range(size.y):
		for x in range(24): land[y*size.x+x] = 0
	var wet: Dictionary = model.build_fields(zero,land,size,{"spinup_steps":60})
	check(Array(wet.annual).max()>0.,"ocean did not supply moisture")
	var repeated: Dictionary = model.build_fields(zero,land,size,{"spinup_steps":60})
	check(wet.annual==repeated.annual,"non-deterministic weather")
	for i in range(zero.size()):
		var mean := 0.
		for quarter in wet.quarters: mean += quarter[i]*.25
		check(absf(wet.annual[i]-mean)<.001,"annual rainfall not mean of seasons")
		check(is_finite(wet.annual[i]) and wet.annual[i]>=0,"invalid precipitation")
	var shifted := land.duplicate()
	for y in range(size.y):
		for x in range(size.x): shifted[y*size.x+(x+13)%size.x] = land[y*size.x+x]
	var moved: Dictionary = model.build_fields(zero,shifted,size,{"spinup_steps":60})
	var difference := 0.
	for y in range(size.y):
		for x in range(size.x): difference = maxf(difference,absf(wet.annual[y*size.x+x]-moved.annual[y*size.x+(x+13)%size.x]))
	check(difference<.001,"arbitrary date-line seam")
	print("ATLAS_SEASONAL_CIRCULATION failures=",failures); quit(1 if failures else 0)
