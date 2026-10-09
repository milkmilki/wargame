extends SceneTree
func _initialize() -> void:
	var Labels = load("res://scripts/atlas/polity_labels.gd")
	if not Labels: quit(1); return
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/name-layout-1.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-native-reference/world-1.json"))
	var field: Dictionary = Labels.field(PackedInt32Array(ref.grid.region),PackedInt32Array(data.ownership),512,256)
	var errors := 0
	if field.dist!=PackedFloat32Array(ref.dist): errors += 1; print("LABEL_DIFF distance")
	var actual: Array = Labels.fit_all(data,field)
	if actual.size()!=ref.labels.size(): errors += 1; print("LABEL_DIFF count ",actual.size())
	else:
		for i in range(actual.size()):
			for key in ["size","vertical","polity","path","anchor"]:
				if key in ["path","anchor"]:
					if actual[i][key].size()!=ref.labels[i][key].size(): errors += 1; continue
					for j in range(actual[i][key].size()):
						if absf(actual[i][key][j]-ref.labels[i][key][j])>1e-10: errors += 1
				elif key=="size":
					if absf(actual[i][key]-ref.labels[i][key])>1e-10: errors += 1; print("LABEL_DIFF ",i," ",key)
				elif actual[i][key]!=ref.labels[i][key]: errors += 1; print("LABEL_DIFF ",i," ",key)
	print("ATLAS_NATIVE_LABELS count=",actual.size()," failures=",errors); quit(1 if errors else 0)
