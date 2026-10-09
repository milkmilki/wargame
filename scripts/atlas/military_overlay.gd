extends Node2D
var state: GameState
var show_traffic := false
var selection := -1
var state_lines: Array = []
var district_lines: Array = []
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
	var pen := 1./maxf(.1,global_scale.x)
	for shift in [-2048.,0.,2048.]:
		draw_set_transform(Vector2(shift,0.))
		for path in state_lines:
			if path.size()>=2: draw_polyline(path,Color(.30,.17,.09,.42),.75*pen,true)
		if global_scale.x>=1.5:
			for path in district_lines:
				if path.size()>=2: draw_polyline(path,Color(.35,.23,.15,.20),.45*pen,true)
		if show_traffic:
			for city in state.cities:
				if city.is_traffic: draw_circle(city.map_position*Vector2(2048,1024),2.5*pen,Color(.25,.15,.1,.7))
	draw_set_transform(Vector2.ZERO)

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
