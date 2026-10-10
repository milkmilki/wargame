extends RefCounted
## Worker-only numerical preparation. Fill, picking, borders and labels publish
## as one revision after all GPU uploads complete on the main thread.
const Borders = preload("res://scripts/atlas/borders.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Zoom = preload("res://scripts/atlas/zoom_geometry.gd")
const Wash = preload("res://scripts/atlas/wash.gd")
const Labels = preload("res://scripts/atlas/polity_labels.gd")
const Persistent = preload("res://scripts/atlas/persistent_strokes.gd")
const Fronts = preload("res://scripts/atlas/war_fronts.gd")
static func calculate(input: Dictionary) -> Dictionary:
	var lines := Borders.build(input.chains,input.ownership,input.mesh,input.raster,input.region_of)
	var index := Zoom.build(lines); var labels := PackedInt32Array(); labels.resize(input.provinces.size())
	for i in range(labels.size()): labels[i] = input.ownership[input.provinces[i]] if input.provinces[i]>=0 else -2
	Geometry.band_labels(labels,2048,1024,lines,input.weak)
	var colors: Array = []
	for nation in input.data.nations: colors.append(Color8(nation.color[0],nation.color[1],nation.color[2]))
	var grid := PackedInt32Array(); grid.resize(512*256)
	for y in range(256):
		for x in range(512): grid[y*512+x] = input.provinces[(y*4+2)*2048+x*4+2]
	var normal: Array = []; var fronts: Array = []; var teeth: Array = []
	for line in lines:
		var key := "%d:%d"%[mini(line.left,line.right),maxi(line.left,line.right)]
		var path := Geometry.points(line.pts)
		if input.fronts.roles.has(key):
			if input.fronts.roles[key]==line.left: path.reverse()
			fronts.append(path); teeth.append_array(Fronts.teeth(path,Fronts.TOOTH_STEP,Fronts.TOOTH_LENGTH))
		else: normal.append(path)
	return {"lines":lines,"index":index,"labels":labels,"segments":Zoom.texture_data(index),"edge":Wash.edge_data(labels,2048,1024),"color":Wash.color_data(labels,2048,1024,colors),"names":Labels.fit_all(input.data,Labels.field(grid,input.ownership,512,256)),"stroke_plans":{"normal":Persistent.plan(normal),"front":Persistent.plan(fronts),"teeth":Persistent.plan(teeth)},"stroke_keys":{"normal":hash(normal),"front":hash(fronts),"teeth":hash(teeth)}}
