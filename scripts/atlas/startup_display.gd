extends RefCounted
## Initial numeric display plans. No nodes, fonts, GPU resources or game state.
const Fields = preload("res://scripts/atlas/paint_fields.gd")
const Borders = preload("res://scripts/atlas/borders.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Zoom = preload("res://scripts/atlas/zoom_geometry.gd")
const Wash = preload("res://scripts/atlas/wash.gd")
const Ice = preload("res://scripts/atlas/ice_geometry.gd")
const Coast = preload("res://scripts/atlas/coast_ink.gd")
const Labels = preload("res://scripts/atlas/polity_labels.gd")
static func geometry(data: Dictionary,raster: Dictionary,provinces: PackedInt32Array) -> Dictionary:
	var chains := Borders.trace(data.mesh,PackedInt32Array(data.regions.of))
	var lines := Borders.build(chains,PackedInt32Array(data.ownership),data.mesh,raster,PackedInt32Array(data.regions.of))
	var owners := PackedInt32Array(); owners.resize(data.regions.count)
	for i in range(owners.size()): owners[i]=i
	var province_lines := Borders.build(chains,owners,data.mesh,raster,PackedInt32Array(data.regions.of))
	var political_index := Zoom.build(lines); var province_index := Zoom.build(province_lines)
	var weak := PackedByteArray(); weak.resize(provinces.size())
	var province_labels := provinces.duplicate(); var political_labels := province_labels.duplicate()
	for i in range(provinces.size()):
		weak[i]=int(raster.water[i]==0 and data.regions.of[raster.cell[i]]<0)
		if province_labels[i]<0: province_labels[i]=-2
		political_labels[i]=int(data.ownership[provinces[i]]) if provinces[i]>=0 else -2
	Geometry.band_labels(province_labels,2048,1024,province_lines,weak)
	Geometry.band_labels(political_labels,2048,1024,lines,weak)
	var grid := PackedInt32Array(); grid.resize(512*256)
	for y in range(256):
		for x in range(512): grid[y*512+x]=provinces[(y*4+2)*2048+x*4+2]
	var state_lines: Array=[]
	if data.has("parent_regions"):
		var parent: Dictionary=data.parent_regions; var parent_owners := PackedInt32Array()
		for id in range(parent.count): parent_owners.append(id)
		for line in Borders.build(Borders.trace(data.mesh,parent.of),parent_owners,data.mesh,raster,parent.of): state_lines.append(Geometry.points(line.pts))
	return {"chains":chains,"lines":lines,"province_lines":province_lines,"state_lines":state_lines,"political_index":political_index,"province_index":province_index,"political_segments":Zoom.texture_data(political_index),"province_segments":Zoom.texture_data(province_index),"province_labels":province_labels,"political_labels":political_labels,"political_ids":Wash.id_data(political_labels,2048,1024),"weak":weak,"province_edge":Wash.edge_data(province_labels,2048,1024),"political_edge":Wash.edge_data(political_labels,2048,1024),"names":Labels.fit_all(data,Labels.field(grid,PackedInt32Array(data.ownership),512,256))}
static func prepare(data: Dictionary,raster: Dictionary,provinces: PackedInt32Array,glyphs: Array) -> Dictionary:
	var started := Time.get_ticks_msec(); var ice := Fields.ice_field(raster)
	var result := {"ice":ice}; var mutex := Mutex.new()
	var jobs: Array=[func(): return geometry(data,raster,provinces),func(): return Fields.texture_data(raster,data,glyphs,ice),func(): return Fields.habitat_data(data,raster),func(): return Ice.data(raster,ice.mask),func(): return Coast.prepare(raster,ice)]
	var keys := ["geometry","fields","habitat","ice_geometry","coast"]
	var task := WorkerThreadPool.add_group_task(func(i):
		var begin := Time.get_ticks_msec(); var value: Dictionary=jobs[i].call()
		mutex.lock(); result[keys[i]]=value; result[keys[i]+"_ms"]=Time.get_ticks_msec()-begin; mutex.unlock(),jobs.size(),mini(4,maxi(1,OS.get_processor_count()-1)),false,"Atlas startup display")
	WorkerThreadPool.wait_for_group_task_completion(task)
	result.total_ms=Time.get_ticks_msec()-started; return result
