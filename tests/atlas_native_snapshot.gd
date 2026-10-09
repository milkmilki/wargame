extends SceneTree
const Snapshot = preload("res://scripts/atlas/snapshot.gd")
const Generator = preload("res://scripts/atlas/generator.gd")
func _initialize() -> void:
	var generated: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-1.bin",FileAccess.READ).get_var(false)
	var payload := {"format":Snapshot.FORMAT,"version":Snapshot.VERSION,"data":generated.data,"raster":generated.raster,"display":generated.display,"provinces":Generator.pixel_regions(generated.data,generated.raster)}
	var errors := 0; var path := "res://.dbg/atlas-test.snapshot"
	var error := Snapshot.save_file(path,payload)
	if not error.is_empty(): errors += 1; print("SNAPSHOT_FAIL save ",error)
	var result := Snapshot.load_file(path)
	if result.has("error"): errors += 1; print("SNAPSHOT_FAIL load ",result.error)
	else:
		for key in ["data","raster","display","provinces"]:
			if var_to_bytes(result.payload[key])!=var_to_bytes(payload[key]): errors += 1; print("SNAPSHOT_FAIL roundtrip ",key)
	var saved_cell: int = payload.raster.cell[0]; payload.raster.cell[0] = 99999999
	if Snapshot.validate(payload).is_empty(): errors += 1; print("SNAPSHOT_FAIL invalid raster accepted")
	payload.raster.cell[0] = saved_cell
	FileAccess.open(path,FileAccess.WRITE).store_var({"format":Snapshot.FORMAT,"version":999},false)
	if not Snapshot.load_file(path).has("error"): errors += 1; print("SNAPSHOT_FAIL invalid version accepted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("ATLAS_NATIVE_SNAPSHOT failures=",errors); quit(1 if errors else 0)
