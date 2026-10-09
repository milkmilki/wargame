extends SceneTree
func _initialize() -> void:
	var failures := 0
	for side in ["before","after"]:
		for view in ["world","china","europe","africa","southern-africa","southern-africa-terrain","southern-africa-habitat"]:
			var path := "res://docs/atlas/climate_limits/%s-%s.png"%[side,view]
			var image := Image.load_from_file(path)
			if image==null or image.get_size()!=Vector2i(2048,1024):
				failures += 1; print("CLIMATE_EVIDENCE_FAIL viewport ",path)
	for name_value in ["earth-mode-0","earth-mode-1","earth-mode-2","earth-mode-3","earth-china","earth-eurasia","earth-mediterranean"]:
		var image := Image.load_from_file("res://docs/atlas/earth/"+name_value+".png")
		if image==null or image.get_size()!=Vector2i(2048,1024): failures += 1; print("CLIMATE_EVIDENCE_FAIL viewport ",name_value)
	print("ATLAS_CLIMATE_LIMIT_EVIDENCE failures=",failures); quit(1 if failures else 0)
