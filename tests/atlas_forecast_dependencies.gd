extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks+=1
	if not ok: failures.append(message)
func equal_direct(sim: Simulation, label: String):
	var cached := sim._forecast_trade_and_gold_flows(true)
	var direct := Simulation.monthly_gold_flows(sim.state)
	check(var_to_bytes(cached.gold_flows)==var_to_bytes(direct),label+": exact current fiscal reports")
func run():
	var state := GameState.new(); state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").eurasia_military())
	var sim := Simulation.new(); sim.setup(state)
	var city := state.cities[state.administrative_center_city_ids[0]]
	city.war_disruption_until_day=100
	equal_direct(sim,"start disruption")
	var initial_probe := sim._trade_structure_runtime_probe()
	var initial_token := sim._trade_structure_fingerprint
	var initial_builds := sim.trade_structure_build_total
	for day in range(1,4):
		state.day=day; city.war_disruption_until_day=100+day
		check(sim._trade_structure_runtime_probe()==initial_probe,"extending an already active disruption does not invalidate current tax geometry")
		equal_direct(sim,"extended day%d"%day)
		check(sim._trade_structure_fingerprint==initial_token and sim.trade_structure_build_total==initial_builds,"extension retains existing structure")
	state.day=city.war_disruption_until_day
	check(sim._trade_structure_runtime_probe()!=initial_probe,"disruption expiry invalidates immediately")
	equal_direct(sim,"expired")
	check(sim._trade_structure_fingerprint!=initial_token,"expiry refreshes actual output")
	state.edge_of(state.edges[0].city_a,state.edges[0].city_b).danger=.31
	state.road_network_revision+=1; equal_direct(sim,"road edit")
	state.nations[0].trade_policy=TradeNetwork.GOLD; state.nations[0].ruler_revision+=1
	equal_direct(sim,"ruler policy")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	equal_direct(sim,"war discount")
	var transferred := state.transfer_city_control(city.id,1,1,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"forecast_cache_test")
	check(bool(transferred.get("ok",false)),"real control transfer succeeds")
	equal_direct(sim,"conquest")
	sim.free()
	for failure in failures: printerr("ATLAS_FORECAST_DEPENDENCY_FAIL ",failure)
	print("ATLAS_FORECAST_DEPENDENCY_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
