extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func fingerprint_builds() -> int:
	return int(TradeNetwork.connectivity_prefilter_counters().get("structure_fingerprint_builds", -1))
func run():
	var state := GameState.new()
	state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").eurasia_military())
	state.trade_enabled = true
	# Older committed inputs start with trade disabled and have no trade regions.
	# The compatibility check must exercise actual routes rather than empty data.
	if state.region_count <= 0: state.rebuild_region_analysis()
	var sim := Simulation.new(); sim.setup(state)
	sim._reset_trade_forecast_cache()
	TradeNetwork.reset_connectivity_prefilter_counters()
	var first := sim._forecast_trade_and_gold_flows(true).duplicate(true)
	check(fingerprint_builds() == 1, "cold forecast computes its exact structure fingerprint once; actual=%d" % fingerprint_builds())
	var warm := sim._forecast_trade_and_gold_flows(true)
	check(fingerprint_builds() == 1, "warm forecast reuses the existing structure; total=%d" % fingerprint_builds())
	check(var_to_bytes(first) == var_to_bytes(warm), "warm fiscal report remains exact")
	if sim.get("trade_structure_fingerprint_reuse_disabled") == null:
		finish(sim); return
	var expected := Simulation.monthly_gold_flows(state)
	check(var_to_bytes(first.gold_flows) == var_to_bytes(expected), "current forecast agrees with independent monthly calculation")
	sim._reset_trade_forecast_cache(); TradeNetwork.reset_connectivity_prefilter_counters()
	sim.set("trade_structure_fingerprint_reuse_disabled", true)
	var oracle := sim._forecast_trade_and_gold_flows(true)
	check(fingerprint_builds() == 2, "disabled comparison switch restores duplicate calculation")
	check(var_to_bytes(first) == var_to_bytes(oracle), "prepared and original paths return byte-identical fiscal data")
	TradeNetwork.reset_connectivity_prefilter_counters()
	var exact := TradeNetwork.structure_fingerprint(state)
	var prepared := TradeNetwork.build_structure(state, true, {}, {}, exact)
	check(fingerprint_builds() == 1, "a freshly prepared fingerprint is consumed without a second calculation")
	var direct := TradeNetwork.build_structure(state)
	check(fingerprint_builds() == 2, "public callers without prepared data still calculate their own fingerprint")
	check(var_to_bytes(prepared) == var_to_bytes(direct), "complete route structures retain exact ordering and values")
	var original_bytes := var_to_bytes(direct)
	if state.get("atlas_trade_cache") != null:
		check(not (prepared.routes as Array).is_empty(), "the current annual-route Eurasia fixture exercises actual routes")
	if not (prepared.routes as Array).is_empty():
		prepared.routes[0].city_path.append(-123)
		check(var_to_bytes(TradeNetwork.build_structure(state)) == original_bytes, "caller mutation cannot damage the internal route cache")
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.build_structure(state, true, {}, {}, PackedByteArray())
	check(fingerprint_builds() == 1, "an empty prepared fingerprint uses the normal calculation")
	sim.set("trade_structure_fingerprint_reuse_disabled", false)
	sim._reset_trade_forecast_cache()
	sim._forecast_trade_and_gold_flows(true)
	sim._trade_structure_cache.clear()
	TradeNetwork.reset_connectivity_prefilter_counters()
	sim._forecast_trade_and_gold_flows(true)
	check(fingerprint_builds() == 1, "a retained probe is not passed as a newly computed fingerprint")
	var city: City = state.cities[state.administrative_center_city_ids[0]]
	var changed := state.transfer_city_control(city.id, 1, 1, GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL, "fingerprint_reuse_test")
	check(bool(changed.get("ok", false)), "real territory transaction succeeds")
	var conquered := sim._forecast_trade_and_gold_flows(true).duplicate(true)
	check(var_to_bytes(conquered.gold_flows) == var_to_bytes(Simulation.monthly_gold_flows(state)), "ownership and new tax allocation refresh exactly")
	sim._reset_trade_forecast_cache(); state.trade_enabled = false
	var disabled := sim._forecast_trade_and_gold_flows(true)
	check(var_to_bytes(disabled.gold_flows) == var_to_bytes(Simulation.monthly_gold_flows(state)), "trade-off configuration retains the direct fiscal result")
	check(var_to_bytes(TradeNetwork.build_structure(null, true, {}, {}, exact)) == var_to_bytes(TradeNetwork.build_structure(null)), "null state retains its normal empty structure")
	state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").eurasia_military())
	state.trade_enabled = true
	if state.region_count <= 0: state.rebuild_region_analysis()
	sim.setup(state); sim._reset_trade_forecast_cache()
	TradeNetwork.reset_connectivity_prefilter_counters()
	var regenerated := sim._forecast_trade_and_gold_flows(true).duplicate(true)
	check(fingerprint_builds() == 1, "same-object regeneration computes a new current fingerprint once")
	check(var_to_bytes(regenerated.gold_flows) == var_to_bytes(Simulation.monthly_gold_flows(state)), "regeneration does not reuse the old ownership or fiscal data")
	# The old pre-trade Atlas baseline has no physical-region route links.
	# Also verify the interface on a connected legacy graph with nonempty routes.
	var grid := preload("res://tests/support/grid_world.gd").new()
	grid.generate_world(24680, 3, 24); grid.trade_enabled = true
	var grid_prepared := TradeNetwork.build_structure(grid, true, {}, {}, TradeNetwork.structure_fingerprint(grid))
	var grid_direct := TradeNetwork.build_structure(grid)
	check(not (grid_prepared.routes as Array).is_empty(), "connected legacy fixture exercises actual routes")
	check(var_to_bytes(grid_prepared) == var_to_bytes(grid_direct), "prepared legacy route data agrees with the normal public call")
	var grid_original := var_to_bytes(grid_direct)
	if not (grid_prepared.routes as Array).is_empty():
		grid_prepared.routes[0].city_path.append(-123)
		check(var_to_bytes(TradeNetwork.build_structure(grid)) == grid_original, "legacy result mutation cannot alter later route data")
	sim.free(); finish(null)
func finish(sim):
	if sim != null: sim.free()
	for failure in failures: printerr("TRADE_FINGERPRINT_REUSE_FAIL ",failure)
	print("TRADE_FINGERPRINT_REUSE_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
