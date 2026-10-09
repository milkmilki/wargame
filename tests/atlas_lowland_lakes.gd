extends SceneTree
const Adapter = preload("res://scripts/atlas/circulation_rainfall.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("LOWLAND_LAKE_FAIL ",message)
func _initialize() -> void:
	var size := Vector2i(8,4); var types := PackedByteArray(); types.resize(32)
	var height := PackedFloat32Array(); height.resize(32); height.fill(100.)
	types[10] = 2; types[11] = 2; height[10] = -500.; height[11] = -600.
	check(Adapter.lowland_lake_mask(types,height,size).count(1)==0,"deep lake bed alone does not prove below-sea-level shores")
	height[9] = -5.
	var closed := Adapter.lowland_lake_mask(types,height,size)
	check(closed[10]==1 and closed[11]==1 and closed.count(1)==2,"below-sea-level closed basin not detected")
	types[12] = 1
	check(Adapter.lowland_lake_mask(types,height,size).count(1)==0,"marine connection classified as closed basin")
	types.fill(0); height.fill(100.); types[8] = 2; types[15] = 2; height[16] = -5.
	var seam := Adapter.lowland_lake_mask(types,height,size)
	check(seam[8]==1 and seam[15]==1 and seam.count(1)==2,"date-line lake component split")
	print("ATLAS_LOWLAND_LAKES failures=",failures); quit(1 if failures else 0)
