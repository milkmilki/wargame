extends Node2D
## Persistent schematic attack plans; no pathfinding or writes to simulation.
const Shape = preload("res://scripts/atlas/attack_arrow_geometry.gd")
const Strokes = preload("res://scripts/atlas/ink_strokes.gd")
const WORLD := Vector2(2048,1024)
const PAPER := Color(.97,.93,.83,.75)
var rows: Array = []
var geometry_build_count := 0
var publication_count := 0
var source_id := 0
var row_cache := {}
var batches: Array[ArrayMesh] = []

static func valid_city(state: GameState, id: int) -> bool:
	return id >= 0 and id < state.cities.size() and state.cities[id].map_position.is_finite()

static func axis_for(state: GameState, origin: int, target: int, entry: int) -> PackedVector2Array:
	if not valid_city(state, origin) or not valid_city(state, target): return PackedVector2Array()
	var start := state.cities[origin].map_position * WORLD
	start.x = fposmod(start.x, WORLD.x)
	var tip := state.cities[target].map_position * WORLD
	tip.x += roundf((start.x-tip.x)/WORLD.x) * WORLD.x
	var delta := tip-start
	if delta.length_squared() < .001: return PackedVector2Array()
	var axis := PackedVector2Array([start])
	if valid_city(state, entry) and entry != origin and entry != target:
		var via := state.cities[entry].map_position * WORLD
		via.x += roundf((start.x-via.x)/WORLD.x) * WORLD.x
		var fraction := (via-start).dot(delta) / delta.length_squared()
		var deviation := absf((via-start).cross(delta)) / delta.length_squared()
		# Only a forward entry is useful for a readable schematic curve.
		if fraction > .08 and fraction < .8 and deviation < .35: axis.append(via)
	axis.append(tip)
	return axis

static func plans(state: GameState, observer: int) -> Array:
	var result: Array = []
	var ids := state.campaign_fronts.keys(); ids.sort()
	for id in ids:
		var front: CoalitionCampaignFront = state.campaign_fronts[id]
		if front.mode != CoalitionCampaignFront.Mode.OFFENSE or front.retiring or front.war_id < 0: continue
		var actor := front.anchor_nation_id
		if actor < 0 or actor >= state.nations.size() or not state.nations[actor].alive: continue
		var active := front.state_campaign_ids.is_empty()
		for campaign_id in front.state_campaign_ids:
			var record: StateCampaign = state.state_campaigns.get(campaign_id)
			if record != null and record.lifecycle == StateCampaign.Lifecycle.ACTIVE: active = true
		if not active: continue
		var origin := front.staging_city_id if valid_city(state, front.staging_city_id) else front.camp_city_id
		var axis := axis_for(state, origin, front.center_city_id, front.entry_city_id)
		if axis.size() >= 2:
			result.append({"key":"front:%d"%id, "origin":origin, "target":front.center_city_id, "axis":axis, "color":state.nations[actor].color, "preparing":false})
	ids = state.state_campaigns.keys(); ids.sort()
	for id in ids:
		var record: StateCampaign = state.state_campaigns[id]
		if record.lifecycle != StateCampaign.Lifecycle.PREPARING or not record.visible_to(observer): continue
		var actor := record.initiator_nation_id
		if actor < 0 or actor >= state.nations.size(): continue
		var nation: Nation = state.nations[actor]
		if not nation.alive or nation.war_preparation_target_nation != record.defender_nation_id or nation.war_preparation_objective_center_city != record.center_city_id: continue
		var axis := axis_for(state, nation.war_preparation_staging_city_id, record.center_city_id, -1)
		if axis.size() >= 2:
			result.append({"key":"preparation:%d"%id, "origin":nation.war_preparation_staging_city_id, "target":record.center_city_id, "axis":axis, "color":nation.color, "preparing":true})
	return result

func configure(state: GameState, observer: int, day_in_progress: bool = false) -> void:
	if day_in_progress: return # Match the country's frozen daily presentation.
	if source_id != state.get_instance_id(): source_id = state.get_instance_id(); row_cache.clear()
	var next: Array = []; var retained := {}; var changed := false
	for plan in plans(state, observer):
		var previous: Dictionary = row_cache.get(plan.key, {})
		if not previous.is_empty() and previous.axis == plan.axis and previous.color == plan.color and previous.preparing == plan.preparing and previous.origin == plan.origin and previous.target == plan.target:
			next.append(previous); retained[plan.key] = previous; continue
		var row := build_row(plan)
		if row.is_empty(): continue
		next.append(row); retained[plan.key] = row; changed = true
	changed = changed or rows != next
	rows = next; row_cache = retained
	if changed: rebuild_batches(); publication_count += 1; queue_redraw()

func rebuild_batches() -> void:
	batches.clear()
	for layer in range(3):
		var vertices := PackedVector3Array(); var colors := PackedColorArray(); var indices := PackedInt32Array()
		for row in rows:
			var mesh: ArrayMesh = row.meshes[layer]
			if mesh.get_surface_count() == 0: continue
			var source := mesh.surface_get_arrays(0)
			var base := vertices.size(); var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
			vertices.append_array(points)
			# Atlas country colors are deliberately pastel; tactical ink needs a
			# darker, more saturated version of the same hue above the paper map.
			var color: Color = row.color
			var ink := Color.from_hsv(color.h,maxf(color.s,.45),minf(color.v,.62),.95)
			var tint := Color(ink,.22 if row.preparing else .38) if layer == 0 else (PAPER if layer == 1 else ink)
			var source_colors: PackedColorArray = source[Mesh.ARRAY_COLOR] if source[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			for i in range(points.size()): colors.append(tint * source_colors[i] if not source_colors.is_empty() else tint)
			for index in source[Mesh.ARRAY_INDEX]: indices.append(base+index)
		var batch := ArrayMesh.new()
		if not vertices.is_empty():
			var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_INDEX] = indices
			batch.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		batches.append(batch)

func build_row(plan: Dictionary) -> Dictionary:
	var length := 0.
	for i in range(1, plan.axis.size()): length += plan.axis[i-1].distance_to(plan.axis[i])
	var polygon := Shape.polygon(plan.axis, clampf(length*.2, 2., 14.))
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty(): return {}
	var vertices := PackedVector3Array()
	for point in polygon: vertices.append(Vector3(point.x,point.y,0.))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_INDEX] = indices
	var fill := ArrayMesh.new(); fill.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var closed := polygon.duplicate(); closed.append(closed[0])
	var meshes := [fill, Strokes.build([closed], .70, .10), Strokes.build([closed], .30, .10)]
	geometry_build_count += 1
	var row := plan.duplicate(); row.meshes = meshes; row.polygon = polygon
	return row

func _draw() -> void:
	for shift in [-2048.,0.,2048.]:
		draw_set_transform(Vector2(shift,0.))
		for mesh in batches:
			if mesh.get_surface_count() > 0: draw_mesh(mesh,null)
	draw_set_transform(Vector2.ZERO)
