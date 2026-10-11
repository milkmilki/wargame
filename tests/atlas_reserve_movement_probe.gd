extends SceneTree
## Manual before/after probe. Supply external frozen state and codec via CLI.
## Timing excludes sampling, audit and snapshot hashing; headless only.
var options := {}
var rows: Array = []
var errors: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			options[arg.get_slice("=", 0).trim_prefix("--")] = arg.substr(arg.find("=") + 1)
	call_deferred("run")

func sample(state: GameState) -> Dictionary:
	var moving := 0; var reserve_moving := 0; var armies := 0
	for army in state.armies:
		if army.size <= 0 or army.is_city_garrison: continue
		armies += 1
		if army.state == Army.State.MOVING:
			moving += 1
			if army.ai_order_reason.begins_with("国家预备队"): reserve_moving += 1
	return {"day": state.day, "armies": armies, "moving": moving, "reserve_moving": reserve_moving}

func audit(state: GameState) -> void:
	if not state.territory_structure_valid(): errors.append([state.day, "territory"])
	if not state._battle_group_structure_valid(): errors.append([state.day, "battle_groups"])
	if not state.suzerainty_structure_valid(): errors.append([state.day, "suzerainty"])
	var occupancy := {}; var ids := {}; var active_wars := {}
	for war_id in state.war_relation_ids.values(): active_wars[int(war_id)] = true
	for army in state.armies:
		if ids.has(army.id): errors.append([state.day, "duplicate_army", army.id])
		ids[army.id] = true
		if army.size < 0 or army.size > army.max_size: errors.append([state.day, "army_size", army.id])
		if army.size <= 0: continue
		if army.owner_nation < 0 or army.owner_nation >= state.nations.size():
			errors.append([state.day, "army_owner", army.id]); continue
		var owner := state.nations[army.owner_nation]
		if not owner.alive and not owner.succession_identity: errors.append([state.day, "dead_army_owner", army.id])
		if army.location_city < 0 or army.location_city >= state.cities.size(): errors.append([state.day, "army_location", army.id])
		if army.on_edge:
			var key := GameState.edge_key(army.move_from, army.move_to)
			occupancy[key] = int(occupancy.get(key, 0)) + 1
			if state.edge_of(army.move_from, army.move_to) == null or not is_finite(army.move_progress) or army.move_progress < 0.0 or army.move_progress > 1.00001:
				errors.append([state.day, "army_road", army.id])
		if army.battle_id >= 0:
			var battle := state.battle_by_id(army.battle_id)
			if battle == null or battle.finished or not battle.has_army(army): errors.append([state.day, "battle_binding", army.id])
		if army.campaign_front_id >= 0 and state.campaign_front(army.campaign_front_id) == null:
			errors.append([state.day, "front_binding", army.id])
		if army.campaign_war_id >= 0 and not active_wars.has(army.campaign_war_id):
			errors.append([state.day, "war_binding", army.id])
	for edge in state.edges:
		if edge.passing_count != int(occupancy.get(GameState.edge_key(edge.city_a, edge.city_b), 0)):
			errors.append([state.day, "road_occupancy", edge.city_a, edge.city_b])
	for nation in state.nations:
		if nation.treasury_gold < 0 or nation.manpower_pool < 0 or nation.granary_food < 0:
			errors.append([state.day, "stocks", nation.id])

func run() -> void:
	var sim: Simulation
	var script_path: String = options.get("simulation", "res://scripts/simulation/simulation.gd")
	var peace: bool = options.get("peace", "false") == "true"
	if peace or options.get("fresh", "false") == "true":
		var payload: Dictionary = FileAccess.open(options["payload"], FileAccess.READ).get_var(false)
		payload.simulation_options = {"trade_enabled": true, "rulers_enabled": true}
		var state := GameState.new(); state.generate_from_atlas(payload)
		sim = load(script_path).new(); sim.setup(state)
	else:
		sim = load(options["codec"]).new().restore(options["snapshot"], script_path)
	var initial := sample(sim.state)
	var days := int(options.get("days", "35"))
	for index in range(days):
		var started := Time.get_ticks_usec()
		sim._advance_day(false)
		var elapsed := Time.get_ticks_usec() - started
		var row := sample(sim.state); row.compute_us = elapsed; rows.append(row)
		audit(sim.state)
		if index % 30 == 0:
			print("RESERVE_PROBE_PROGRESS day=", sim.state.day)
			await process_frame
	var output := {"pid": OS.get_process_id(), "seed": sim.state.world_seed,
		"mask": sim.state.atlas_layout.data.options.settlement_mask,
		"trade": sim.state.trade_enabled, "rulers": sim.state.random_ruler_profiles_enabled(),
		"script": script_path, "peace": peace, "initial": initial, "rows": rows, "errors": errors,
		"scope": "Headless compute. Controlled peace disables monthly diplomacy only, not ruler events."}
	if "observed_orders" in sim: output.orders = sim.get("observed_orders")
	FileAccess.open(options["output"], FileAccess.WRITE).store_string(JSON.stringify(output, "  "))
	print("RESERVE_PROBE_DONE day=", sim.state.day, " errors=", errors.size())
	sim.free(); quit(0 if errors.is_empty() else 1)
