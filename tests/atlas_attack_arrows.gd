extends SceneTree
const LAYER_PATH := "res://scripts/atlas/attack_arrows.gd"
var failures := 0
var checks := 0

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("ATTACK_ARROW_FAIL ", message)
func run():
	if not FileAccess.file_exists(LAYER_PATH):
		check(false, "the selected OL Plot attack arrow renderer exists")
		finish(); return
	test_geometry()
	var script = load(LAYER_PATH)
	var layer = script.new(); root.add_child(layer)
	var state := fixture()
	var rng_before := state.rng.state
	layer.configure(state, -1)
	check(layer.rows.size() == 1, "one coalition offense yields one arrow; defense and retiring fronts yield none")
	check(layer.batches.size() == 3 and layer.batches.all(func(mesh): return mesh.get_surface_count() == 1), "all arrows share only three drawing batches")
	check(layer.rows[0].origin == 0 and layer.rows[0].target == 2, "arrow runs from the actual staging city to the target state seat")
	check(layer.rows[0].axis[0].is_equal_approx(Vector2(2040,400)) and layer.rows[0].axis[-1].is_equal_approx(Vector2(2068,420)), "date-line attack uses the short continuous map direction")
	check(layer.rows[0].axis.size() == 3, "a legal intermediate entry bends the attack arrow")
	var builds: int = layer.geometry_build_count
	var meshes: Array = layer.rows[0].meshes.duplicate()
	var batches: Array = layer.batches.duplicate()
	for i in range(30):
		layer.position = Vector2(-i * 100, 0); layer.scale = Vector2.ONE * [.625,1.,2.,4.,8.][i % 5]
		layer.configure(state, -1)
	check(layer.geometry_build_count == builds and layer.rows[0].meshes == meshes, "camera movement and unchanged plans reuse cached arrow meshes")
	check(layer.batches == batches, "camera movement does not upload new combined geometry")
	var preparing := StateCampaign.new(); preparing.campaign_id = 8; preparing.initiator_nation_id = 1
	preparing.center_city_id = 0; preparing.defender_nation_id = 0
	state.state_campaigns[8] = preparing
	state.nations[1].war_preparation_staging_city_id = 2
	state.nations[1].war_preparation_objective_center_city = 0
	state.nations[1].war_preparation_target_nation = 0
	layer.configure(state, 0)
	check(layer.rows.size() == 1, "defender cannot see an undeclared preparation")
	layer.configure(state, 1)
	check(layer.rows.size() == 2 and layer.rows[1].preparing, "initiator can see its real preparation alongside public attacks")
	var frozen: Array = layer.rows.duplicate()
	state.campaign_fronts[3].staging_city_id = 1
	layer.configure(state, 1, true)
	check(layer.rows == frozen, "an unfinished simulation day keeps the previously committed arrows")
	layer.configure(state, 1)
	check(layer.rows[0].origin == 1, "committed rally changes replace the correct offensive arrow")
	state.state_campaigns.erase(8); layer.configure(state, 1)
	check(layer.rows.size() == 1, "cancelled preparation disappears")
	var record := StateCampaign.new(); record.campaign_id = 9; record.lifecycle = StateCampaign.Lifecycle.ENDING
	state.state_campaigns[9] = record; state.campaign_fronts[3].state_campaign_ids.append(9)
	layer.configure(state, 1)
	check(layer.rows.is_empty(), "a battle entering shared ending loses its offensive plan even during physical withdrawal")
	check(state.rng.state == rng_before, "rendering never consumes the simulation random stream")
	var replacement := fixture(); layer.configure(replacement, -1)
	check(layer.rows.size() == 1, "new world replaces disposed campaign references")
	replacement.cities[0].map_position = replacement.cities[2].map_position
	replacement.campaign_fronts[3].entry_city_id = -1
	layer.configure(replacement, -1)
	check(layer.rows.is_empty(), "coincident start and target never create degenerate meshes")
	root.remove_child(layer); layer.free()
	finish()
func fixture() -> GameState:
	var state := GameState.new(); state.rng.seed = 87
	for id in range(2):
		var nation := Nation.new(); nation.id = id; nation.color = Color("ac5545") if id == 0 else Color("446c8e")
		state.nations.append(nation)
	for point in [Vector2(2040,400), Vector2(2052,402), Vector2(20,420)]:
		var city := City.new(); city.id = state.cities.size(); city.map_position = point / Vector2(2048,1024)
		state.cities.append(city)
	for id in [3,4,5]:
		var front := CoalitionCampaignFront.new(); front.front_id = id; front.war_id = 0; front.anchor_nation_id = 0
		front.participant_nation_ids = [0,1] as Array[int]; front.center_city_id = 2
		front.staging_city_id = 0; front.entry_city_id = 1
		front.mode = CoalitionCampaignFront.Mode.DEFENSE if id == 4 else CoalitionCampaignFront.Mode.OFFENSE
		front.retiring = id == 5; state.campaign_fronts[id] = front
	return state
func test_geometry():
	var shape := preload("res://scripts/atlas/attack_arrow_geometry.gd")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ol-attack-arrow-reference.json"))
	for sample in reference.cases:
		var axis := PackedVector2Array()
		for point in sample.axis: axis.append(Vector2(point[0],point[1]))
		var polygon := shape.polygon(axis, sample.width)
		check(polygon.size() == sample.polygon.size(), "port retains upstream OL Plot contour sample count")
		for i in range(mini(polygon.size(),sample.polygon.size())):
			check(polygon[i].distance_to(Vector2(sample.polygon[i][0],sample.polygon[i][1])) < .002, "native polygon matches the independent TypeScript reference")
		check(not Geometry2D.triangulate_polygon(polygon).is_empty(), "the upstream arrow shape produces a fillable native mesh")
	var straight := PackedVector2Array([Vector2(100,200),Vector2(300,200)])
	var repeated := PackedVector2Array([Vector2(100,200),Vector2(100,200),Vector2(300,200),Vector2(300,200)])
	check(shape.polygon(straight,40) == shape.polygon(repeated,40), "duplicate route coordinates do not produce invalid corners")
	check(shape.polygon(PackedVector2Array([Vector2.ONE,Vector2.ONE]),3).is_empty(), "zero length axis has no polygon")
	check(shape.polygon(straight,0).is_empty() and shape.polygon(straight,INF).is_empty(), "invalid arrow widths are rejected")
	check(shape.polygon(PackedVector2Array([Vector2(NAN,0),Vector2.ONE]),3).is_empty(), "nonfinite points never reach the renderer")
func finish():
	print("ATLAS_ATTACK_ARROWS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
