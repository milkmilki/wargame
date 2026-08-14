extends SceneTree
## 纯省界视觉烟测：隐藏军队与 HUD，放大地图以检查有机边界和平滑线条。


func _init() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_world(12345)
	state.armies.clear()
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(state, simulation)
	renderer._map_zoom = 1.35
