extends SceneTree
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
func _initialize() -> void:
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/atlas_native_display_cases.json")); var errors := 0
	for c in cases:
		var labels := PackedInt32Array(c.raw); var original := labels.duplicate()
		Geometry.band_labels(labels,c.w,c.h,c.lines,PackedByteArray(c.weak))
		if labels!=PackedInt32Array(c.expected): errors += 1; print("DISPLAY_CASE_DIFF ",c.kind)
		for i in range(labels.size()):
			if original[i]==-2 and labels[i]!=-2: errors += 1; print("DISPLAY_CASE_DIFF invalid sea fill")
	print("ATLAS_NATIVE_DISPLAY_CASES cases=",cases.size()," failures=",errors); quit(1 if errors else 0)
