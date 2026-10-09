extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("EARTH_FAIL ",message)
func _initialize() -> void:
	var source = load("res://scripts/atlas/earth_surface.gd")
	if not source: print("EARTH_FAIL missing native Earth input"); quit(1); return
	var surface = source.load_surface()
	check(not surface.is_empty(),"Earth data could not be read")
	if surface.is_empty(): quit(1); return
	for point in [[116.4,39.9,0],[10.,51.,0],[-100.,40.,0],[135.,-25.,0],[-30.,30.,1],[-150.,0.,1],[80.,-30.,1],[50.,42.,2],[-87.,44.,2]]:
		check(source.water_at(surface,point[0],point[1])==point[2],"land/ocean/lake longitude/latitude "+str(point))
	check(source.water_at(surface,34.,43.)==1,"Black Sea must remain sea despite subpixel Bosporus")
	check(source.elevation_at(surface,86.5,28.)>4000,"Himalayas lack real elevation")
	check(source.elevation_at(surface,-150.,0.)< -2000,"Pacific lacks bathymetry")
	check(absf(source.elevation_at(surface,-180.,12.)-source.elevation_at(surface,180.,12.))<.001,"longitude wrap")
	check(is_finite(source.elevation_at(surface,0.,90.)) and is_finite(source.elevation_at(surface,0.,-90.)),"pole clamping")
	print("ATLAS_NATIVE_EARTH failures=",failures); quit(1 if failures else 0)
