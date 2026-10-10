extends Node
## Frozen native symbol tiles; only the visible-tile compositors follow the camera.
const Symbols = preload("res://scripts/atlas/symbols.gd")
const Index = preload("res://scripts/atlas/render_index.gd")
const Scheduler = preload("res://scripts/atlas/render_scheduler.gd")
const SymbolState = preload("res://scripts/atlas/symbol_state.gd")
const SymbolMesh = preload("res://scripts/atlas/symbol_mesh.gd")
const TileTexture = preload("res://scripts/atlas/tile_texture.gd")
const TILE := 512.
class Canvas extends Node2D:
	var rows: Array = []
	func _draw() -> void:
		for row in rows: draw_texture_rect_region(row.texture,row.rect,row.region,Color.WHITE,false)
class Batch extends Node2D:
	var mesh: ArrayMesh
	func _draw():
		if mesh.get_surface_count()>0: draw_mesh(mesh,null)
var scheduler: Node
var output: SubViewport
var data: Dictionary
var display: Dictionary
var forest_index := Index.new()
var glyph_index := Index.new()
var forest_ids := PackedInt32Array()
var groups: Array = []
var blend_material: ShaderMaterial
var overview: Dictionary = {}
var entries := {}
var requests := {}
var visible_keys := {}
var max_radius := 0.
var world_version := 0
var current_lod := -1
var target_lod := -1
var active_group := 0
var blending := false
var blend_elapsed := 0.
var transition_lod := -1
var view_rect := Rect2(0,0,2048,1024)
var origin := Vector2.ZERO
var zoom := 1.
var tile_build_count := 0
var tile_hits := 0
var tile_render_max_usec := 0

func setup(map_data: Dictionary,plan: Dictionary,service: Node,target: SubViewport) -> void:
	data = map_data; display = plan; scheduler = service; output = target; world_version += 1
	for i in range(display.forest.size()):
		if display.forest[i]==0: continue
		forest_ids.append(i); forest_index.add(Rect2(Vector2(data.mesh.x[i],data.mesh.y[i])-Vector2.ONE*data.mesh.spacing*3,Vector2.ONE*data.mesh.spacing*6))
	max_radius = data.mesh.spacing*3
	for glyph in display.glyphs:
		var r: float = glyph.s*2.; max_radius = maxf(max_radius,r)
		glyph_index.add(Rect2(Vector2(glyph.x,glyph.y)-Vector2.ONE*r,Vector2.ONE*r*2))
	for i in range(2):
		var view := SubViewport.new(); view.disable_3d = true; view.transparent_bg = true; view.size = output.size
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
		var canvas := Canvas.new(); view.add_child(canvas); groups.append({"view":view,"canvas":canvas,"keys":[]})
	var sprite := Sprite2D.new(); sprite.centered = false; sprite.texture = groups[0].view.get_texture()
	blend_material = ShaderMaterial.new(); blend_material.shader = preload("res://assets/atlas/tile_blend.gdshader")
	blend_material.set_shader_parameter("older",groups[0].view.get_texture()); blend_material.set_shader_parameter("newer",groups[1].view.get_texture())
	sprite.material = blend_material; output.add_child(sprite)
	request("overview",Rect2(0,0,2048,1024),.5,true,-10)

func tile_key(lod: int,x: int,y: int) -> String:
	return "symbols:%d:%d:%d:%d"%[world_version,lod,x,y]

func request(key: String,rect: Rect2,detail: float,pinned: bool,priority: int) -> void:
	if entries.has(key) or requests.has(key): return
	requests[key] = true
	var gs := pow(maxf(1.,detail/1.35),-.22)
	var local_radius: float = data.mesh.spacing*3
	for id in glyph_index.query(rect.grow(32./detail)):
		local_radius = maxf(local_radius,display.glyphs[id].s*2.)
	var pad := maxi(32,ceili(local_radius*gs*detail+data.mesh.spacing*.42*detail+4))
	var visible := rect.grow(float(pad)/detail)
	var cells := PackedInt32Array()
	for id in forest_index.query(visible): cells.append(forest_ids[id])
	var glyphs: Array = []
	for id in glyph_index.query(visible): glyphs.append(display.glyphs[id])
	var input := {"data":{"seed":data.seed,"mesh":data.mesh,"environment":data.environment},"glyphs":glyphs,"forest":display.forest,"cells":cells,"detail":detail,"rect":visible}
	scheduler.submit("symbols",func(): return SymbolState.tile(input),func(geometry):
		if not is_inside_tree(): return
		create_tile(key,rect,detail,pinned,geometry,pad),priority,key)

func create_tile(key: String,rect: Rect2,detail: float,pinned: bool,geometry: Dictionary,pad: int) -> void:
	var start := Time.get_ticks_usec()
	var gs := pow(maxf(1.,detail/1.35),-.22)
	var pixels := Vector2i(ceili(rect.size.x*detail),ceili(rect.size.y*detail))
	var size_value := pixels+Vector2i.ONE*pad*2
	var view_origin := Vector2.ONE*pad-rect.position*detail
	var forest := SubViewport.new(); forest.size = size_value; forest.disable_3d = true; forest.transparent_bg = true; forest.render_target_update_mode = SubViewport.UPDATE_DISABLED; add_child(forest)
	var canopy := Batch.new(); canopy.mesh = ArrayMesh.new(); canopy.scale = Vector2.ONE*detail; canopy.position = view_origin; forest.add_child(canopy)
	var symbols := SubViewport.new(); symbols.size = size_value; symbols.disable_3d = true; symbols.transparent_bg = true; symbols.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if RenderingServer.get_current_rendering_method()!="gl_compatibility": symbols.msaa_2d = Viewport.MSAA_4X
	add_child(symbols)
	var background := Sprite2D.new(); background.centered = false; background.texture = forest.get_texture()
	var mat := ShaderMaterial.new(); mat.shader = preload("res://assets/atlas/forest.gdshader")
	mat.set_shader_parameter("shade_distance",data.mesh.spacing*.42*gs*detail); mat.set_shader_parameter("glyph_scale",gs)
	mat.set_shader_parameter("view_scale",detail); mat.set_shader_parameter("view_origin",view_origin); background.material = mat; symbols.add_child(background)
	var crowns := Batch.new(); crowns.mesh = ArrayMesh.new(); crowns.scale = Vector2.ONE*detail; crowns.position = view_origin
	var clip := ShaderMaterial.new(); clip.shader = preload("res://assets/atlas/crown_clip.gdshader")
	clip.set_shader_parameter("canopy_mask",forest.get_texture()); clip.set_shader_parameter("view_origin",view_origin); clip.set_shader_parameter("view_scale",detail); crowns.material = clip; symbols.add_child(crowns)
	var mountains := Batch.new(); mountains.mesh = ArrayMesh.new(); mountains.scale = Vector2.ONE*detail; mountains.position = view_origin; symbols.add_child(mountains)
	var bytes: int = size_value.x*size_value.y*4*(5 if symbols.msaa_2d!=Viewport.MSAA_DISABLED else 1)
	var row := {"rect":rect,"detail":detail,"pad":pad,"pixels":pixels,"region_size":rect.size*detail,"forest":forest,"view":symbols,"texture":symbols.get_texture(),"ready_frame":9223372036854775807,"registered":false,"copying":false,"bytes":bytes,"pinned":pinned}
	entries[key] = row
	var nodes := [canopy,crowns,mountains]; var kinds := ["forest","crowns","glyphs"]
	for i in range(3):
		var mesh: ArrayMesh = nodes[i].mesh
		for part in geometry[kinds[i]].get("parts",[geometry[kinds[i]]]):
			var buffer: Dictionary = part
			scheduler.enqueue(func(): SymbolMesh.append(mesh,buffer),0,"symbols")
	scheduler.enqueue(func():
		for node in nodes: node.queue_redraw()
		forest.render_target_update_mode = SubViewport.UPDATE_ONCE; symbols.render_target_update_mode = SubViewport.UPDATE_ONCE
		row.ready_frame = Engine.get_process_frames()+2,0,"symbols")
	tile_build_count += 1; tile_render_max_usec = maxi(tile_render_max_usec,Time.get_ticks_usec()-start)

func set_camera(position_value: Vector2,zoom_value: float,viewport_size: Vector2) -> void:
	origin = position_value; zoom = zoom_value; view_rect = Rect2(-origin/zoom,viewport_size/zoom)
	var next := Scheduler.choose_lod(zoom,target_lod)
	if next!=target_lod: target_lod = next
	for group in groups:
		group.view.size = output.size
		group.canvas.position = origin; group.canvas.scale = Vector2.ONE*zoom
	update_groups()

func keys_for(lod: int,margin: int = 0,priority: int = -1) -> Array:
	var out: Array = []; var detail: float = Scheduler.LODS[lod]; var step := TILE/detail
	var ny := ceili(1024./step); var nx := ceili(2048./step)
	for shift in [-2048.,0.,2048.]:
		var rect := Rect2(view_rect.position+Vector2(shift,0),view_rect.size)
		for y in range(maxi(0,floori(rect.position.y/step)-margin),mini(ny,ceili(rect.end.y/step)+margin)):
			for x in range(maxi(0,floori(rect.position.x/step)-margin),mini(nx,ceili(rect.end.x/step)+margin)):
				var key := tile_key(lod,x,y)
				if out.has(key): continue
				out.append(key)
				var tile := Rect2(Vector2(x,y)*step,Vector2(minf(step,2048.-x*step),minf(step,1024.-y*step)))
				request(key,tile,detail,false,priority if priority>=0 else 0 if margin==0 else 5)
	return out

func _process(delta: float) -> void:
	if groups.is_empty(): return
	for key in entries.keys():
		var row: Dictionary = entries[key]
		if not row.registered and not row.copying and Engine.get_process_frames()>=row.ready_frame:
			row.copying = true
			var owner := self; var name_value: String = key; var source: Dictionary = row
			TileTexture.copy(row.texture,Rect2i(Vector2i.ONE*(row.pad-1),row.pixels+Vector2i.ONE*2),func(texture,copied):
				if not is_instance_valid(owner): return
				source.registered = true; source.texture = texture; owner.requests.erase(name_value)
				if copied:
					source.pad = 1; source.bytes = (source.pixels.x+2)*(source.pixels.y+2)*4
					source.view.queue_free(); source.view = null
				else:
					source.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
					for child in source.view.get_children(): child.queue_free()
				source.forest.queue_free(); source.forest = null
				owner.scheduler.remember(name_value,source,source.bytes,source.pinned or owner.visible_keys.has(name_value))
				if name_value=="overview": owner.overview = source)
		elif row.registered and not scheduler.cache.has(key):
			if is_instance_valid(row.view): row.view.queue_free()
			entries.erase(key)
	update_groups()
	if blending:
		blend_elapsed += delta; blend_material.set_shader_parameter("blend",minf(1.,blend_elapsed/.12))
		if blend_elapsed>=.12:
			blending = false; active_group = 1-active_group; current_lod = transition_lod
			blend_material.set_shader_parameter("older",groups[active_group].view.get_texture()); blend_material.set_shader_parameter("newer",groups[1-active_group].view.get_texture()); blend_material.set_shader_parameter("blend",0.)
			clear_group(1-active_group)

func update_groups() -> void:
	if target_lod<0 or overview.is_empty(): return
	visible_keys.clear()
	var target_keys := keys_for(target_lod); var complete := target_keys.all(func(key): return entries.has(key) and entries[key].registered)
	if current_lod<0: current_lod = target_lod
	var active_keys := keys_for(current_lod)
	for key in target_keys+active_keys: visible_keys[key] = true
	if blending:
		for key in keys_for(transition_lod): visible_keys[key] = true
	for key in scheduler.cache:
		if key.begins_with("symbols:"): scheduler.cache[key].pinned = visible_keys.has(key)
	scheduler.trim()
	set_rows(active_group,active_keys)
	if target_lod!=current_lod and not blending:
		set_rows(1-active_group,target_keys)
		if complete:
			blending = true; transition_lod = target_lod; blend_elapsed = 0.
			blend_material.set_shader_parameter("older",groups[active_group].view.get_texture()); blend_material.set_shader_parameter("newer",groups[1-active_group].view.get_texture())
	# Peripheral tiles are requested after the entire current view is ready.
	var wanted := visible_keys.duplicate(); wanted.overview = true
	if complete and not blending:
		for key in keys_for(target_lod,1): wanted[key] = true
		for neighbor in [target_lod-1,target_lod+1]:
			if neighbor>=0 and neighbor<Scheduler.LODS.size():
				for key in keys_for(neighbor,0,8): wanted[key] = true
	for key in scheduler.cancel_queued("symbols",wanted): requests.erase(key)
	if current_lod==target_lod and not blending: clear_group(1-active_group)
	groups[active_group].view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	groups[1-active_group].view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if blending else SubViewport.UPDATE_DISABLED

func set_rows(group_index: int,keys: Array) -> void:
	var rows: Array = []; var stamp: Array = []
	for key in keys:
		var ready: bool = entries.has(key) and entries[key].registered
		var row: Dictionary = entries[key] if ready else {}
		var parts: PackedStringArray = key.split(":"); var detail: float = Scheduler.LODS[int(parts[2])]; var step := TILE/detail
		var rect := Rect2(Vector2(int(parts[3]),int(parts[4]))*step,Vector2.ZERO)
		rect.size = Vector2(minf(step,2048.-rect.position.x),minf(step,1024.-rect.position.y))
		var texture: Texture2D = row.texture if ready else overview.texture
		var region := Rect2(Vector2.ONE*row.pad,row.region_size) if ready else Rect2(Vector2.ONE*overview.pad+rect.position*.5,rect.size*.5)
		stamp.append([key,ready,texture.get_instance_id()])
		if ready: scheduler.touch(key); tile_hits += 1
		for shift in [-2048.,0.,2048.]: rows.append({"texture":texture,"region":region,"rect":Rect2(rect.position+Vector2(shift,0),rect.size)})
	if groups[group_index].keys==stamp: return
	groups[group_index].keys = stamp; groups[group_index].canvas.rows = rows; groups[group_index].canvas.queue_redraw()

func clear_group(group_index: int) -> void:
	if groups[group_index].keys.is_empty(): return
	groups[group_index].keys.clear(); groups[group_index].canvas.rows.clear(); groups[group_index].canvas.queue_redraw()

func is_ready() -> bool:
	if target_lod<0 or overview.is_empty() or blending: return false
	for key in keys_for(target_lod):
		if not entries.has(key) or not entries[key].registered: return false
	return true

func _exit_tree() -> void:
	if is_instance_valid(scheduler):
		scheduler.invalidate("symbols")
		for key in entries: scheduler.forget(key)
