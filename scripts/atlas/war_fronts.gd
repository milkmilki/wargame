extends Node2D
## AGPL-3.0-only. Port of civ-atlas 103afd3 render/civ/warfare.ts:
## warFront, frontTeeth, strokeFront and fantasy WAR_SIZE/warLook.
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Strokes = preload("res://scripts/atlas/ink_strokes.gd")
const Persistent = preload("res://scripts/atlas/persistent_strokes.gd")
var high_performance := false
var persistent_layers: Array = []
var persistent_version := -1
var scheduler: Node
var geometry_pool := {}
const RED := Color(168./255.,38./255.,26./255.,.95)
const PAPER := Color(250./255.,242./255.,222./255.,.85)
const LINE_GROW := 0.6309297535714574 # log(2) / log(3)
const FRONT_PAPER := 8.4
const FRONT_WIDTH := 3.6
const TOOTH_STEP := 6.5
const TOOTH_LENGTH := 3.45
const TOOTH_PAPER := 5.4
const TOOTH_WIDTH := 1.95
var fronts: Array = []
var normal_borders: Array = []
var classification_count := 0
var view_zoom := 1.0
var classification_key: Array = []
var mesh_key: Array = []
var meshes: Array = []

static func roles(state: GameState) -> Dictionary:
	var out := {}
	for id in state.war_chronicle_contexts:
		var context: Dictionary = state.war_chronicle_contexts[id]
		out[id] = {"actors":context.actor_ids,"targets":context.target_ids}
	return out

static func state_key(state: GameState) -> Array:
	var alive := PackedByteArray()
	for nation in state.nations: alive.append(1 if nation.alive else 0)
	return [state.get_instance_id(),state.ownership_revision,state.diplomacy_revision,hash(state.war_objectives),hash(roles(state)),alive]

static func defender_of(state: GameState,left: int,right: int) -> int:
	var sides: Dictionary = roles(state).get(state.war_id_between(left,right),{})
	if not sides.is_empty():
		if sides.targets.has(right) and sides.actors.has(left): return right
		if sides.targets.has(left) and sides.actors.has(right): return left
	var objective := state.war_objective(left,right)
	var defender := int(objective.get("defender",-1))
	# Direct hostility (e.g. a rebellion) can exist without a declaration record.
	return defender if defender in [left,right] else maxi(left,right)

func configure(borders: Array,state: GameState) -> void:
	var key := state_key(state) + [hash(borders)]
	if key == classification_key: return
	classification_key = key; classification_count += 1
	fronts.clear(); normal_borders.clear(); mesh_key.clear()
	for border in borders:
		var left := int(border.left); var right := int(border.right)
		if (left<0 or right<0 or left==right
			or left>=state.nations.size() or right>=state.nations.size()
			or not state.nations[left].alive or not state.nations[right].alive
			or not state.is_enemy(left,right)):
			normal_borders.append(border); continue
		var defender := defender_of(state,left,right)
		var path := Geometry.points(border.pts)
		# Border side labels use y-up; canvas-left (dy,-dx) is the right label.
		if defender == left: path.reverse()
		fronts.append({"path":path,"defender":defender,"closed":border.closed})
	queue_redraw()

static func unit(zoom_value: float) -> float:
	return pow(maxf(1.,zoom_value),LINE_GROW-1.)

static func teeth(path: PackedVector2Array,step: float,length: float) -> Array:
	var out: Array = []
	if step<=0: return out
	var acc := step*.5
	for index in range(1,path.size()):
		var delta := path[index]-path[index-1]; var distance := delta.length()
		if distance<=0: continue
		var normal := Vector2(delta.y,-delta.x)/distance*length
		while acc<=distance:
			var point := path[index-1]+delta*(acc/distance)
			out.append(PackedVector2Array([point,point+normal])); acc += step
		acc -= distance
	return out

func set_view_zoom(value: float) -> void:
	if is_equal_approx(view_zoom,value): return
	view_zoom = value; queue_redraw()
	if high_performance: update_persistent()

func prepare_meshes() -> void:
	var key := [classification_count,view_zoom]
	if key == mesh_key: return
	mesh_key = key; meshes.clear()
	var paths: Array = []; var ticks: Array = []; var u := unit(view_zoom)
	for front in fronts:
		paths.append(front.path); ticks.append_array(teeth(front.path,TOOTH_STEP,TOOTH_LENGTH*u))
	var aa := .55/maxf(.01,view_zoom)
	for record in [[paths,FRONT_PAPER*u],[paths,FRONT_WIDTH*u],[ticks,TOOTH_PAPER*u],[ticks,TOOTH_WIDTH*u]]:
		meshes.append(Strokes.build(record[0],record[1],aa))

func _draw() -> void:
	if high_performance: update_persistent(); return
	if fronts.is_empty(): return
	prepare_meshes()
	for index in range(meshes.size()):
		if meshes[index].get_surface_count()==0: continue
		for shift in [-2048.,0.,2048.]:
			draw_set_transform(Vector2(shift,0))
			draw_mesh(meshes[index],null,Transform2D.IDENTITY,PAPER if index%2==0 else RED)
	draw_set_transform(Vector2.ZERO)

func update_persistent() -> void:
	if persistent_version!=classification_count:
		persistent_version = classification_count
		for layer in persistent_layers: layer.queue_free()
		persistent_layers.clear()
		var paths: Array = []; var ticks: Array = []
		for front in fronts: paths.append(front.path); ticks.append_array(teeth(front.path,TOOTH_STEP,TOOTH_LENGTH))
		for i in range(4):
			var layer := Persistent.new(); layer.scheduler = scheduler; layer.pool = geometry_pool; layer.set_paths(paths if i<2 else ticks)
			layer.style([FRONT_PAPER,FRONT_WIDTH,TOOTH_PAPER,TOOTH_WIDTH][i],PAPER if i%2==0 else RED,0,0,LINE_GROW-1.)
			layer.material.set_shader_parameter("scale_origin",1.)
			if i>=2: layer.material.set_shader_parameter("path_scale_exponent",LINE_GROW-1.)
			add_child(layer); persistent_layers.append(layer)
		var used := {}
		for layer in persistent_layers: used[layer.key] = true
		for key in geometry_pool.keys():
			if not used.has(key): geometry_pool.erase(key)
	for layer in persistent_layers: layer.set_zoom(view_zoom)
