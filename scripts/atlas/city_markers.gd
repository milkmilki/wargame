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
var hit_boxes: Array = []
var publication_version := 0
var hovered_city := -1
var previous_city := -1
var hover_amount := 0.
var previous_amount := 0.
const HOVER_DURATION := .12
func _init() -> void: set_process(false)
func set_hover_city(id: int) -> void:
	if id==hovered_city: return
	var retained := hover_weight(id) if id>=0 else 0.
	previous_city=hovered_city; previous_amount=hover_amount
	hovered_city=id; hover_amount=retained
	set_process(true); publish_hover()
func hover_weight(id: int) -> float:
	if id<0: return 0.
	return maxf(hover_amount if id==hovered_city else 0.,previous_amount if id==previous_city else 0.)
func _process(delta: float) -> void:
	hover_amount=move_toward(hover_amount,1. if hovered_city>=0 else 0.,delta/HOVER_DURATION)
	previous_amount=move_toward(previous_amount,0.,delta/HOVER_DURATION)
	publish_hover()
	if previous_amount==0. and (hovered_city<0 or hover_amount==1.): set_process(false)
func publish_hover() -> void:
	for layer in layers:
		for node in layer.nodes:
			node.material.set_shader_parameter("hovered_city",float(hovered_city))
			node.material.set_shader_parameter("hover_amount",hover_amount)
			node.material.set_shader_parameter("previous_city",float(previous_city))
			node.material.set_shader_parameter("previous_amount",previous_amount)
func hit_city(point: Vector2,period: float) -> int:
	for row in hit_boxes:
		var factor:=1.+.15*hover_weight(row.id)
		var box:=Rect2(row.anchor+(row.box.position-row.anchor)*factor,row.box.size*factor)
		for shift in [-period,0.,period]:
			if box.has_point(point+Vector2(shift,0)): return row.id
	return -1
func setup(source: Dictionary) -> void:
	hovered_city=-1; previous_city=-1; hover_amount=0.; previous_amount=0.; set_process(false); publish_hover()
	data = source; index = Index.new(); last_key.clear(); hit_boxes.clear()
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
	last_key = key
	var result := prepare_instances(data,ids,detail,accepted)
	apply_instances(result)
	max_update_usec = maxi(max_update_usec,Time.get_ticks_usec()-start)

static func prepare_instances(source: Dictionary,ids: Array,detail: float,accepted: Array = []) -> Dictionary:
	var permitted := {}
	for mark in accepted: permitted[mark.index]=true
	var jobs: Array = []
	for id in ids:
		if not accepted.is_empty() and not permitted.has(id): continue
		var city: Dictionary = source.cities[id]; var owner := int(source.ownership[city.region]); var kind := City.kind_for(city,owner,source.nations)
		jobs.append({"id":id,"kind":kind,"owner":owner,"point":Vector2(source.mesh.x[city.cell],source.mesh.y[city.cell])*detail})
	jobs.sort_custom(func(a,b): return a.id<b.id if a.kind==b.kind else a.kind>b.kind)
	var hit_boxes: Array = []
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
		hit_boxes.append({"id":job.id,"box":box,"anchor":job.point})
		for cell in buckets:
			if not occupied.has(cell): occupied[cell] = []
			occupied[cell].append(box)
		var color := Color8(150,60,50)
		if job.owner>=0:
			var rgb: Array = source.nations[job.owner].color; color = Color8(rgb[0],rgb[1],rgb[2])
		# Custom alpha carries the stable city id; glyph opacity remains in its
		# vertex colors. Hover changes shader uniforms, never instance buffers.
		buffers[job.kind].append_array(PackedFloat32Array([s,0.,0.,job.point.x,0.,s,0.,job.point.y,color.r,color.g,color.b,float(job.id)])); counts[job.kind] += 1
	for kind in range(5):
		var capacity := 2048 if kind==2 else 128
		buffers[kind].resize(maxi(capacity,ceili(counts[kind]/128.)*128)*12)
	return {"buffers":buffers,"counts":counts,"hit_boxes":hit_boxes,"detail":detail,"ids":ids}

func apply_instances(result: Dictionary) -> void:
	hit_boxes=result.hit_boxes
	var buffers: Array=result.buffers.duplicate(); var counts: Array=result.counts; var detail: float=result.detail
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
	publication_version+=1
