extends Node2D
const Strokes = preload("res://scripts/atlas/ink_strokes.gd")
const VisibleLines = preload("res://scripts/atlas/visible_lines.gd")
const Persistent = preload("res://scripts/atlas/persistent_strokes.gd")
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
	var host: Node2D
	func _draw() -> void: host.draw_markers(self)
var markers: Node2D
func _ready() -> void:
	markers = Markers.new(); markers.host = self; markers.z_index = 2; add_child(markers)
func _process(_delta: float) -> void:
	if markers!=null: markers.queue_redraw()
func army_position(army: Army) -> Vector2:
	if army.on_edge and army.move_from>=0 and army.move_to>=0:
		var edge := state.edge_of(army.move_from,army.move_to)
		if edge!=null:
			return edge.map_position_at(army.move_progress if army.move_from==edge.city_a else 1.-army.move_progress,state.cities[edge.city_a].map_position,state.cities[edge.city_b].map_position,2.)*Vector2(2048,1024)
	return state.cities[maxi(0,army.location_city)].map_position*Vector2(2048,1024)
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

func draw_markers(canvas: Node2D) -> void:
	if state==null: return
	var pen := 1./maxf(.1,global_scale.x)
	for shift in [-2048.,0.,2048.]:
		canvas.draw_set_transform(Vector2(shift,0.))
		for army in state.armies:
			if army.size<=0: continue
			var point := army_position(army); point.x = fposmod(point.x,2048.)
			var color := state.nations[army.owner_nation].color
			canvas.draw_circle(point,5.5*pen,Color(.13,.07,.04)); canvas.draw_circle(point,3.8*pen,color)
			if army.id==selection: canvas.draw_arc(point,8.*pen,0.,TAU,24,Color(1.,.85,.2),2.*pen,true)
		for battle in state.battles:
			if battle.finished: continue
			var point := Vector2.ZERO
			if battle.traffic_node_id>=0: point = state.cities[battle.traffic_node_id].map_position*Vector2(2048,1024)
			elif battle.city!=null: point = battle.city.map_position*Vector2(2048,1024)
			elif battle.edge!=null: point = battle.edge.map_position_at((battle.contact_dist_a+battle.contact_dist_b)*.5/maxf(.000001,battle.edge.distance_units()),state.cities[battle.edge.city_a].map_position,state.cities[battle.edge.city_b].map_position,2.)*Vector2(2048,1024)
			point.x = fposmod(point.x,2048.); canvas.draw_line(point-Vector2(5,5)*pen,point+Vector2(5,5)*pen,Color(.8,.08,.04),3.*pen,true); canvas.draw_line(point+Vector2(-5,5)*pen,point+Vector2(5,-5)*pen,Color(.8,.08,.04),3.*pen,true)
	canvas.draw_set_transform(Vector2.ZERO)
