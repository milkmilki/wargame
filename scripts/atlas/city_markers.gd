extends Node2D
## Reusable native city glyphs, instanced independently of expensive label layout.
const City = preload("res://scripts/atlas/city_symbols.gd")
const Plan = preload("res://scripts/atlas/symbol_mesh.gd")
const Index = preload("res://scripts/atlas/render_index.gd")
class Recorder extends RefCounted:
	var plan := Plan.new()
	func draw_colored_polygon(points: PackedVector2Array,color: Color):
		plan.polygon(points,Color.MAGENTA if color==Color(.85,.85,.85) else color)
	func draw_polyline(points: PackedVector2Array,color: Color,width: float,aa: bool): plan.line(points,color,width,aa)
	func draw_line(a: Vector2,b: Vector2,color: Color,width: float,aa: bool): plan.segment(a,b,color,width,aa)
	func draw_circle(center: Vector2,radius: float,color: Color):
		var points := PackedVector2Array()
		for i in range(32): points.append(center+Vector2(cos(i*TAU/32),sin(i*TAU/32))*radius)
		plan.polygon(points,color)
var data: Dictionary = {}
var index := Index.new()
var layers: Array = []
var template_builds := 0
var visible_count := 0
var last_key: Array = []
var max_update_usec := 0
func setup(source: Dictionary) -> void:
	data = source; index = Index.new(); last_key.clear()
	for city in data.cities: index.add(Rect2(Vector2(data.mesh.x[city.cell],data.mesh.y[city.cell])-Vector2.ONE*16,Vector2.ONE*32))
	if not layers.is_empty(): return
	for kind in range(5):
		var recorder := Recorder.new(); recorder.plan.aa = .15; City.draw(recorder,Vector2.ZERO,1.,kind,Color.WHITE)
		var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_2D; multi.use_custom_data = true
		multi.mesh = Plan.resource(recorder.plan.arrays()); multi.instance_count = 2048 if kind==2 else 128; multi.visible_instance_count = 0
		var nodes: Array = []
		for shift in [-2048.,0.,2048.]:
			var node := MultiMeshInstance2D.new(); node.multimesh = multi
			var material := ShaderMaterial.new(); material.shader = preload("res://assets/atlas/city_instances.gdshader"); node.material = material
			add_child(node); nodes.append(node)
		layers.append({"mesh":multi,"nodes":nodes}); template_builds += 1

func set_view(rect: Rect2,detail: float,accepted: Array = []) -> void:
	if data.is_empty(): return
	var ids := index.query(rect.grow(24./detail)); var key := [ids,detail,hash(accepted)]
	if last_key==key: return
	var start := Time.get_ticks_usec()
	last_key = key; var permitted := {}
	for mark in accepted: permitted[mark.index] = true
	var jobs: Array = []
	for id in ids:
		if not accepted.is_empty() and not permitted.has(id): continue
		var city: Dictionary = data.cities[id]; var owner := int(data.ownership[city.region]); var kind := 3 if city.major else 2
		if owner>=0 and data.nations[owner].seat==city.region: kind = 4
		jobs.append({"id":id,"kind":kind,"owner":owner,"point":Vector2(data.mesh.x[city.cell],data.mesh.y[city.cell])*detail})
	jobs.sort_custom(func(a,b): return a.id<b.id if a.kind==b.kind else a.kind>b.kind)
	var s := sqrt(2048./1300)*pow(maxf(1,detail),.5); var occupied := {}; var counts := [0,0,0,0,0]
	var buffers: Array = [PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
	for job in jobs:
		var reach := Vector4(5,9,5,3.1) if job.kind==4 else Vector4(4.4,4.1,4.4,3) if job.kind==3 else Vector4(3.7,2.7,3.7,2.5)
		var box := Rect2(job.point-Vector2(reach.x,reach.y)*s,Vector2(reach.x+reach.z,reach.y+reach.w)*s)
		var collision := false; var buckets: Array = []
		for y in range(floori(box.position.y/48),floori(box.end.y/48)+1):
			for x in range(floori(box.position.x/48),floori(box.end.x/48)+1):
				var cell := Vector2i(x,y); buckets.append(cell)
				for other in occupied.get(cell,[]):
					if box.intersects(other): collision = true; break
		if collision and job.kind!=4: continue
		for cell in buckets:
			if not occupied.has(cell): occupied[cell] = []
			occupied[cell].append(box)
		var color := Color8(150,60,50)
		if job.owner>=0:
			var rgb: Array = data.nations[job.owner].color; color = Color8(rgb[0],rgb[1],rgb[2])
		buffers[job.kind].append_array(PackedFloat32Array([s,0.,0.,job.point.x,0.,s,0.,job.point.y,color.r,color.g,color.b,color.a])); counts[job.kind] += 1
	visible_count = 0
	for kind in range(5):
		var multi: MultiMesh = layers[kind].mesh
		if counts[kind]>multi.instance_count: multi.instance_count = ceili(counts[kind]/128.)*128
		buffers[kind].resize(multi.instance_count*12); multi.buffer = buffers[kind]
		layers[kind].mesh.visible_instance_count = counts[kind]; visible_count += counts[kind]
		# Bulk instance publication does not invalidate the initial empty canvas
		# commands. Refresh their bounds after an actual buffer change, not on pan.
		for i in range(3):
			layers[kind].nodes[i].position.x = [-2048.,0.,2048.][i]*detail
			layers[kind].nodes[i].queue_redraw()
	max_update_usec = maxi(max_update_usec,Time.get_ticks_usec()-start)
