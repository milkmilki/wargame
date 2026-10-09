extends SceneTree
const Fields = preload("res://scripts/atlas/paint_fields.gd")
func _initialize() -> void:
	var errors := 0
	var mask := PackedByteArray(); mask.resize(35); mask[2*7+6] = 1
	var distances := Fields.distance_to(mask,7,5)
	for y in range(5):
		for x in range(7):
			var dx := mini(absi(x-6),7-absi(x-6)); var dy := y-2
			var expected := PackedFloat32Array([sqrt(dx*dx+dy*dy)])[0]
			if distances[y*7+x]!=expected: errors += 1
	var values := PackedFloat32Array(); values.resize(15); values.fill(7.0)
	Fields.blur(values,5,3,1)
	for v in values:
		if v!=7.0: errors += 1
	print("ATLAS_NATIVE_PAINT_FIELDS failures=",errors); quit(1 if errors else 0)
