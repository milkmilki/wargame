extends SceneTree
func _initialize() -> void:
	var payload: Dictionary = FileAccess.open("res://.dbg/atlas-military-earth.bin",FileAccess.READ).get_var(false)
	var sea_centers := 0; var sea_fu := 0; var max_land_offset := 0.
	for city in payload.hierarchy.cities:
		var point := Vector2(payload.data.mesh.x[city.cell],payload.data.mesh.y[city.cell]); var x := posmod(roundi(point.x),2048); var y := clampi(roundi(point.y),0,1023)
		if payload.raster.water[y*2048+x]==0: continue
		if city.role=="zhou": sea_centers += 1
		else: sea_fu += 1
		var nearest := INF
		for dy in range(-8,9):
			for dx in range(-8,9):
				if y+dy<0 or y+dy>=1024: continue
				if payload.raster.water[(y+dy)*2048+posmod(x+dx,2048)]==0: nearest = minf(nearest,Vector2(dx,dy).length())
		max_land_offset = maxf(max_land_offset,nearest)
	print("ATLAS_VISUAL_LAND centers_on_raster_water=",sea_centers," fu_on_raster_water=",sea_fu," max_offset=",max_land_offset); quit(0)
