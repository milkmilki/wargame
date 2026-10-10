extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_RUNTIME_COST_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(12345)
	for i in range(2500):
		var node := City.new(); node.id=state.cities.size(); node.node_kind=City.NodeKind.TRAFFIC
		state.cities.append(node); state.adjacency[node.id]=[] as Array[int]
	var view := AiWorldView.build(state,0)
	for partition in [view.friendly_cities,view.enemy_cities,view.allied_cities,view.neutral_cities]:
		check(partition.all(func(city): return not city.is_traffic),"strategic partition excludes road junctions")
	var cities: Array[City]=[state.cities[5],state.cities[9],state.cities[1]]
	var expected := cities.duplicate()
	expected.sort_custom(func(a,b): return EquivariantOrder.city_less(state,0,a,b))
	EquivariantOrder._city_rank_cache.clear()
	EquivariantOrder.sort_cities(cities,state,0)
	check(cities==expected,"local city sort preserves global ranking order")
	check(EquivariantOrder._city_rank_cache.is_empty(),"local city sort does not rank the world")
	var armies: Array[Army]=[]
	for id in [9,5,1]:
		var army := Army.new(); army.location_city=0; army.ai_target_city=id
		armies.append(army)
	var ordered := armies.duplicate()
	ordered.sort_custom(func(a,b): return EquivariantOrder.army_less(state,0,a,b))
	EquivariantOrder._city_rank_cache.clear()
	EquivariantOrder.sort_armies(armies,state,0)
	check(armies==ordered,"local target ranks preserve military tie breaking")
	check(EquivariantOrder._city_rank_cache.is_empty(),"army sort does not rank road junctions")
	var inputs := DiplomacyAI._resource_forecast_inputs(state,{})
	var sliced_inputs := await DiplomacyAI.resource_forecast_inputs_over_frames(state,{},self)
	check(inputs==sliced_inputs,"frame-sliced aggregates match synchronous inputs")
	var food := DiplomacyAI.war_food_report(state,0,-1,-1,{},true)
	var cache_values := {}
	await DiplomacyAI.prepare_food_capacity_over_frames(state,0,cache_values,self)
	var sliced_food := DiplomacyAI.war_food_report(state,0,-1,-1,cache_values,true)
	check(food==sliced_food,"frame-sliced capacity search preserves forecast and tie breaking")
	var overlay := preload("res://scripts/atlas/military_overlay.gd").new(); overlay.state=state; root.add_child(overlay)
	await process_frame; await process_frame
	var marker_updates: int=overlay.marker_redraw_count
	for i in range(10): await process_frame
	check(overlay.marker_redraw_count==marker_updates,"stationary armies keep their recorded drawing commands")
	state.armies[0].location_city=1
	await process_frame; await process_frame
	check(overlay.marker_redraw_count>marker_updates,"army location changes refresh markers")
	root.remove_child(overlay); overlay.free()
	for nation in state.nations:
		check(inputs[nation.id].food_capacity==state.food_storage_capacity(nation.id),"batched storage equals capacity API")
		check(inputs[nation.id].manpower_target<=state.manpower_pool_capacity(nation.id),"batched manpower respects capacity")
	var service := preload("res://scripts/atlas/render_scheduler.gd").new(); root.add_child(service)
	var cache := preload("res://scripts/atlas/raster_layers.gd").new(); root.add_child(cache)
	var material := ShaderMaterial.new(); material.shader=Shader.new()
	material.shader.code="shader_type canvas_item; uniform float view_zoom=1.; uniform float glyph_scale=1.; void fragment(){COLOR=vec4(1.);}"
	cache.setup(ImageTexture.create_from_image(Image.create(1,1,false,Image.FORMAT_RGBA8)),material,service)
	var picture := Sprite2D.new(); root.add_child(picture); cache.bind(picture)
	var texture := picture.texture
	for i in range(50): cache.set_zoom(.8); picture.position+=Vector2(4,2)
	check(picture.texture==texture and cache.build_count==2,"camera reuses prepainted world textures")
	cache.set_zoom(8.); check(picture.texture.get_width()==8192,"zoomed picture retains detailed raster")
	cache.set_zoom(1.); check(picture.texture==texture,"overview cache survives zoom round trip")
	root.remove_child(picture); picture.free(); root.remove_child(cache); cache.free()
	check(service.cache_bytes==0,"terrain texture budget is released with the world")
	root.remove_child(service); service.free()
	print("ATLAS_RUNTIME_COSTS failures=",failures); quit(1 if failures else 0)
