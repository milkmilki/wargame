extends RefCounted
## Numeric, cached geometry of the existing TradeNetwork regions; no new rules.
const Borders = preload("res://scripts/atlas/borders.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Zoom = preload("res://scripts/atlas/zoom_geometry.gd")
const Wash = preload("res://scripts/atlas/wash.gd")
static func calculate(input: Dictionary) -> Dictionary:
	var lines := Borders.build(input.chains,input.owners,input.mesh,input.raster,input.region_of)
	var index := Zoom.build(lines)
	var labels := PackedInt32Array(); labels.resize(input.provinces.size()); labels.fill(-2)
	for k in range(labels.size()):
		var district: int=input.provinces[k]
		if district>=0 and district<input.owners.size(): labels[k]=input.owners[district]
	Geometry.band_labels(labels,2048,1024,lines,input.weak)
	var colors: Array=[]
	var palette_size:=int(input.count)
	for owner in input.owners: palette_size=maxi(palette_size,int(owner)+1)
	for id in range(palette_size): colors.append(Color.from_hsv(fposmod(id*.61803398875,1.),.38,.78))
	return {"lines":lines,"labels":labels,"index":index,"segments":Zoom.texture_data(index),"edge":Wash.edge_data(labels,2048,1024),"color":Wash.color_data(labels,2048,1024,colors),"colors":colors}

class Hubs extends Node2D:
	var points := PackedVector2Array()
	var view_zoom := 1.
	func set_points(value: PackedVector2Array):
		if points==value: return
		points=value; queue_redraw()
	func set_zoom(value: float):
		if is_equal_approx(value,view_zoom): return
		view_zoom=value; queue_redraw()
	func _draw():
		var pen:=1./maxf(.1,view_zoom)
		for shift in [-2048.,0.,2048.]:
			draw_set_transform(Vector2(shift,0))
			for p in points:
				draw_circle(p,5.5*pen,Color(.22,.12,.06))
				draw_circle(p,3.7*pen,Color(.98,.77,.30))
				draw_arc(p,8.*pen,0,TAU,24,Color(.27,.15,.05),pen,true)
		draw_set_transform(Vector2.ZERO)
