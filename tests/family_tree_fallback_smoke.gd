extends SceneTree
## 模拟旧热重载实例：按钮脚本已更新，但场景里没有新增的家族树节点。

const TIMEOUT_MSEC := 20000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	var map_3d := main.get_node("StrategicMap3D") as StrategicMap3D
	var started := Time.get_ticks_msec()
	while map_3d._terrain == null or map_3d._terrain.land_cell_count() <= 0:
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("FAMILY_TREE_FALLBACK_TIMEOUT")
			quit(1)
			return
		await process_frame
	var renderer := main.get_node("MapRenderer") as MapRenderer
	var simulation := main.get_node("Simulation") as Simulation
	var original_panel := main.get_node("FamilyTreePanel") as FamilyTreePanel
	var normal_callback := Callable(original_panel, "open_for_nation")
	if renderer.family_tree_requested.is_connected(normal_callback):
		renderer.family_tree_requested.disconnect(normal_callback)
	main.remove_child(original_panel)
	original_panel.free()
	await process_frame

	simulation.paused = false
	renderer.select_nation(0)
	var opened := renderer._open_selected_nation_family_tree()
	await process_frame
	var fallback := main.get_node_or_null("FamilyTreePanel") as FamilyTreePanel
	var valid := (
		opened
		and fallback != null
		and fallback.is_open()
		and simulation.paused
	)
	if fallback != null:
		fallback.close_panel()
	valid = valid and not simulation.paused
	if not valid:
		push_error("FAMILY_TREE_FALLBACK_INVALID")
		quit(1)
		return
	print("FAMILY_TREE_FALLBACK_OK")
	main.free()
	quit(0)
