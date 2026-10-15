extends SceneTree
## Real-renderer churn on the exact reported world; this is not a simulation replay.
const EVIDENCE := "res://.dbg/render-stability-20261015/"
class EvidenceLog extends DebugRunLog:
	func world_started(state: GameState, settings: Dictionary, source: String) -> void:
		# The reported original template already exists. Reference it instead of
		# serializing another 94 MB copy while measuring renderer memory.
		_world_index+=1; _last_day=state.day
		record("world_start",{"seed":state.world_seed,"source":source,"day":state.day,"settings":settings,"world_index":_world_index,"initial_map_template":OS.get_environment("WARGAME_RENDER_REPRO_MAP")})
class View extends "res://scripts/atlas/military_preview.gd":
	func load_native(_seed: int) -> void:
		var path:=OS.get_environment("WARGAME_RENDER_REPRO_MAP")
		var payload: Dictionary
		if path.is_empty(): payload=preload("res://tests/atlas_military_inputs.gd").eurasia_military(1)
		else:
			var template: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
			payload=preload("res://scripts/atlas/military_template.gd").decode(template)
		var prepared:=GameState.new(); prepared.generate_from_atlas(payload)
		run_log=EvidenceLog.new()
		await present_world(prepared,payload,"render_stability_original_template")
var failures:=0
var checks:=0
var samples: Array=[]
var view: View
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("RENDER_STABILITY_FAIL ",label)
func ready_render() -> void:
	check(await view.await_render_ready(30000),"the current complete map revision becomes visible")
	await process_frame
func sample(revision: int) -> void:
	var service: Node=view.render_scheduler
	var pinned_bytes:=0; var orphan_pins:=0
	for key in service.cache:
		if not service.cache[key].pinned: continue
		pinned_bytes+=int(service.cache[key].bytes)
		if str(key).begins_with("geometry:") and int(service.geometry_users.get(key,0))<=0: orphan_pins+=1
	var row: Dictionary={"revision":revision,"memory_bytes":OS.get_static_memory_usage(),"cache_bytes":service.cache_bytes,"cache_entries":service.cache.size(),"pinned_bytes":pinned_bytes,"orphan_pins":orphan_pins,"users":service.geometry_users.size(),"pending":service.geometry_pending.size()}
	samples.append(row); print("RENDER_STABILITY_SAMPLE ",JSON.stringify(row))
	check(orphan_pins==0,"only live consumers pin geometry")
	check(service.cache_bytes<=maxi(service.cache_budget,pinned_bytes),"the renderer obeys its byte budget including its actual live working set")
func run() -> void:
	if DisplayServer.get_name()=="headless": printerr("REAL_RENDERER_REQUIRED"); quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(EVIDENCE)
	root.size=Vector2i(1280,720); view=View.new(); view.terrain_model="earth"; root.add_child(view)
	var deadline:=Time.get_ticks_msec()+120000
	while not view.view_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(view.view_ready,"the original world loads")
	if not view.view_ready: quit(1); return
	view.simulation.paused=true; await ready_render()
	var mask: Dictionary=view.military_payload.data.options.settlement_mask
	check(view.state.world_seed==1 and view.state.nations.size()==40 and mask==preload("res://scripts/atlas/settlement_mask.gd").EURASIA,"actual seed1 / 40-country Eurasia input")
	var target:=-1; var former:=-1; var enemy:=-1
	for border in view.display.lines:
		if border.left<0 or border.right<0 or border.left==border.right: continue
		for city in view.state.land_cities_of(border.left):
			if view.state.administrative_center_of(city.id)!=city.id:
				target=city.id; former=border.left; enemy=border.right; break
		if target>=0: break
	check(target>=0,"a real border府 is available")
	if target<0: quit(1); return
	view.simulation._set_coalition_war([former] as Array[int],[enemy] as Array[int])
	await ready_render(); sample(0)
	for revision in range(1,181):
		var controller:=enemy if revision%2 else former
		var transaction:=view.state.apply_territory_transaction([{"city_id":target,"controller_id":controller,"legal_owner_id":former,"sponsor_id":enemy if controller==enemy else -1,"reason":"renderer_churn"}] as Array[Dictionary])
		check(transaction.ok,"the real occupation / restoration transaction succeeds")
		await process_frame; await ready_render()
		if revision%6==0:
			# Front nodes are rebuilt while previous shared uploads may still exist.
			view.front_layer.persistent_version=-1; view.front_layer.queue_redraw()
		if revision%30==0: sample(revision)
	var settled: int=samples[1].memory_bytes
	check(int(samples.back().memory_bytes)-settled<96*1024*1024,"after warming, 150 further ownership/front updates do not retain unbounded CPU allocations")
	RenderingServer.force_draw(true); root.get_texture().get_image().save_png(EVIDENCE+"stability-map.png")
	FileAccess.open(EVIDENCE+"gpu-stability.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples,"gpu":RenderingServer.get_video_adapter_name(),"source":OS.get_environment("WARGAME_RENDER_REPRO_MAP"),"note":"180 real occupation/restoration publications on original geometry; no day replay."},"\t"))
	print("ATLAS_RENDER_STABILITY checks=",checks," failures=",failures)
	view.queue_free(); await process_frame; await process_frame; quit(1 if failures else 0)
