extends SceneTree
## Claims must not scan idle reserves after all relevant deficits are covered.
class CountingState extends GameState:
	var eligibility_checks := {}
	func army_effective_for_field_campaign(army: Army) -> bool:
		eligibility_checks[army.owner_nation] = int(eligibility_checks.get(army.owner_nation,0))+1
		return super.army_effective_for_field_campaign(army)

var failures := 0
func _initialize():
	create_timer(90.).timeout.connect(func(): printerr("MOBILIZATION_COST_TIMEOUT"); quit(1))
	call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("MOBILIZATION_COST_FAIL ",message)
func fixture(requirement: int) -> CountingState:
	var state:=CountingState.new(); state.day=100
	for owner in range(2):
		var city:=City.new(); city.id=owner; city.owner_nation=owner; city.map_position=Vector2(.2+owner*.6,.5)
		state.cities.append(city)
		var nation:=Nation.new(); nation.id=owner; nation.capital_city_id=owner; state.nations.append(nation)
	var front:=CoalitionCampaignFront.new(); front.front_id=1; front.war_id=7
	front.mode=CoalitionCampaignFront.Mode.DEFENSE; front.participant_nation_ids=[0,1]
	front.combat_report_day=100; front.reported_requirement=requirement
	state.campaign_fronts[1]=front
	return state
func army(state: GameState,owner: int,size: int) -> Army:
	var unit:=Army.new(); unit.id=state.armies.size(); unit.owner_nation=owner; unit.location_city=owner
	unit.size=size; unit.max_size=size; state.armies.append(unit); return unit
func simulation(state: GameState) -> Simulation:
	var sim:=Simulation.new(); sim.state=state
	for unit in state.armies:
		if not sim._coalition_armies_by_nation.has(unit.owner_nation): sim._coalition_armies_by_nation[unit.owner_nation]=[] as Array[Army]
		sim._coalition_armies_by_nation[unit.owner_nation].append(unit)
	return sim
func run():
	for argument in OS.get_cmdline_user_args():
		if argument=="--benchmark": benchmark(); return
	var state:=fixture(0)
	for owner in range(2):
		for index in range(64): army(state,owner,15000)
	var sim:=simulation(state)
	check(sim._campaign_mobilization_claims().is_empty(),"zero deficits produce no claims")
	check(state.eligibility_checks.is_empty(),"zero deficits do not inspect idle candidates")
	sim.free()
	state=fixture(5000); var first:=army(state,0,15000)
	for index in range(64): army(state,1,15000)
	sim=simulation(state); var claims:=sim._campaign_mobilization_claims()
	check(claims.keys()==[first.id],"the first eligible member covers the coalition deficit")
	check(not state.eligibility_checks.has(1),"covered deficits do not inspect later allied reserves")
	sim.free()
	state=fixture(45000)
	var wrong_war:=army(state,0,10000); wrong_war.campaign_war_id=8
	var a:=army(state,0,15000); var b:=army(state,1,30000)
	var extra:=army(state,1,40000); extra.defensive_deployment_until_day=101
	sim=simulation(state); claims=sim._campaign_mobilization_claims()
	check(claims.keys()==[a.id,b.id],"war ownership and defensive locks retain reserve priority")
	state.campaign_fronts.clear(); state.eligibility_checks.clear(); a.campaign_front_id=9
	check(sim._campaign_mobilization_claims().is_empty(),"no campaign tasks require no mobilization")
	check(state.eligibility_checks.is_empty(),"no campaigns do not inspect stale bound armies")
	sim.free()
	print("MOBILIZATION_COSTS failures=",failures); quit(1 if failures else 0)
func benchmark():
	# Reuse a real EURASIA workload without generating or saving another world.
	var directory:="res://.dbg/native-runtime/"
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"manifest.json"))
	if int(manifest.get("world_seed",-1))!=1 or int(manifest.get("initial_nations",0))!=40:
		printerr("MOBILIZATION_BENCH wrong input provenance"); quit(1); return
	var codec:=preload("res://tests/support/native_runtime_fixture.gd").new()
	var state: GameState=codec.unpack(FileAccess.open(directory+"day-600.bin",FileAccess.READ).get_var(false))
	var error: String=codec.validate_world(state,1,false)
	if not error.is_empty(): printerr(error); quit(1); return
	var sim:=Simulation.new(); sim.setup(state); sim.paused=true
	sim._prepare_coalition_campaign_batch()
	for index in range(3): sim._campaign_mobilization_claims()
	var before:=var_to_bytes(codec.snapshot(state)); var rng_before:=state.rng.state
	var expected:=sim._campaign_mobilization_claims(); var durations: Array[int]=[]
	for index in range(25):
		var started:=Time.get_ticks_usec(); var claims:=sim._campaign_mobilization_claims()
		durations.append(Time.get_ticks_usec()-started)
		check(var_to_bytes(claims)==var_to_bytes(expected),"claim bytes are repeatable")
	check(state.rng.state==rng_before and before==var_to_bytes(codec.snapshot(state)),"claims preserve the real state and random stream")
	durations.sort()
	print("MOBILIZATION_BENCH day=%d armies=%d fronts=%d claims=%d median_us=%d p95_us=%d claim_sha=%s"%[state.day,state.armies.size(),state.campaign_fronts.size(),expected.size(),durations[12],durations[23],codec.hash_bytes(var_to_bytes(expected))])
	benchmark_sorts(state)
	var supply_times: Array[int]=[]
	for index in range(28):
		var started:=Time.get_ticks_usec(); sim._prepare_supply_network_caches()
		if index>=3: supply_times.append(Time.get_ticks_usec()-started)
	supply_times.sort()
	print("SUPPLY_PREPARE_BENCH median_us=%d p95_us=%d fingerprint_sha=%s"%[supply_times[12],supply_times[23],codec.hash_bytes(var_to_bytes(sim._supply_network_fingerprints))])
	check(state.rng.state==rng_before and before==var_to_bytes(codec.snapshot(state)),"sorting and supply preparation preserve authoritative state")
	sim.free(); quit(1 if failures else 0)
func benchmark_sorts(state: GameState):
	var groups: Dictionary={}; var expected: Dictionary={}
	for unit in state.armies:
		if not groups.has(unit.owner_nation): groups[unit.owner_nation]=[] as Array[Army]
		groups[unit.owner_nation].append(unit)
	for owner in groups:
		var ordered: Array[Army]=groups[owner].duplicate()
		ordered.sort_custom(func(a,b): return EquivariantOrder.army_less(state,owner,a,b))
		expected[owner]=ordered
	for batch in [false,true]:
		var times: Array[int]=[]
		for iteration in range(28):
			var started:=Time.get_ticks_usec(); var result: Dictionary={}
			for owner in groups:
				var ordered: Array[Army]=groups[owner].duplicate()
				if batch: EquivariantOrder.sort_armies(ordered,state,owner)
				else: ordered.sort_custom(func(a,b): return EquivariantOrder.army_less(state,owner,a,b))
				result[owner]=ordered
			if iteration>=3: times.append(Time.get_ticks_usec()-started)
			check(result==expected,"batch army keys preserve exact order for every real nation")
		times.sort()
		print("ARMY_SORT_BENCH batch=%s armies=%d median_us=%d p95_us=%d"%[batch,state.armies.size(),times[12],times[23]])
