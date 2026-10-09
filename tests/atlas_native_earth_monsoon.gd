extends SceneTree
const World = preload("res://scripts/atlas/world.gd")
const Monsoon = preload("res://scripts/atlas/monsoon_rainfall.gd")
const Earth = preload("res://scripts/atlas/earth_surface.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("EARTH_MONSOON_FAIL ",message)
func _initialize() -> void:
	var original := World.generate({"seed":1,"terrain_model":"earth","rainfall_model":"atlas_original"})
	var wet := World.generate({"seed":1,"terrain_model":"earth","rainfall_model":Monsoon.VERSION})
	check(wet.params.rainfall_model==Monsoon.VERSION,"legacy model selection")
	check(wet.mesh.xyz==original.mesh.xyz and wet.mesh.triangles==original.mesh.triangles,"rainfall changed mesh")
	for field in ["elevation","water","temperature","seaIce"]:
		check(wet[field]==original[field],"rainfall changed "+field)
	var repeat := Monsoon.build(Earth.load_surface(),wet.mesh)
	var east_before := 0.; var east_after := 0.; var dry_before := 0.; var dry_after := 0.
	for cell in range(wet.mesh.n):
		if wet.water[cell]:
			check(wet.precipitation[cell]==original.precipitation[cell],"ocean climate changed")
			continue
		check(is_finite(wet.precipitation[cell]) and wet.precipitation[cell]>=0,"invalid rain")
		check(wet.precipitation[cell]==repeat.precipitation[cell],"non-deterministic transport")
		check(wet.precipitation[cell]==maxf(wet.annual_precipitation[cell],wet.seasonal_precipitation[cell]),"seasonal counted twice")
		check(wet.biome[cell]==World.biome(wet.temperature[cell],wet.precipitation[cell],wet.water[cell],wet.seaIce[cell]),"biomes did not use new rain")
		var lon: float = wet.mesh.x[cell]/2048.*360.-180.; var lat: float = 90.-wet.mesh.y[cell]/1024.*180.; var a: float = wet.mesh.areas[cell]
		if lon>=105 and lon<122 and lat>=22 and lat<42:
			east_before += original.precipitation[cell]*a; east_after += wet.precipitation[cell]*a
		if lon>=-10 and lon<30 and lat>=20 and lat<30:
			dry_before += original.precipitation[cell]*a; dry_after += wet.precipitation[cell]*a
	check(east_after>east_before,"onshore East Asia did not gain moisture")
	check(dry_after<dry_before,"dry subtropical interior became wetter")
	check(wet.rivers.is_empty(),"visible rivers returned")
	check(not World.generate({"terrain_model":"earth","rainfall_model":"invalid"}).get("error","").is_empty(),"invalid model silently accepted")
	print("ATLAS_NATIVE_EARTH_MONSOON failures=",failures); quit(1 if failures else 0)
