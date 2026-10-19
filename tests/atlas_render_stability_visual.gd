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
var longrun := false
var evidence_directory := EVIDENCE
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
	var row: Dictionary={"revision":revision,"memory_bytes":OS.get_static_memory_usage(),"cache_bytes":service.cache_bytes,"cache_entries":service.cache.size(),"pinned_bytes":pinned_bytes,"orphan_pins":orphan_pins,"users":service.geometry_users.size(),"pending":service.geometry_pending.size(),"history_points":view.history.snapshot_count(),"texture_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),"buffer_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)}
	samples.append(row); print("RENDER_STABILITY_SAMPLE ",JSON.stringify(row))
	check(orphan_pins==0,"only live consumers pin geometry")
	check(service.cache_bytes<=maxi(service.cache_budget,pinned_bytes),"the renderer obeys its byte budget including its actual live working set")
func run() -> void:
	if DisplayServer.get_name()=="headless": printerr("REAL_RENDERER_REQUIRED"); quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	longrun=OS.get_cmdline_user_args().has("--longrun-memory")
	if longrun: evidence_directory="res://.dbg/longrun-oom/"
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	# This test mutates committed state directly; no concurrent interactive
	# day command or timer may enter the simulation while those edits run.
	root.gui_disable_input=true
	root.size=Vector2i(1280,720); view=View.new(); view.terrain_model="earth"
	view.set_process_input(false); view.set_process_unhandled_input(false)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	var deadline:=Time.get_ticks_msec()+120000
	while not view.view_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(view.view_ready,"the original world loads")
	if not view.view_ready: quit(1); return
	view.simulation.paused=true; view.simulation.set_process(false); await ready_render()
	check(view.size==Vector2(root.size) and view.zoom>0.,"the real map fills a nonzero viewport")
	RenderingServer.force_draw(true)
	var pixels:=root.get_texture().get_image()
	var colors: Dictionary={}
	for y in range(180,620,24):
		for x in range(40,1240,40): colors[pixels.get_pixel(x,y).to_rgba32()]=true
	check(colors.size()>16,"the viewport contains visible map pixels rather than an empty background")
	pixels.save_png(evidence_directory+"startup-map.png")
	if colors.size()<=16: view.queue_free(); await process_frame; quit(1); return
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
	var districts: Array[Dictionary]=[{"id":target,"former":former,"enemy":enemy}]
	if longrun:
		for border in view.display.lines:
			if border.left<0 or border.right<0 or border.left==border.right: continue
			for city in view.state.land_cities_of(border.left):
				if view.state.administrative_center_of(city.id)==city.id or districts.any(func(row): return row.id==city.id): continue
				districts.append({"id":city.id,"former":border.left,"enemy":border.right})
				view.simulation._set_coalition_war([border.left] as Array[int],[border.right] as Array[int])
				break
			if districts.size()==10: break
		check(districts.size()==10,"ten different districts produce unique ownership revisions")
	await ready_render(); sample(0)
	var revisions:=720 if longrun else 180
	for revision in range(1,revisions+1):
		var operations: Array[Dictionary]=[]
		for index in range(districts.size()):
			var district: Dictionary=districts[index]
			var controller: int=district.enemy if (revision>>index)&1 else district.former
			if view.state.cities[district.id].owner_nation==controller: continue
			operations.append({"city_id":district.id,"controller_id":controller,"legal_owner_id":district.former,"sponsor_id":district.enemy if controller==district.enemy else -1,"reason":"renderer_churn"})
		var transaction:=view.state.apply_territory_transaction(operations)
		check(transaction.ok,"the real occupation / restoration transaction succeeds")
		if longrun:
			view.state.day=revision*30
			view.simulation.set_ruler_profile(former,RulerProfile.GUARDIAN if revision%2 else RulerProfile.CONQUEROR,[])
			view.capture_history(view.state.day)
		await process_frame; await ready_render()
		if revision%6==0:
			# Front nodes are rebuilt while previous shared uploads may still exist.
			view.front_layer.persistent_version=-1; view.front_layer.queue_redraw()
		if revision%30==0: sample(revision)
	var settled: int=samples[1].memory_bytes
	check(int(samples.back().memory_bytes)-settled<(192 if longrun else 96)*1024*1024,"after warming, distinct map revisions and historical records stay within the memory budget")
	if longrun: check(view.state.day==21600 and view.history.snapshot_count()==721,"720 monthly history points exceed the reported crash date without dropping old dates")
	RenderingServer.force_draw(true); root.get_texture().get_image().save_png(evidence_directory+"stability-map.png")
	FileAccess.open(evidence_directory+"gpu-stability.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples,"gpu":RenderingServer.get_video_adapter_name(),"source":OS.get_environment("WARGAME_RENDER_REPRO_MAP"),"history_source_sha256":FileAccess.get_sha256("res://scripts/state/political_history.gd"),"note":"%d real occupation/restoration publications on original geometry with %d monthly captures; no daily simulation replay."%[revisions,720 if longrun else 0]},"\t"))
	print("ATLAS_RENDER_STABILITY checks=",checks," failures=",failures)
	view.queue_free(); await process_frame; await process_frame; quit(1 if failures else 0)
