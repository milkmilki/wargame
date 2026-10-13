extends RefCounted
## Immutable CPU revisions. Only changed pixel blocks reach the GPU staging buffer.
const Borders = preload("res://scripts/atlas/borders.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Zoom = preload("res://scripts/atlas/zoom_geometry.gd")
const Labels = preload("res://scripts/atlas/polity_labels.gd")
const Native = preload("res://scripts/atlas/native_display.gd")
const Persistent = preload("res://scripts/atlas/persistent_strokes.gd")
const Fronts = preload("res://scripts/atlas/war_fronts.gd")
const CityMarkers = preload("res://scripts/atlas/city_markers.gd")
const WIDTH := 2048
const HEIGHT := 1024
const TILE := 128

static func initialize(input: Dictionary,geo: Dictionary) -> Dictionary:
	var grid := PackedInt32Array(); grid.resize(512*256)
	for y in range(256):
		for x in range(512): grid[y*512+x]=input.provinces[(y*4+2)*WIDTH+x*4+2]
	var tiles: Array = []; var hashes: Array = []
	for row in Native.label_tiles(geo.political_labels,WIDTH,HEIGHT,TILE,Native.all_tiles(WIDTH,HEIGHT,TILE)):
		tiles.append(row.bytes); hashes.append(hash(row.bytes))
	return {"ownership":input.ownership,"nations":input.data.nations.duplicate(true),"lines":geo.lines,"index":geo.political_index,"labels":geo.political_labels,"names":geo.names,"grid":grid,"region_tiles":Native.region_tiles(input.provinces,input.ownership.size(),WIDTH,HEIGHT,TILE),"tiles":tiles,"tile_hashes":hashes}

static func mark_line_tiles(line: Dictionary,dirty: Dictionary) -> void:
	# Include removed as well as added geometry. Endpoint bands reach eight pixels.
	var pts: PackedFloat32Array = line.pts
	for i in range(0,pts.size()-2,2):
		for shift in [-float(WIDTH),0.,float(WIDTH)]:
			var x0 := maxi(0,floori((minf(pts[i],pts[i+2])+shift-9)/TILE))
			var x1 := mini(WIDTH/TILE-1,floori((maxf(pts[i],pts[i+2])+shift+9)/TILE))
			var y0 := maxi(0,floori((minf(pts[i+1],pts[i+3])-9)/TILE))
			var y1 := mini(HEIGHT/TILE-1,floori((maxf(pts[i+1],pts[i+3])+9)/TILE))
			for y in range(y0,y1+1):
				for x in range(x0,x1+1): dirty[y*(WIDTH/TILE)+x]=true

static func dirty_for_lines(old: Array,current: Array,dirty: Dictionary) -> void:
	# Reordering equal-distance borders can affect band labels; conservatively
	# mark borders from the first changed position, preserving oracle ordering.
	var first := 0
	while first<mini(old.size(),current.size()) and old[first]==current[first]: first+=1
	if first==old.size() and first==current.size(): return
	for i in range(first,old.size()): mark_line_tiles(old[i],dirty)
	for i in range(first,current.size()): mark_line_tiles(current[i],dirty)

static func calculate(input: Dictionary) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var previous: Dictionary = input.get("cache",{})
	var changed: bool = previous.is_empty() or previous.ownership!=input.ownership
	var lines: Array = Borders.build(input.chains,input.ownership,input.mesh,input.raster,input.region_of) if changed else previous.lines
	var index: Dictionary = Zoom.build(lines) if previous.is_empty() or lines!=previous.lines else previous.index
	var dirty := {}; var affected := {}
	var grid: PackedInt32Array; var region_tiles: Array
	if previous.is_empty():
		grid.resize(512*256)
		for y in range(256):
			for x in range(512): grid[y*512+x]=input.provinces[(y*4+2)*WIDTH+x*4+2]
		region_tiles=Native.region_tiles(input.provinces,input.ownership.size(),WIDTH,HEIGHT,TILE)
		for id in Native.all_tiles(WIDTH,HEIGHT,TILE): dirty[id]=true
		for id in range(input.data.nations.size()): affected[id]=true
	else:
		grid=previous.grid; region_tiles=previous.region_tiles
		for id in range(input.ownership.size()):
			if input.ownership[id]==previous.ownership[id]: continue
			for tile in region_tiles[id]: dirty[tile]=true
			if input.ownership[id]>=0: affected[input.ownership[id]]=true
			if previous.ownership[id]>=0: affected[previous.ownership[id]]=true
		for id in range(input.data.nations.size()):
			if id>=previous.nations.size() or input.data.nations[id]!=previous.nations[id]: affected[id]=true
		dirty_for_lines(previous.lines,lines,dirty)
	var sorted := dirty.keys(); sorted.sort(); var dirty_tiles := PackedInt32Array(sorted)
	var labels: PackedInt32Array = previous.get("labels",PackedInt32Array())
	if not dirty_tiles.is_empty():
		var painted := Native.paint_labels({"provinces":input.provinces,"ownership":input.ownership,"lines":lines,"weak":input.weak,"w":WIDTH,"h":HEIGHT,"tile":TILE,"previous":labels,"dirty_tiles":dirty_tiles})
		labels=painted.labels; dirty_tiles=painted.dirty_tiles
	var tiles: Array = previous.get("tiles",[]).duplicate(); var hashes: Array = previous.get("tile_hashes",[]).duplicate()
	if tiles.is_empty(): tiles.resize(WIDTH/TILE*HEIGHT/TILE); hashes.resize(tiles.size())
	var updates: Array = []
	for row in Native.label_tiles(labels,WIDTH,HEIGHT,TILE,dirty_tiles):
		var id: int=row.id
		if tiles[id]==row.bytes: continue
		tiles[id]=row.bytes; hashes[id]=hash(row.bytes); updates.append(row)
	var names: Array = previous.get("names",[]).duplicate()
	if not affected.is_empty():
		var selected := PackedInt32Array(affected.keys()); selected.sort()
		var field := Native.label_field(grid,input.ownership,512,256)
		names=names.filter(func(row): return not affected.has(row.polity))
		names.append_array(Labels.fit_all(input.data,field,selected,Native.kernel()))
		names.sort_custom(func(a,b): return a.polity<b.polity)
	var normal: Array = []; var fronts: Array = []; var teeth: Array = []
	for line in lines:
		var key := "%d:%d"%[mini(line.left,line.right),maxi(line.left,line.right)]
		var path := Geometry.points(line.pts)
		if input.fronts.roles.has(key):
			if input.fronts.roles[key]==line.left: path.reverse()
			fronts.append(path); teeth.append_array(Fronts.teeth(path,Fronts.TOOTH_STEP,Fronts.TOOTH_LENGTH))
		else: normal.append(path)
	var paths := {"normal":normal,"front":fronts,"teeth":teeth}; var plans := {}; var keys := {}
	for kind in paths:
		keys[kind]=hash(paths[kind])
		if previous.get("stroke_keys",{}).get(kind)!=keys[kind]: plans[kind]=Persistent.plan(paths[kind])
	var cache := {"ownership":input.ownership,"nations":input.data.nations,"lines":lines,"index":index,"labels":labels,"names":names,"grid":grid,"region_tiles":region_tiles,"tiles":tiles,"tile_hashes":hashes,"stroke_keys":keys}
	var marker_plan := {}
	if input.data.has("cities") and (changed or not affected.is_empty()):
		marker_plan=CityMarkers.prepare_instances(input.data,range(input.data.cities.size()),4.)
	return {"cache":cache,"lines":lines,"index":index,"labels":labels,"names":names,"dirty_tiles":dirty_tiles,"tile_updates":updates,"segments":Zoom.texture_data(index) if previous.is_empty() or index!=previous.index else {},"edge":Native.edge_data(labels,WIDTH,HEIGHT) if not updates.is_empty() else {},"stroke_plans":plans,"stroke_keys":keys,"marker_plan":marker_plan,"content_changed":changed or not affected.is_empty(),"compute_usec":Time.get_ticks_usec()-begin}
