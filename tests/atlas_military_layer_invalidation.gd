extends SceneTree
## Changing an inspection ring or combat label must preserve recorded army ink.
const Overlay = preload("res://scripts/atlas/military_overlay.gd")
var failures := 0
var checks := 0
var army_draws := 0

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("MILITARY_LAYER_FAIL ", message)
func settle():
	await process_frame
	await process_frame
func run():
	var state := GameState.new()
	state.rng.seed = 8123
	var rng_before := state.rng.state
	var nation := Nation.new(); nation.id = 0; nation.color = Color("775533")
	state.nations.append(nation)
	var city := City.new(); city.id = 0; city.owner_nation = 0; city.map_position = Vector2(.25, .4)
	state.cities.append(city)
	for id in [4, 9]:
		var army := Army.new(); army.id = id; army.owner_nation = 0; army.location_city = 0; army.size = 15000
		state.armies.append(army)
	var battle := Battle.new(); battle.id = 7; battle.city = city
	battle.side_a = [state.armies[0]]; battle.side_b = [state.armies[1]]
	state.battles.append(battle)
	var overlay := Overlay.new(); overlay.state = state
	root.add_child(overlay)
	await process_frame
	check(overlay.markers != null, "the public army marker layer remains available")
	overlay.markers.draw.connect(func(): army_draws += 1)
	overlay.markers.queue_redraw()
	await settle()
	var army_mesh: MultiMesh = overlay.get("army_mesh")
	check(army_mesh != null and army_mesh.visible_instance_count == 2, "the army batch submits the visible formations once per longitude copy")
	var recorded := army_draws
	for i in range(4): await process_frame
	check(army_draws == recorded, "idle frames reuse army drawing commands")
	overlay.selection = 4
	await settle()
	check(army_draws == recorded, "selecting a formation only redraws the inspection ring")
	overlay.selection = 9
	await settle()
	check(army_draws == recorded, "switching selected formation preserves all army drawing commands")
	overlay.selection = -1
	await settle()
	check(army_draws == recorded, "closing army inspection preserves the army layer")
	# A normal non-fatal casualty changes the combat label without removing a dot.
	state.armies[0].size -= 1000
	await settle()
	check(army_draws == recorded, "combat manpower text changes without rebuilding unchanged army dots")
	check(overlay.battle_strength(battle).counts == [0, 14000, 15000], "the independent combat presentation uses live casualties")
	var battle_builds := int(overlay.get("battle_build_count"))
	overlay.scale = Vector2.ONE * 2.
	overlay.set_view(2., Rect2(0, 0, 1024, 512))
	await settle()
	check(army_draws == recorded, "zoom inside the same visible army set reuses army geometry")
	check(int(overlay.get("battle_build_count")) == battle_builds, "zoom reuses the recorded combat text")
	check(is_equal_approx(float(overlay.markers.material.get_shader_parameter("view_zoom")),2.), "the batched army ink receives the actual zoom for fixed screen radii")
	var battle_layer: Node2D = overlay.get("battle_markers")
	check(battle_layer != null and battle_layer.get_child_count() > 0, "combat presentation has its own layer")
	if battle_layer != null:
		for node in battle_layer.get_children():
			check(node.global_scale.is_equal_approx(Vector2.ONE), "combat text remains at its original screen size after zoom")
	var point := city.map_position * Vector2(2048, 1024) + Vector2(0, -25) / 2.
	check(overlay.battle_at(point) == 7, "zoomed combat bar remains clickable at its actual screen size")
	check(overlay.battle_at(point + Vector2(2048, 0)) == 7, "wrapped battle bar retains the same combat target")
	battle.finished = true
	await settle()
	check(army_draws == recorded, "removing a combat label preserves surviving army dots")
	check(overlay.battle_at(point) == -1, "finished combat loses its information target")
	state.armies[0].location_city = -1
	state.armies[0].size = 0
	await settle()
	check(army_draws > recorded, "a destroyed formation is actually removed from the army layer")
	if army_mesh != null:
		check(army_mesh.visible_instance_count == 1, "the batch removes the destroyed formation")
		overlay.set_view(2.,Rect2(1500,200,120,100))
		await settle()
		check(army_mesh.visible_instance_count == 0, "formations outside the view submit no army instances")
		overlay.set_view(2.,Rect2(-1590,390,150,60))
		await settle()
		check(army_mesh.visible_instance_count == 1, "panning across the seam submits the visible wrapped formation")
		overlay.set_view(2.,Rect2(10700,390,150,60))
		await settle()
		check(army_mesh.visible_instance_count == 1, "panning to a distant longitude copy submits the correct world instance")
	check(state.rng.state == rng_before, "display updates leave the simulation random stream unchanged")
	root.remove_child(overlay); overlay.queue_free(); await process_frame
	print("ATLAS_MILITARY_LAYER_INVALIDATION checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
