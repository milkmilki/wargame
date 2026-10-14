extends SceneTree
const Inputs = preload("res://tests/atlas_military_inputs.gd")
func _initialize(): call_deferred("run")
func run():
	var payload := Inputs.eurasia_military().duplicate()
	# Uniform affinities preserve the identical military choices on both revisions.
	var profiles := NationEnvironment.prepare(payload.data,payload.hierarchy)
	for p in profiles.profiles.values():
		p.kind="farm"
		for kind in NationEnvironment.KINDS: p.affinities[kind]=0.5
	payload.nation_environment=profiles
	var state := GameState.new(); state.generate_from_atlas(payload)
	state.region_ids.fill(0); state.region_analysis_revision+=1
	for nation in state.nations:
		nation.ruler_archetype=RulerProfile.BALANCED; nation.ruler_traits.clear()
		nation.treasury_gold=1000000; nation.manpower_pool=1000000
	for city in state.cities:
		if city.is_traffic: continue
		city.gold_per_month=100; city.food_per_half_year=10000; city.manpower_per_month=1000
	for a in range(40):
		for b in range(a+1,40): state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.ALLIED if (a<20)==(b<20) else GameState.DiplomaticRelation.WAR)
	var war := state.war_id_between(0,20)
	for a in range(20):
		for b in range(20,40): state.merge_war_ids(war,state.war_id_between(a,b))
	var sim := Simulation.new(); root.add_child(sim); sim.setup(state); sim.paused=true
	var samples: Array[int] = []
	var signature: Array = []
	for sample in range(18):
		state.day=(sample+1)*10; state.clear_campaign_fronts()
		for army in state.armies:
			army.campaign_war_id=-1; army.campaign_front_id=-1; army.path.clear(); army.state=Army.State.IDLE
			army.on_edge=false; army.size=15000; army.morale=100.; army.ai_order_until_day=0; army.defensive_deployment_until_day=0
		sim._ai_planned_armies.clear()
		var started := Time.get_ticks_usec(); sim._manage_coalition_campaigns()
		if sample>=3: samples.append(Time.get_ticks_usec()-started)
		signature.clear()
		for front in state.campaign_fronts.values(): signature.append([front.war_id,front.mode,front.center_city_id,front.anchor_nation_id,front.participant_nation_ids])
	var total := 0
	for value in samples: total+=value
	var average_ms := float(total)/samples.size()/1000.
	print("ENVIRONMENT_PLANNING_BENCHMARK samples=",samples.size()," average_ms=",average_ms," peak_ms=",samples.max()/1000.," choice_hash=",var_to_bytes(signature).hex_encode().sha256_text()," states=",profiles.profiles.size())
	var baseline := float(OS.get_environment("ENVIRONMENT_BENCH_BASELINE_MS"))
	var passed := baseline<=0. or average_ms<=baseline*1.05
	if baseline>0.: print("ENVIRONMENT_PLANNING_BUDGET baseline_ms=",baseline," current_ms=",average_ms," overhead_pct=",100.*(average_ms/baseline-1.)," pass=",passed)
	sim.free(); quit(0 if passed else 1)
