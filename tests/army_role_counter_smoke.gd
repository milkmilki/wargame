extends SceneTree
## 角色兵棋门禁：同编制 MAIN/LINE 在 2D 与 3D 都必须显著不同。


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var line_profile := MapRenderer.army_counter_profile(
		GameState.INITIAL_LIGHT_ARMY_SIZE, Army.StrategicRole.LINE
	)
	var main_profile := MapRenderer.army_counter_profile(
		GameState.INITIAL_LIGHT_ARMY_SIZE, Army.StrategicRole.MAIN
	)
	var state := GameState.new()
	state.generate_world(12345)
	var line_army: Army = null
	var main_army: Army = null
	for army in state.armies:
		if line_army == null and army.is_line_role():
			line_army = army
		elif main_army == null and army.is_main_battle_role():
			main_army = army
		if line_army != null and main_army != null:
			break
	if line_army == null or main_army == null:
		_fail("fixture must contain both MAIN and LINE armies")
		return
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.paused = true
	var overlay := MapRenderer.new()
	root.add_child(overlay)
	overlay.setup(state, sim)
	overlay.set_world_layer_visible(false)
	var map_3d := StrategicMap3D.new()
	root.add_child(map_3d)
	map_3d.setup(state, sim, overlay)
	var started := Time.get_ticks_msec()
	while map_3d._terrain == null or map_3d._terrain.land_cell_count() <= 0:
		if Time.get_ticks_msec() - started > 15000:
			_fail("terrain timeout")
			return
		await process_frame
	var line_scale := StrategicMap3D.army_role_scale(line_army)
	var main_scale := StrategicMap3D.army_role_scale(main_army)
	var line_color := StrategicMap3D.army_role_base_color(line_army)
	var main_color := StrategicMap3D.army_role_base_color(main_army)
	var valid := (
		str(line_profile["role_code"]) == "线"
		and str(main_profile["role_code"]) == "主"
		and float(main_profile["width"]) > float(line_profile["width"])
		and main_scale > line_scale * 1.45
		and main_color.is_equal_approx(StrategicMap3D.MAP_GOLD)
		and line_color.is_equal_approx(StrategicMap3D.MAP_INK)
	)
	if not valid:
		_fail("role counters are not visually distinct: scales=%.2f/%.2f colors=%s/%s profiles=%s/%s" % [
			main_scale, line_scale,
			str(main_color), str(line_color), str(main_profile), str(line_profile),
		])
		return
	print("ARMY_ROLE_COUNTER_OK main_scale=%.2f line_scale=%.2f" % [
		main_scale, line_scale,
	])
	map_3d.free()
	overlay.free()
	sim.free()
	quit(0)


func _fail(message: String) -> void:
	push_error("ARMY_ROLE_COUNTER_FAILED: " + message)
	quit(1)
