extends SceneTree
const Generator = preload("res://scripts/atlas/generator.gd")
var errors := 0
func check(ok: bool,message: String) -> void:
	if not ok: errors += 1; print("PREVIEW_FAIL ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(2048,1024)
	var scene = load("res://atlas_preview.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.generating: await process_frame
	var initial_rainfall_model: String = scene.data.options.get("rainfall_model","atlas_original")
	var initial_settlement_model: String = scene.data.options.get("settlement_model","atlas_original")
	check(scene.rainfall_model==initial_rainfall_model,"rainfall model control differs from loaded world")
	scene.snapshot_path = "res://.dbg/atlas-preview-test.snapshot"
	scene.hud.hide()
	var road_bytes := var_to_bytes(scene.data.roads); var province_bytes := var_to_bytes(scene.data.regions.of)
	var index_before: Dictionary = scene.province_index
	var country_index_before: Dictionary = scene.political_index; var country_labels_before := var_to_bytes(scene.political_labels)
	var country_edge_before: ImageTexture = scene.political_edge
	for mode in range(4):
		scene.mode_control.select(mode); scene.update_mode(); await process_frame; RenderingServer.force_draw(true)
		root.get_texture().get_image().save_png("res://.dbg/atlas-native-reference/godot-native-mode-%d.png"%mode)
		check(var_to_bytes(scene.data.roads)==road_bytes,"mode switch changed roads")
		check(scene.province_index==index_before,"mode switch rebuilt province geometry")
		check(scene.political_index==country_index_before and var_to_bytes(scene.political_labels)==country_labels_before and scene.political_edge==country_edge_before,"mode switch rebuilt country display geometry")
	scene.mode_control.select(0); scene.update_mode()
	scene.show_border_layer = false; scene.mode_control.select(2); scene.update_mode(); check(not scene.copies[0].ink.show_borders,"mode switch ignored boundary toggle")
	scene.show_border_layer = true; scene.mode_control.select(0); scene.update_mode()
	var city: Dictionary = scene.data.cities[0]; scene.select_at(Vector2(scene.data.mesh.x[city.cell],scene.data.mesh.y[city.cell]))
	check(scene.selected_region>=0,"city click failed")
	var region := int(scene.selected_region); var owner := int(scene.data.ownership[region]); var next: int = (owner+1)%scene.data.nations.size()
	scene.owner_control.value = next; scene.change_owner()
	check(scene.data.ownership[region]==next,"owner change failed")
	check(var_to_bytes(scene.data.roads)==road_bytes and var_to_bytes(scene.data.regions.of)==province_bytes,"owner change regenerated data")
	scene.save_snapshot(); check(FileAccess.file_exists(scene.snapshot_path),"snapshot missing")
	scene.data.ownership[region] = owner
	scene.rainfall_model = "atlas_original" if initial_rainfall_model!="atlas_original" else "legacy_monsoon_global_v1"
	scene.settlement_model = "atlas_original" if initial_settlement_model!="atlas_original" else "climate_capacity_v2"
	await scene.load_snapshot()
	check(scene.rainfall_model==initial_rainfall_model,"snapshot lost rainfall model")
	check(scene.rain_control.selected==scene.RAIN_MODELS.find(initial_rainfall_model),"snapshot rainfall selector not synchronized")
	check(scene.settlement_model==initial_settlement_model,"snapshot lost settlement model")
	check(scene.data.ownership[region]==next,"snapshot owner restore")
	check(scene.default_owners[region]==owner,"snapshot lost generated ownership baseline")
	FileAccess.open(scene.snapshot_path,FileAccess.WRITE).store_var({"format":"atlas-preview","version":99},false)
	await scene.load_snapshot(); check(scene.data.ownership[region]==next,"failed load replaced current world")
	scene.data.ownership = Array(scene.default_owners); scene.refresh_ownership()
	scene.threshold_control.value = 50; await scene.rebuild_roads()
	check(scene.data.cities.is_empty() and scene.data.roads.is_empty(),"high threshold world still has cities or roads")
	check(var_to_bytes(scene.data.regions.of)==province_bytes,"threshold changed provinces")
	scene.threshold_control.value = 1; await scene.rebuild_roads(); check(var_to_bytes(scene.data.roads)==road_bytes,"threshold restore road determinism")
	scene.text_layer.show_names = false; scene.text_layer.show_cities = false; scene.text_layer.rebuild(); scene.fit_map()
	for mode in range(4):
		scene.mode_control.select(mode); scene.update_mode(); await process_frame; RenderingServer.force_draw(true)
		root.get_texture().get_image().save_png("res://.dbg/atlas-native-reference/godot-native-compare-mode-%d.png"%mode)
	scene.mode_control.select(0); scene.update_mode()
	for k in [2.,4.,8.]:
		scene.zoom = k; scene.map_root.scale = Vector2.ONE*k; scene.map_root.position = Vector2(1024,512)-Vector2(500,420)*k
		scene.limit_pan(); scene.refresh_symbols(); await process_frame; RenderingServer.force_draw(true)
		root.get_texture().get_image().save_png("res://.dbg/atlas-native-reference/godot-native-zoom-%d.png"%int(k))
	scene.zoom = 4; scene.map_root.scale = Vector2.ONE*4; scene.map_root.position = Vector2(1024,512)-Vector2(2048,440)*4; scene.limit_pan(); scene.refresh_symbols()
	await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png("res://.dbg/atlas-native-reference/godot-native-seam.png")
	scene.zoom = 8; scene.map_root.scale = Vector2.ONE*8; scene.map_root.position = Vector2(1024,512)-Vector2(880,160)*8; scene.limit_pan(); scene.refresh_symbols()
	await process_frame; RenderingServer.force_draw(true); root.get_texture().get_image().save_png("res://.dbg/atlas-native-reference/godot-native-polar-8.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scene.snapshot_path))
	print("ATLAS_NATIVE_PREVIEW failures=",errors); quit(1 if errors else 0)
