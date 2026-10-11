extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var payload: Dictionary = preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	var a := GameState.new(); a.generate_from_atlas(payload.duplicate(true))
	var b := GameState.new(); b.generate_from_atlas(payload.duplicate(true))
	var sync := Simulation.new(); root.add_child(sync); sync.setup(a); sync.paused=true
	var sliced := Simulation.new(); root.add_child(sliced); sliced.setup(b); sliced.paused=true
	for state in [a,b]:
		state.day=359; state.month=11
		var region := int(state.atlas_trade_centers.keys().min())
		var incumbent := int(state.atlas_trade_centers[region])
		for city in state.cities:
			if city.is_settlement() and state.region_ids[city.id]==region and city.id!=incumbent:
				city.gold_per_month=10000; break
		TradeNetwork.build(state)
	sync._advance_day()
	await sliced.advance_one_day()
	var same: bool = var_to_bytes(NativeSnapshotBuilder.build(a))==var_to_bytes(NativeSnapshotBuilder.build(b))
	same=same and a.atlas_trade_centers==b.atlas_trade_centers and a.trade_routes==b.trade_routes
	print("ATLAS_TRADE_RUNTIME day=",a.day," equivalent=",same," fields=",a.atlas_trade_cache.dijkstra_builds,"/",b.atlas_trade_cache.dijkstra_builds)
	if not same: printerr("ATLAS_TRADE_RUNTIME_FAIL annual rotation differs between sync and worker paths")
	sync.free(); sliced.free(); quit(0 if same else 1)
