extends Node2D
const Strokes = preload("res://scripts/atlas/ink_strokes.gd")
const VisibleLines = preload("res://scripts/atlas/visible_lines.gd")
const Persistent = preload("res://scripts/atlas/persistent_strokes.gd")
const BattleBar = preload("res://scripts/atlas/battle_strength_bar.gd")
const BattleInformation = preload("res://scripts/atlas/battle_information.gd")
const MarkerState = preload("res://scripts/atlas/military_marker_state.gd")
var marker_state := MarkerState.new()
var high_performance := false
var persistent_layers: Array = []
var persistent_key: Array = []
var scheduler: Node
var geometry_pool := {}
var state: GameState
var show_traffic := false
var selection := -1
var state_lines: Array = []
var district_lines: Array = []
var view_zoom := -1.
var static_key: Array = []
var static_meshes: Array = []
var static_build_count := 0
var visible_world := Rect2(0,0,2048,1024)
var cached_world := Rect2()
var line_index: Array = []
var line_key: Array = []

func set_view_zoom(value: float) -> void:
	if is_equal_approx(value,view_zoom): return
	view_zoom = value; queue_redraw()

func set_view(value: float,rect: Rect2) -> void:
	set_view_zoom(value); visible_world = rect
	if high_performance:
		if persistent_layers.is_empty(): update_persistent()
		else:
			for i in range(persistent_layers.size()):
				persistent_layers[i].set_zoom(value); persistent_layers[i].set_view(rect); persistent_layers[i].visible = i==0 or value>=1.5
		return
	if not cached_world.encloses(rect): queue_redraw()

func prepare_static() -> void:
	var value := maxf(.1,global_scale.x)
	var key := [hash(state_lines),hash(district_lines),value]
	if key==static_key and cached_world.encloses(visible_world): return
	var sources := [key[0],key[1]]
	if sources!=line_key:
		line_key = sources
		line_index = [VisibleLines.index(state_lines),VisibleLines.index(district_lines)]
	cached_world = visible_world.grow(192./value)
	static_key = key; static_build_count += 1
	static_meshes = [Strokes.build(VisibleLines.select(line_index[0],cached_world),.75/value,.55/value,Geometry2D.END_BUTT)]
	static_meshes.append(Strokes.build(VisibleLines.select(line_index[1],cached_world),.45/value,.55/value,Geometry2D.END_BUTT) if value>=1.5 else ArrayMesh.new())
class Markers extends Node2D:
	var mesh: MultiMesh
	func _draw() -> void:
		if mesh!=null and mesh.visible_instance_count>0: draw_multimesh(mesh,null)
class Inspection extends Node2D:
	func _draw() -> void: draw_arc(Vector2.ZERO,8.,0.,TAU,24,Color(1.,.85,.2),2.,true)
class CombatMarker extends Node2D:
	var row := {}
	func _draw() -> void:
		draw_line(Vector2(-5,-5),Vector2(5,5),Color(.8,.08,.04),3.,true)
		draw_line(Vector2(-5,5),Vector2(5,-5),Color(.8,.08,.04),3.,true)
		if not row.is_empty(): BattleBar.draw(self,Vector2.ZERO,1.,row)
var markers: Node2D
var battle_markers: Node2D
var selection_marker: Node2D
var army_mesh: MultiMesh
var army_build_count := 0
var battle_build_count := 0
var army_stamp := -1
var battle_stamp := -1
var army_rows: Array = []
var combat_rows: Array = []
var army_coverage := Rect2()
var battle_nodes := {}
var inspection_nodes: Array = []
var marker_positions := {}
var army_buffer := PackedFloat32Array()
var marker_stamp := -1
var marker_redraw_count := 0
func _ready() -> void:
	markers = Markers.new()
	army_mesh = MultiMesh.new(); army_mesh.transform_format = MultiMesh.TRANSFORM_2D; army_mesh.use_colors = true
	var quad := QuadMesh.new(); quad.size = Vector2.ONE*12.; army_mesh.mesh = quad; army_mesh.visible_instance_count = 0
	markers.mesh = army_mesh
	var ink := ShaderMaterial.new(); ink.shader = preload("res://assets/atlas/army_instances.gdshader"); markers.material = ink
	# Absolute map layer above fronts (8), labels and trade hubs (9).
	# Keep camera transforms inherited; only drawing order is independent.
	markers.z_as_relative = false; markers.z_index = 10; add_child(markers)
	battle_markers = Node2D.new(); battle_markers.z_as_relative = false; battle_markers.z_index = 11; add_child(battle_markers)
	selection_marker = Node2D.new(); selection_marker.z_as_relative = false; selection_marker.z_index = 12; add_child(selection_marker)
func _process(_delta: float) -> void:
	if markers==null or state==null: return
	# Army motion advances with the simulation. Keep the recorded CanvasItem
	# commands between changes instead of rebuilding hundreds of circles/paths.
	var army_keys: Array = []
	for army in state.armies:
		army_keys.append([army.id,army.size>0,army.owner_nation,army.on_edge,army.location_city,army.move_from,army.move_to,army.move_progress])
	var battle_keys: Array = []
	for battle in state.battles:
		battle_keys.append([battle.id,battle.finished,battle.traffic_node_id,battle.city.id if battle.city!=null else -1,battle.edge.get_instance_id() if battle.edge!=null else 0,battle.contact_dist_a,battle.contact_dist_b,battle_strength(battle).counts,battle.kind,battle.side_b_defends_city])
	var color_key := state.nations.map(func(nation): return nation.color)
	var stamp := hash([state.get_instance_id(),state.road_network_revision,selection,global_scale.x,army_keys,battle_keys,color_key])
	if stamp!=marker_stamp: marker_stamp=stamp; marker_redraw_count+=1
	var armies := hash([state.get_instance_id(),state.road_network_revision,army_keys,color_key])
	if armies!=army_stamp:
		army_stamp=armies; army_rows.clear(); marker_positions.clear(); army_coverage=Rect2()
		for army in state.armies:
			if army.size<=0: continue
			var point := army_position(army)
			army_rows.append({"id":army.id,"point":point,"color":state.nations[army.owner_nation].color}); marker_positions[army.id]=point
	var battles := hash([state.get_instance_id(),state.road_network_revision,battle_keys])
	if battles!=battle_stamp:
		battle_stamp=battles; combat_rows.clear()
		for battle in state.battles:
			if not battle.finished: combat_rows.append({"id":battle.id,"point":battle_position(battle),"row":battle_strength(battle)})
	update_marker_layers()

func update_marker_layers() -> void:
	if markers==null: return
	var value := maxf(.1,global_scale.x)
	markers.material.set_shader_parameter("view_zoom",value)
	if not army_coverage.encloses(visible_world):
		army_coverage=visible_world.grow(96./value)
		var buffer := PackedFloat32Array(); var box := Rect2()
		for row in army_rows:
			for point in MarkerState.visible_copies(row.point,army_coverage,6./value):
				buffer.append_array(PackedFloat32Array([1.,0.,0.,point.x,0.,1.,0.,point.y,row.color.r,row.color.g,row.color.b,1.]))
				box = Rect2(point,Vector2.ONE*.001) if not box.has_area() else box.expand(point)
		if buffer!=army_buffer:
			army_buffer=buffer; army_build_count+=1
			army_mesh.instance_count=buffer.size()/12; army_mesh.visible_instance_count=army_mesh.instance_count
			if not buffer.is_empty(): army_mesh.buffer=buffer; army_mesh.custom_aabb=AABB(Vector3(box.position.x-60.,box.position.y-60.,-1.),Vector3(box.size.x+120.,box.size.y+120.,2.))
			markers.queue_redraw()
	var visible := {}
	for combat in combat_rows:
		for point in MarkerState.visible_copies(combat.point,visible_world,170./value):
			var key := "%d:%d"%[combat.id,roundi((point.x-fposmod(combat.point.x,2048.))/2048.)]
			visible[key]=true
			if not battle_nodes.has(key):
				var node := CombatMarker.new(); battle_markers.add_child(node); battle_nodes[key]=node
			var node: Node2D = battle_nodes[key]
			if node.row!=combat.row: node.row=combat.row; node.queue_redraw(); battle_build_count+=1
			node.position=point; node.scale=Vector2.ONE/value
	for key in battle_nodes.keys():
		if not visible.has(key): battle_nodes[key].queue_free(); battle_nodes.erase(key)
	var selected: Array = MarkerState.visible_copies(marker_positions[selection],visible_world,10./value) if marker_positions.has(selection) else []
	while inspection_nodes.size()<selected.size():
		var node := Inspection.new(); selection_marker.add_child(node); inspection_nodes.append(node)
	for i in range(inspection_nodes.size()):
		var node: Node2D = inspection_nodes[i]; node.visible=i<selected.size()
		if node.visible: node.position=selected[i]; node.scale=Vector2.ONE/value
func battle_strength(battle: Battle) -> Dictionary:
	return BattleBar.summary(battle)
func battle_position(battle: Battle) -> Vector2:
	return BattleInformation.position(state,battle)
func battle_at(point: Vector2) -> int:
	if state==null: return -1
	var pen:=1./maxf(.1,global_scale.x); var best:=INF; var selected: int=-1
	for battle in state.battles:
		if battle.finished: continue
		var row:=battle_strength(battle)
		if row.total<=0: continue
		var anchor:=battle_position(battle)
		anchor.x+=roundf((point.x-anchor.x)/2048.)*2048.
		var rect:=BattleBar.hit_rect(anchor,pen,row)
		var distance:=point.distance_squared_to(rect.get_center())
		if rect.has_point(point) and distance<best: best=distance; selected=battle.id
	return selected
func army_position(army: Army) -> Vector2:
	return marker_state.position(state,army)
func _draw() -> void:
	if state==null: return
	if high_performance: update_persistent()
	else: prepare_static()
	var pen := 1./maxf(.1,global_scale.x)
	for shift in [-2048.,0.,2048.]:
		draw_set_transform(Vector2(shift,0.))
		for i in range(0 if high_performance else static_meshes.size()):
			if static_meshes[i].get_surface_count()>0:
				draw_mesh(static_meshes[i],null,Transform2D.IDENTITY,Color(.30,.17,.09,.42) if i==0 else Color(.35,.23,.15,.20))
		if show_traffic:
			for city in state.cities:
				if city.is_traffic: draw_circle(city.map_position*Vector2(2048,1024),2.5*pen,Color(.25,.15,.1,.7))
	draw_set_transform(Vector2.ZERO)

func update_persistent() -> void:
	var sources := [hash(state_lines),hash(district_lines)]
	if sources!=persistent_key:
		persistent_key = sources
		for layer in persistent_layers: layer.queue_free()
		persistent_layers.clear(); static_build_count += 1
		for i in range(2):
			var layer := Persistent.new(); layer.scheduler = scheduler; layer.pool = geometry_pool; layer.set_paths(state_lines if i==0 else district_lines)
			layer.style(.75 if i==0 else .45,Color(.30,.17,.09,.42) if i==0 else Color(.35,.23,.15,.20),0,0,-1.)
			add_child(layer); persistent_layers.append(layer)
	for i in range(persistent_layers.size()):
		persistent_layers[i].set_zoom(view_zoom); persistent_layers[i].set_view(visible_world); persistent_layers[i].visible = i==0 or view_zoom>=1.5
