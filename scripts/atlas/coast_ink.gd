extends Node2D
## Zoom coast/lake/ripple vectors from original fantasy.ts. AGPL-3.0-only.
const Contours = preload("res://scripts/atlas/contours.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Strokes = preload("res://scripts/atlas/ink_strokes.gd")
const Fields = preload("res://scripts/atlas/paint_fields.gd")
const Persistent = preload("res://scripts/atlas/persistent_strokes.gd")
var high_performance := false
var persistent_layers: Array = []
var fade_texture: ImageTexture
var scheduler: Node
var geometry_pool := {}
var coast: Array = []
var lake: Array = []
var rings: Array = []
var meshes: Array = []
var zoom := 1.
var last_zoom := -1.
var ripple_nodes: Array = []
var visible_world := Rect2(0,0,2048,1024)
var last_rect := Rect2()
var chunks: Array = []
var mesh_build_count := 0
var render_rect := Rect2()
static func chunk(lines: Array) -> Array:
	var out: Array = []
	for p in lines:
		for start in range(0,p.size()-1,48):
			var points: PackedVector2Array = p.slice(start,mini(start+49,p.size())); var box := Rect2(points[0],Vector2.ZERO)
			for point in points: box = box.expand(point)
			out.append({"p":points,"box":box})
	return out
func in_view(source: Array) -> Array:
	var out: Array = []; var rect := render_rect.grow(3.)
	for c in source:
		for shift in [-2048.,0.,2048.]:
			if rect.intersects(Rect2(c.box.position+Vector2(shift,0),c.box.size),true): out.append(c.p); break
	return out
static func prepare(raster: Dictionary,prepared_ice: Dictionary = {}) -> Dictionary:
	var coast: Array=[]; var lake: Array=[]; var rings: Array=[]
	var n: int = raster.w*raster.h; var sea := PackedByteArray(); sea.resize(n); var lakes := sea.duplicate(); var land := sea.duplicate()
	for k in range(n): sea[k] = int(raster.water[k]==1); lakes[k] = int(raster.water[k]==2); land[k] = int(raster.water[k]!=1)
	for p in Contours.trace(raster.w,raster.h,sea,func(a,b): return Contours.elevation_cross(raster.elev,a,b)): coast.append(Geometry.points(Array(p)))
	for p in Contours.trace(raster.w,raster.h,lakes): lake.append(Geometry.points(Array(Contours.chaikin(Contours.chaikin(p)))))
	var dist := Fields.distance_to(land,raster.w,raster.h); var quant := PackedInt32Array(); quant.resize(n)
	for k in range(n): quant[k] = mini(65535,roundi(dist[k]*4096))
	for d in [4,9,15]:
		var mask := PackedByteArray(); mask.resize(n); var level: int = d*4096; var lines: Array = []
		for k in range(n): mask[k] = int(quant[k]<level)
		for p in Contours.trace(raster.w,raster.h,mask,func(a,b): return float(level-quant[a])/(quant[b]-quant[a])): lines.append(Geometry.points(Array(Contours.chaikin(p))))
		rings.append(lines)
	var ice := Fields.ice_field(raster) if prepared_ice.is_empty() else prepared_ice; var bytes := PackedByteArray(); bytes.resize(n)
	for k in range(n):
		var conc := maxf(0,(int(ice.near[k])-1)/254.); var fade := 1-(clampf((conc-.02)/.28,0,1)*clampf((conc-.02)/.28,0,1)*(3-2*clampf((conc-.02)/.28,0,1)))
		bytes[k] = roundi(255*fade) if sea[k] and not ice.mask[k] else 0
	return {"coast":coast,"lake":lake,"rings":rings,"chunks":[chunk(lake),chunk(coast),chunk(rings[0]),chunk(rings[1]),chunk(rings[2])],"fade":{"w":raster.w,"h":raster.h,"format":Image.FORMAT_R8,"bytes":bytes}}

func setup(raster: Dictionary,prepared_ice: Dictionary = {},prepared: Dictionary = {}) -> void:
	var plan := prepare(raster,prepared_ice) if prepared.is_empty() else prepared
	coast=plan.coast; lake=plan.lake; rings=plan.rings; chunks=plan.chunks
	var texture := Fields.upload(plan.fade)
	fade_texture = texture
	for i in range(3):
		var node := Ripple.new(); node.show_behind_parent = true; var mat := ShaderMaterial.new(); mat.shader = load("res://assets/atlas/ripple.gdshader"); mat.set_shader_parameter("fade_fields",texture); node.material = mat; add_child(node); ripple_nodes.append(node)
func rebuild() -> void:
	if high_performance:
		update_persistent(); return
	if zoom==last_zoom and last_rect.encloses(visible_world): return
	last_zoom = zoom; last_rect = visible_world.grow(192./maxf(.1,zoom)); render_rect = last_rect
	mesh_build_count += 1
	var gs := pow(zoom/1.35,-.22) if zoom>1.35 else 1.; var aa := .55/zoom
	meshes = [Strokes.build(in_view(chunks[0]),1.05*gs,aa,Geometry2D.END_BUTT),Strokes.build(in_view(chunks[1]),1.45*gs,aa,Geometry2D.END_BUTT) if zoom>1.35 else ArrayMesh.new()]
	for i in range(3):
		ripple_nodes[i].visible = zoom>1.35
		if zoom>1.35: ripple_nodes[i].mesh = Strokes.build(in_view(chunks[i+2]),.55*sqrt(PI)*gs,aa,Geometry2D.END_BUTT); ripple_nodes[i].alpha = .42-i*.12; ripple_nodes[i].queue_redraw()
	queue_redraw()
func _draw() -> void:
	if high_performance: return
	if meshes.is_empty(): return
	for i in range(2):
		if meshes[i].get_surface_count()==0: continue
		for shift in [-2048.,0.,2048.]: draw_set_transform(Vector2(shift,0)); draw_mesh(meshes[i],null,Transform2D.IDENTITY,Color(58/255.,45/255.,34/255.,.65 if i==0 else .9))
	draw_set_transform(Vector2.ZERO)

func update_persistent() -> void:
	if persistent_layers.is_empty():
		for i in range(5):
			var layer := Persistent.new(); layer.scheduler = scheduler; layer.pool = geometry_pool; var source: Array = lake if i==0 else coast if i==1 else rings[i-2]
			layer.set_paths(source); layer.style(1.05 if i==0 else 1.45 if i==1 else .55*sqrt(PI),Color(58/255.,45/255.,34/255.,.65 if i==0 else .9 if i==1 else .42-(i-2)*.12))
			if i>=2: layer.material.set_shader_parameter("ripple",true); layer.material.set_shader_parameter("fade_fields",fade_texture)
			add_child(layer); persistent_layers.append(layer)
		for node in ripple_nodes: node.hide()
		mesh_build_count += 1
	for i in range(persistent_layers.size()):
		persistent_layers[i].visible = i==0 or zoom>1.35
		persistent_layers[i].set_zoom(zoom); persistent_layers[i].set_view(visible_world)
class Ripple extends Node2D:
	var mesh: ArrayMesh
	var alpha: float
	func _draw() -> void:
		if mesh==null or mesh.get_surface_count()==0: return
		for shift in [-2048.,0.,2048.]: draw_set_transform(Vector2(shift,0)); draw_mesh(mesh,null,Transform2D.IDENTITY,Color(58/255.,45/255.,34/255.,alpha))
		draw_set_transform(Vector2.ZERO)
