extends Node2D
## A segment owns only its nearest part of a joined stroke: no alpha accumulation
## at joins. Spatial chunks share cumulative arc distances, including at the seam.
const SHADER = preload("res://assets/atlas/stroke.gdshader")
const CHUNK := 128.
var chunks: Array = []
var build_count := 0
var key := -1
var zoom := 1.
var visible_world := Rect2(-4096,-1024,8192,3072)
var coverage := Rect2()
var pool: Dictionary = {}
var scheduler: Node
var preparing := false
var revision := 0
var asset_key := ""

func _init() -> void:
	material = ShaderMaterial.new(); material.shader = SHADER

static func plan(paths: Array) -> Array:
	var buckets := {}
	for path in paths:
		var arc := 0.; var closed: bool = path.size()>2 and path[0].is_equal_approx(path[-1])
		for i in range(1,path.size()):
			var a: Vector2 = path[i-1]; var b: Vector2 = path[i]; var length := a.distance_to(b)
			if length<.000001: continue
			var before: Vector2 = path[i-2] if i>1 else path[-2] if closed else a
			var after: Vector2 = path[i+1] if i+1<path.size() else path[1] if closed else b
			var cell := Vector2i(floori(fposmod((a.x+b.x)*.5,2048.)/CHUNK),floori((a.y+b.y)*.5/CHUNK))
			if not buckets.has(cell): buckets[cell] = {"vertices":PackedVector2Array(),"uv":PackedVector2Array(),"endpoints":PackedFloat32Array(),"neighbors":PackedFloat32Array(),"indices":PackedInt32Array(),"box":Rect2(a,Vector2.ZERO)}
			var row: Dictionary = buckets[cell]; var base: int = row.vertices.size()
			for corner in range(4):
				row.vertices.append(a if corner<2 else b); row.uv.append(Vector2(arc,corner))
				row.endpoints.append_array(PackedFloat32Array([a.x,a.y,b.x,b.y]))
				row.neighbors.append_array(PackedFloat32Array([before.x,before.y,after.x,after.y]))
			row.indices.append_array(PackedInt32Array([base,base+1,base+2,base+2,base+1,base+3]))
			row.box = row.box.expand(a).expand(b); arc += length
	var out: Array = []; var cells: Array = buckets.keys()
	cells.sort_custom(func(a,b): return a.x<b.x if a.y==b.y else a.y<b.y)
	for cell in cells: out.append(buckets[cell])
	return out

static func resource(row: Dictionary) -> ArrayMesh:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = row.vertices; arrays[Mesh.ARRAY_TEX_UV] = row.uv; arrays[Mesh.ARRAY_INDEX] = row.indices
	arrays[Mesh.ARRAY_CUSTOM0] = row.endpoints; arrays[Mesh.ARRAY_CUSTOM1] = row.neighbors
	var mesh := ArrayMesh.new()
	var flags: int = Mesh.ARRAY_FLAG_USE_2D_VERTICES | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
	# Shader extrusion is absent from the CPU bounds; keep it in the culling box.
	var box: Rect2 = row.box.grow(12.)
	mesh.custom_aabb = AABB(Vector3(box.position.x,box.position.y,-1),Vector3(box.size.x,box.size.y,2))
	return mesh

func set_paths(paths: Array) -> void:
	var value := hash(paths)
	if value==key: return
	if scheduler!=null and not asset_key.is_empty(): scheduler.release_geometry(asset_key)
	key = value; revision += 1; build_count += 1
	if scheduler!=null:
		asset_key = "geometry:%d:%d"%[scheduler.versions.get("geometry",0),value]
		scheduler.geometry_users[asset_key] = int(scheduler.geometry_users.get(asset_key,0))+1
	if pool.has(value):
		chunks = pool[value]; preparing = false; coverage = Rect2(); queue_redraw(); return
	if scheduler!=null:
		if scheduler.cache.has(asset_key):
			chunks = scheduler.touch(asset_key); scheduler.cache[asset_key].pinned = true; pool[value] = chunks; preparing = false; coverage = Rect2(); queue_redraw(); return
		preparing = true
		var generation := revision; var input := paths.duplicate(); var owner := self
		var publish := func(uploaded):
			if not is_instance_valid(owner) or owner.revision!=generation: return
			owner.pool[value] = uploaded; owner.chunks = uploaded; owner.preparing = false; owner.coverage = Rect2(); owner.queue_redraw()
		if scheduler.geometry_pending.has(asset_key): scheduler.geometry_pending[asset_key].append(publish); return
		scheduler.geometry_pending[asset_key] = [publish]
		var name_value := asset_key; var service := scheduler
		scheduler.submit("geometry",func(): return plan(input),func(rows):
			var uploaded: Array = []
			var bytes := 0
			for row in rows:
				var source: Dictionary = row
				bytes += source.vertices.size()*96+source.indices.size()*8 # CPU + GPU buffers.
				service.enqueue(func(): uploaded.append({"mesh":resource(source),"box":source.box}),-1,"geometry")
			service.enqueue(func():
				service.remember(name_value,uploaded,bytes,int(service.geometry_users.get(name_value,0))>0)
				for listener in service.geometry_pending.get(name_value,[]): listener.call(uploaded)
				service.geometry_pending.erase(name_value),-1,"geometry"),-1)
		return
	chunks.clear()
	for row in plan(paths): chunks.append({"mesh":resource(row),"box":row.box})
	pool[value] = chunks; coverage = Rect2(); queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(scheduler) and not asset_key.is_empty(): scheduler.release_geometry(asset_key)

func style(width: float,color: Color,dash: float = 0.,gap: float = 0.,exponent: float = -.22,vary: bool = false) -> void:
	material.set_shader_parameter("stroke_width",width); material.set_shader_parameter("stroke_color",color)
	material.set_shader_parameter("dash_length",dash); material.set_shader_parameter("gap_length",gap)
	material.set_shader_parameter("width_exponent",exponent); material.set_shader_parameter("vary_pen",vary)

func set_zoom(value: float) -> void:
	zoom = value; material.set_shader_parameter("view_zoom",value)

func set_view(rect: Rect2) -> void:
	visible_world = rect
	if coverage.encloses(rect): return
	coverage = rect.grow(192./maxf(.1,zoom)); queue_redraw()

func _draw() -> void:
	for row in chunks:
		for shift in [-2048.,0.,2048.]:
			if not coverage.has_area() or coverage.intersects(Rect2(row.box.position+Vector2(shift,0),row.box.size).grow(12.),true):
				draw_set_transform(Vector2(shift,0)); draw_mesh(row.mesh,null)
	draw_set_transform(Vector2.ZERO)
