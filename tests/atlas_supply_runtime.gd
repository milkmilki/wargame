extends SceneTree
## Default Eurasia/rulers/trade world: warm a genuine 60-day war state, then
## compare old synchronous supply against new worker supply on complete days.
const Legacy = preload("res://tests/support/legacy_supply_batch_simulation.gd")
func _initialize(): call_deferred("run")
func run():
	var payload: Dictionary = preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	var a := GameState.new(); a.generate_from_atlas(payload.duplicate(true))
	var b := GameState.new(); b.generate_from_atlas(payload.duplicate(true))
	var before := Legacy.new(); root.add_child(before); before.setup(a); before.paused=true
	var after := Simulation.new(); root.add_child(after); after.setup(b); after.paused=true
	var log := DebugRunLog.new(); log.begin("tests/atlas_supply_runtime.gd")
	log.world_started(b,{"days":65,"settlement_mask":payload.data.options.settlement_mask,"simulation_options":payload.simulation_options},"supply_runtime")
	for day in range(60):
		before._advance_day(false); after._advance_day(false)
		if a.day%15==0: print("ATLAS_SUPPLY_RUNTIME_WARM ",a.day); await process_frame
	var same: bool = var_to_bytes(NativeSnapshotBuilder.build(a))==var_to_bytes(NativeSnapshotBuilder.build(b))
	var exercised_succession := not b.succession_conflicts.is_empty()
	for day in range(5):
		before._advance_day(false); await after.advance_one_day()
		same=same and var_to_bytes(NativeSnapshotBuilder.build(a))==var_to_bytes(NativeSnapshotBuilder.build(b))
		exercised_succession=exercised_succession or not b.succession_conflicts.is_empty()
		log.checkpoint(b)
		print("ATLAS_SUPPLY_RUNTIME_DAY ",b.day," equivalent=",same)
	print("ATLAS_SUPPLY_RUNTIME_RESULT pid=",OS.get_process_id()," day=",b.day," equivalent=",same," succession=",exercised_succession)
	if not same: printerr("ATLAS_SUPPLY_RUNTIME_FAIL full state differs between old sync and new worker supply")
	if not exercised_succession: printerr("ATLAS_SUPPLY_RUNTIME_FAIL fixture did not exercise succession context")
	before.free(); after.free(); quit(0 if same and exercised_succession else 1)
