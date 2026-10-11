extends SceneTree
const Inputs = preload("res://tests/atlas_military_inputs.gd")
const Template = preload("res://scripts/atlas/military_template.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("ATLAS_POLITICS_TRADE_FAIL ", message)
func _initialize(): call_deferred("run")
func run():
	test_transit()
	var payload := Inputs.eurasia_military().duplicate()
	payload.simulation_options = {"trade_enabled":true,"rulers_enabled":true}
	if "--export-visual" in OS.get_cmdline_user_args(): FileAccess.open("res://.dbg/atlas-politics-visual.bin",FileAccess.WRITE).store_var(payload,false)
	var state := GameState.new(); state.generate_from_atlas(payload)
	check(state.trade_enabled and state.random_ruler_profiles_enabled(),"requested systems enabled")
	var profiles := {}
	for nation in state.nations:
		check(not nation.ruler_name.is_empty() and nation.ruler_name!="中性君主","real ruler initialized")
		profiles[nation.ruler_archetype]=true
	check(profiles.size()>1,"deterministic varied ruler profiles")
	var allowed := TradeNetwork._ideal_city_mask(state)
	for city in state.cities:
		if city.is_traffic: check(allowed[city.id]==1,"junction is traversable, not a trade endpoint")
	var whole := Edge.new(); whole.precise_distance=2.
	var half := Edge.new(); half.precise_distance=1.
	check(is_equal_approx(TradeNetwork._edge_transport_cost(whole,true),2.*TradeNetwork._edge_transport_cost(half,true)),"segment cost is additive")
	if failures: quit(1); return
	var before_rng := state.rng.state
	var structure := TradeNetwork.build_structure(state)
	print("ATLAS_POLITICS_TRADE structure regions=",state.region_count," routes=",structure.routes.size())
	check(not structure.routes.is_empty(),"enabled Eurasia has trade routes")
	var uses_junction := false
	for route in structure.routes:
		check(state.cities[route.source].is_settlement() and state.cities[route.destination].is_settlement(),"real endpoints")
		for city_id in route.city_path:
			if state.cities[city_id].is_traffic: uses_junction=true
		for city_id in route.city_gold_bonus: check(state.cities[city_id].is_settlement(),"tax recipients exclude junctions")
	check(uses_junction,"trade traverses shared physical graph")
	check(state.rng.state==before_rng,"trade derivation does not consume random stream")
	var sim := Simulation.new(); sim.setup(state)
	check(state.family_trees.has(state.nations[0].family_tree_id),"family system initialized")
	var rejected := false
	var allowed_target := false
	for nation in state.nations:
		if not RulerProfile.offensive_allowed(nation): continue
		for center in range(payload.hierarchy.members.size()):
			var owner := state.cities[center].owner_nation
			if owner==nation.id: continue
			if RegionalStrategy.allows_objective(state,nation.id,center):
				check(DiplomacyAI._ruler_allows_war_objective(state,nation.id,center),"inside business region remains selectable")
				allowed_target=true; continue
			if not rejected:
				check(not sim._start_war_preparation(nation.id,owner,{"objective_city":center}),"outside business region cannot prepare invasion")
				check(not sim._execute_diplomatic_action({"kind":DiplomacyAI.Action.DECLARE_WAR,"a":nation.id,"b":owner,"objective_city":center}),"declaration commit enforces business region")
				rejected=true
			if rejected and allowed_target: break
		if rejected and allowed_target: break
	check(rejected,"outside-region declaration case exercised")
	check(allowed_target,"inside-region target case exercised")
	var definition := Template.encode(state)
	check(Template.validate(definition).is_empty(),"enabled template validates")
	var malformed := Template.decode(definition)
	malformed.simulation_options.trade_enabled="true"
	check(not Template.validate({"format":"world-war-map","version":9,"atlas_payload":Marshalls.raw_to_base64(var_to_bytes(malformed))}).is_empty(),"template rejects non-boolean feature flag")
	malformed=Template.decode(definition); malformed.nations[0].ruler.archetype=999
	check(not Template.validate({"format":"world-war-map","version":9,"atlas_payload":Marshalls.raw_to_base64(var_to_bytes(malformed))}).is_empty(),"template rejects invalid ruler profile")
	var restored := GameState.new(); restored.generate_from_atlas(Template.decode(definition))
	check(restored.trade_enabled and restored.random_ruler_profiles_enabled(),"template retains systems")
	for n in state.nations:
		check(restored.nations[n.id].ruler_name==n.ruler_name and restored.nations[n.id].ruler_archetype==n.ruler_archetype and restored.nations[n.id].ruler_traits==n.ruler_traits,"template retains ruler identity")
	var legacy := payload.duplicate(); legacy.erase("simulation_options")
	var legacy_state := GameState.new(); legacy_state.generate_from_atlas(legacy)
	check(not legacy_state.trade_enabled and not legacy_state.random_ruler_profiles_enabled(),"old template retains military-only semantics")
	check(TradeNetwork.build_structure(legacy_state).routes.is_empty(),"legacy trade remains disabled")
	var successor_sim := Simulation.new(); successor_sim.setup(restored)
	var old_revision := restored.nations[0].ruler_revision
	restored.nations[0].ruler_started_day=-RulerProfile.MAX_REIGN_YEARS*360
	successor_sim._resolve_ruler_successions()
	check(restored.nations[0].ruler_revision>old_revision,"real succession lifecycle enabled")
	check(RegionalStrategy.target_region(restored,0)>=0,"succession retains a valid business region")
	successor_sim.free()
	var timings := []
	for day in range(35):
		var started := Time.get_ticks_usec(); sim._advance_day(); timings.append((Time.get_ticks_usec()-started)/1000.)
		check(state.territory_structure_valid() and state._battle_group_structure_valid(),"live integration day %d"%state.day)
		for nation in state.nations:
			if nation.war_preparation_objective_city>=0:
				check(RegionalStrategy.allows_objective(state,nation.id,nation.war_preparation_objective_city),"live AI preparation respects ruler region")
	for city in state.cities:
		if city.is_traffic: check(city.trade_gold_bonus==0 and city.trade_route_count==0,"junction never gains economic identity")
	FileAccess.open("res://.dbg/atlas-politics-trade.json",FileAccess.WRITE).store_string(JSON.stringify({"seed":state.world_seed,"mask":payload.data.options.settlement_mask,"systems":payload.simulation_options,"day":state.day,"regions":state.region_count,"routes":structure.routes.size(),"daily_compute_ms":timings,"failures":failures},"  "))
	print("ATLAS_POLITICS_TRADE day=",state.day," regions=",state.region_count," routes=",structure.routes.size()," failures=",failures)
	sim.free(); quit(1 if failures else 0)

func test_transit():
	var state := GameState.new(); state.atlas_layout={"model":"fixture"}
	for id in range(3):
		var n := Nation.new(); n.id=id; state.nations.append(n)
	for id in range(4):
		var c := City.new(); c.id=id; c.owner_nation=id if id<3 else -1
		if id==3: c.node_kind=City.NodeKind.TRAFFIC
		state.cities.append(c)
	state.region_ids=PackedInt32Array([0,1,2,-1])
	for pair in [Vector2i(0,3),Vector2i(1,3)]:
		var e := Edge.new(); e.city_a=pair.x; e.city_b=pair.y; e.control_city_id=2
		state.edges.append(e); state.edge_lookup[GameState.edge_key(pair.x,pair.y)]=e
	var tax_cities := TradeNetwork._tax_cities_on_path(state,[0,3,1])
	check(tax_cities==[0,2,1],"third-country traversed district receives tax once, junction receives none")
	check(TradeNetwork.route_region_crossings(state,[0,3,1])==2,"public regional cost explanation includes the traversed district")
	check(TradeNetwork._route_region_crossings_from_ids([0,3,1],TradeNetwork.trade_region_ids(state))==1,"junction does not create a phantom region crossing")
	check(TradeNetwork._allowed_city_mask(state,0,1)[3]==1 and TradeNetwork._allowed_city_mask_for_enemy_union(state,{})[3]==1,"operational and connectivity masks both permit junctions")
