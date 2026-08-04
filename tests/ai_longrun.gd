extends SceneTree
## Utility AI 多种子长跑诊断。手动运行，不纳入每次快速回归。

const SEEDS: Array[int] = [12345, 23456, 34567, 45678]
const DAYS: int = 1095
const FORCE_STRUCTURE_RECONCILE_DAYS: int = 30


func _init() -> void:
	var total_start := Time.get_ticks_msec()
	var failed := false
	var total_mobilization_armies := 0
	var total_net_captures := 0
	var total_turnovers := 0
	var total_war_declarations := 0
	var total_offensives := 0
	var total_full_preparation_offensives := 0
	var total_multi_target_preparations := 0
	var global_max_parallel_targets := 0
	var total_post_capture_attacks := 0
	var total_post_capture_edge_holds := 0
	var total_post_capture_city_holds := 0
	var total_ai_orders := 0
	var total_redeployment_orders := 0
	var total_role_deployment_orders := 0
	var global_max_idle_city_stack := 0
	var global_max_frontier_idle_stack := 0
	var global_max_interior_idle_stack := 0
	var legacy_capture_fort := (
		OS.get_environment("AI_LONGRUN_LEGACY_CAPTURE_FORT")
			== "1"
	)
	var selected_seeds := SEEDS.duplicate()
	var seed_override := OS.get_environment(
		"AI_LONGRUN_SEED"
	)
	if not seed_override.is_empty():
		selected_seeds = [int(seed_override)]
	for world_seed in selected_seeds:
		var state := GameState.new()
		state.generate_world(world_seed)
		var simulation := Simulation.new()
		root.add_child(simulation)
		simulation.setup(state)
		var initial_owners: Array[int] = []
		for city in state.cities:
			initial_owners.append(city.owner_nation)
		var current_owners := initial_owners.duplicate()
		var force_structure_last_change_day := {}
		for nation in state.nations:
			force_structure_last_change_day[nation.id] = 0
		var turnovers := 0
		var offensive_events := {}
		var full_preparation_events := {}
		var multi_target_preparations := {}
		var max_parallel_targets := 0
		var post_capture_attacks := 0
		var post_capture_edge_holds := 0
		var post_capture_city_holds := 0
		var ai_orders := 0
		var redeployment_orders := 0
		var role_deployment_orders := 0
		var max_idle_city_stack := 0
		var max_frontier_idle_stack := 0
		var max_interior_idle_stack := 0
		var max_idle_stack_context := ""
		var hostile_stationed_events := 0
		var seed_start := Time.get_ticks_msec()
		for _day in range(DAYS):
			if state.winner != -1:
				break
			simulation._advance_day()
			var reverted_legacy_fort := false
			for city in state.cities:
				if city.owner_nation == current_owners[city.id]:
					continue
				var previous_owner: int = current_owners[city.id]
				turnovers += 1
				current_owners[city.id] = city.owner_nation
				force_structure_last_change_day[previous_owner] = (
					state.day
				)
				force_structure_last_change_day[city.owner_nation] = (
					state.day
				)
				if legacy_capture_fort:
					city.fort_strength = 10
					city.fort_last_capture_day = -1
					reverted_legacy_fort = true
			if reverted_legacy_fort:
				state.fortification_revision += 1
			for nation in state.nations:
				var parallel_targets := (
					nation.campaign_preparation_targets.size()
				)
				max_parallel_targets = maxi(
					max_parallel_targets,
					parallel_targets
				)
				if (
					parallel_targets > 1
					and nation.campaign_preparation_started_day >= 0
				):
					multi_target_preparations[
						"%d:%d" % [
							nation.id,
							nation.campaign_preparation_started_day,
						]
					] = true
			for event in state.campaign_visual_events:
				var event_key := "%d:%d:%d:%d" % [
					int(event["start_day"]),
					int(event["nation_id"]),
					int(event["target_city"]),
					int(event["wave"]),
				]
				offensive_events[event_key] = true
			var idle_city_stacks := {}
			for army in state.armies:
				if (
					army.size > 0
					and not army.on_edge
					and army.location_city >= 0
					and army.location_city
						< state.cities.size()
					and army.state
						!= Army.State.FIGHTING
					and not state.has_military_access(
						army.owner_nation,
						state.cities[
							army.location_city
						].owner_nation
					)
				):
					hostile_stationed_events += 1
				if (
					army.size > 0
					and army.location_city >= 0
					and army.state in [
						Army.State.IDLE,
						Army.State.RECOVERING,
					]
				):
					var stack_key := (
						army.owner_nation
							* state.cities.size()
						+ army.location_city
					)
					idle_city_stacks[stack_key] = (
						int(idle_city_stacks.get(stack_key, 0))
						+ 1
					)
				if army.ai_order_created_day == state.day:
					ai_orders += 1
					if army.ai_action in [
						ActionCandidate.Kind.HOLD,
						ActionCandidate.Kind.REINFORCE,
						ActionCandidate.Kind.MERGE,
						ActionCandidate.Kind.RETREAT,
					]:
						redeployment_orders += 1
					if army.ai_order_reason.begins_with(
						"填线部署"
					):
						role_deployment_orders += 1
				if (
					army.ai_order_created_day == state.day
					and army.ai_order_reason.contains(
						"满准备攻势第二阶段"
					)
				):
					if army.ai_action == ActionCandidate.Kind.ATTACK:
						post_capture_attacks += 1
					elif army.ai_order_reason.contains(
						"前出驻守"
					):
						post_capture_edge_holds += 1
					else:
						post_capture_city_holds += 1
				if (
					army.ai_order_created_day == state.day
					and army.ai_action
						== ActionCandidate.Kind.ATTACK
					and is_equal_approx(
						army.offensive_attack_multiplier,
						Simulation.OFFENSIVE_BONUS_MAX_MULTIPLIER
					)
				):
					full_preparation_events[
						"%d:%d" % [
							state.day,
							army.owner_nation,
						]
					] = true
			for stack_key_value in idle_city_stacks:
				var stack_key := int(stack_key_value)
				var stack_size := int(
					idle_city_stacks[stack_key]
				)
				var owner_nation := int(
					stack_key / state.cities.size()
				)
				var city_id := (
					stack_key % state.cities.size()
				)
				var frontier := false
				for neighbor in state.neighbors(city_id):
					if (
						state.cities[neighbor].owner_nation
							!= owner_nation
					):
						frontier = true
						break
				if stack_size > max_idle_city_stack:
					max_idle_city_stack = stack_size
					var stack_armies: Array[String] = []
					for stacked_army in state.armies:
						if (
							stacked_army.owner_nation
								!= owner_nation
							or stacked_army.location_city
								!= city_id
							or stacked_army.state not in [
								Army.State.IDLE,
								Army.State.RECOVERING,
							]
						):
							continue
						stack_armies.append(
							"%d:%d:%d:%s"
							% [
								stacked_army.max_size,
								stacked_army.state,
								stacked_army.ai_action,
								stacked_army.ai_order_reason,
							]
						)
					max_idle_stack_context = (
						"day=%d nation=%d city=%d frontier=%d armies=%s"
						% [
							state.day,
							owner_nation,
							city_id,
							1 if frontier else 0,
							str(stack_armies),
						]
					)
				if frontier:
					max_frontier_idle_stack = maxi(
						max_frontier_idle_stack,
						stack_size
					)
				else:
					max_interior_idle_stack = maxi(
						max_interior_idle_stack,
						stack_size
					)
		var captures := 0
		for city in state.cities:
			if city.owner_nation != initial_owners[city.id]:
				captures += 1
		var alive := 0
		var alive_nations: Array[int] = []
		var eliminated_war_relations := 0
		for nation in state.nations:
			if nation.alive:
				alive += 1
				alive_nations.append(nation.id)
			if state.cities_of(nation.id).is_empty():
				for other in state.nations:
					if (
						other.id != nation.id
						and state.is_enemy(nation.id, other.id)
					):
						eliminated_war_relations += 1
		var terminal_alliance_lock := false
		if alive_nations.size() == 2:
			var finalist_a := alive_nations[0]
			var finalist_b := alive_nations[1]
			terminal_alliance_lock = (
				state.is_allied(finalist_a, finalist_b)
				and state.day
					- state.relation_since(
						finalist_a,
						finalist_b
					)
					>= DiplomacyAI.MIN_ALLIANCE_DAYS
			)
		var ordered := 0
		var invalid := 0
		var troops := 0
		var starving := 0
		for army in state.armies:
			troops += army.size
			if army.starving:
				starving += 1
			if army.ai_order_created_day >= 0:
				ordered += 1
			if army.size <= 0 or army.owner_nation < 0 or army.owner_nation >= state.nations.size():
				invalid += 1
		var manpower := 0
		var food := 0
		var invalid_finance := 0
		for nation in state.nations:
			manpower += nation.manpower_pool
			food += nation.granary_food
			if (
				nation.treasury_gold < 0
				or nation.last_military_upkeep < 0
				or nation.unpaid_military_upkeep < 0
				or nation.unpaid_military_upkeep
					> nation.last_military_upkeep
				or nation.military_payment_ratio < 0.0
				or nation.military_payment_ratio > 1.0
			):
				invalid_finance += 1
		var diplomatic_counts := {
			DiplomacyAI.Action.MAKE_PEACE: 0,
			DiplomacyAI.Action.DECLARE_WAR: 0,
			DiplomacyAI.Action.FORM_ALLIANCE: 0,
			DiplomacyAI.Action.LEAVE_ALLIANCE: 0,
			DiplomacyAI.Action.PREPARE_WAR: 0,
			DiplomacyAI.Action.CANCEL_WAR_PREPARATION: 0,
		}
		var objective_declarations := 0
		var resource_peaces := 0
		var mobilization_armies := 0
		for event in state.diplomatic_history:
			var action := int(event["action"])
			diplomatic_counts[action] = int(diplomatic_counts.get(action, 0)) + 1
			if action == DiplomacyAI.Action.DECLARE_WAR and event.has("objective_city"):
				objective_declarations += 1
				mobilization_armies += int(event.get("mobilization_armies", 0))
			if action == DiplomacyAI.Action.MAKE_PEACE:
				var reason := str(event["reason"])
				if (
					reason.contains("国库")
					or reason.contains("粮草")
					or reason.contains("人力")
				):
					resource_peaces += 1
		var war_pairs := 0
		var alliance_pairs := 0
		for nation_a in range(state.nations.size()):
			for nation_b in range(nation_a + 1, state.nations.size()):
				if state.is_enemy(nation_a, nation_b):
					war_pairs += 1
				elif state.is_allied(nation_a, nation_b):
					alliance_pairs += 1
		var capital_armies := 0
		var border_armies := 0
		var defended_cities_total := 0
		var force_structure_mismatches: Array[Dictionary] = []
		var persistent_force_structure_mismatches: Array[Dictionary] = []
		for nation in state.nations:
			if not nation.alive:
				continue
			var snapshot := StrategicMapSnapshot.build(
				AiWorldView.build(state, nation.id)
			)
			var defended := {}
			for city_id in snapshot.frontier_cities:
				defended[city_id] = true
			for city_id in snapshot.potential_frontier_cities:
				defended[city_id] = true
			defended_cities_total += defended.size()
			for army in state.armies:
				if army.owner_nation != nation.id or army.size <= 0:
					continue
				if (
					army.state in [Army.State.IDLE, Army.State.RECOVERING]
					and army.location_city == nation.capital_city_id
				):
					capital_armies += 1
				var committed_to_border := (
					army.state in [Army.State.IDLE, Army.State.RECOVERING]
					and defended.has(army.location_city)
				) or (
					army.state == Army.State.HOLDING
					and (
						defended.has(army.move_from)
						or defended.has(army.move_to)
					)
				) or (
					army.state == Army.State.MOVING
					and defended.has(army.ai_target_city)
				)
				if army.state == Army.State.FIGHTING:
					var battle := state.battle_by_id(army.battle_id)
					committed_to_border = (
						committed_to_border
						or (
							battle != null
							and battle.city != null
							and defended.has(battle.city.id)
						)
						or (
							battle != null
							and battle.edge != null
							and (
								defended.has(battle.edge.city_a)
								or defended.has(battle.edge.city_b)
							)
						)
					)
				if committed_to_border:
					border_armies += 1
			var light_armies := 0
			var heavy_armies := 0
			for army in state.armies:
				if army.owner_nation != nation.id or army.size <= 0:
					continue
				if army.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE:
					light_armies += 1
				elif army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE:
					heavy_armies += 1
			var target_light := state.target_light_army_count(nation.id)
			var target_heavy := state.target_heavy_army_count(nation.id)
			if light_armies != target_light or heavy_armies != target_heavy:
				var mismatch := {
					"nation": nation.id,
					"cities": state.cities_of(nation.id).size(),
					"light": light_armies,
					"target_light": target_light,
					"heavy": heavy_armies,
					"target_heavy": target_heavy,
					"days_since_city_change": (
						state.day - int(
							force_structure_last_change_day.get(
								nation.id,
								0
							)
						)
					),
				}
				force_structure_mismatches.append(mismatch)
				if (
					int(mismatch["days_since_city_change"])
						> FORCE_STRUCTURE_RECONCILE_DAYS
				):
					persistent_force_structure_mismatches.append(
						mismatch
					)
		var elapsed := Time.get_ticks_msec() - seed_start
		total_mobilization_armies += mobilization_armies
		total_net_captures += captures
		total_turnovers += turnovers
		total_war_declarations += int(
			diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR]
		)
		total_offensives += offensive_events.size()
		total_full_preparation_offensives += (
			full_preparation_events.size()
		)
		total_multi_target_preparations += (
			multi_target_preparations.size()
		)
		global_max_parallel_targets = maxi(
			global_max_parallel_targets,
			max_parallel_targets
		)
		total_post_capture_attacks += post_capture_attacks
		total_post_capture_edge_holds += post_capture_edge_holds
		total_post_capture_city_holds += post_capture_city_holds
		total_ai_orders += ai_orders
		total_redeployment_orders += redeployment_orders
		total_role_deployment_orders += role_deployment_orders
		global_max_idle_city_stack = maxi(
			global_max_idle_city_stack,
			max_idle_city_stack
		)
		global_max_frontier_idle_stack = maxi(
			global_max_frontier_idle_stack,
			max_frontier_idle_stack
		)
		global_max_interior_idle_stack = maxi(
			global_max_interior_idle_stack,
			max_interior_idle_stack
		)
		print(
			(
				"seed=%d day=%d alive=%d eliminated_wars=%d terminal_alliance_lock=%d "
				+ "armies=%d troops=%d manpower=%d food=%d finance_invalid=%d "
				+ "starving=%d net_captures=%d turnovers=%d ordered=%d invalid=%d "
				+ "peace=%d prepare=%d cancel_prepare=%d war=%d objectives=%d "
				+ "offensives=%d full_prep=%d multi_prep=%d max_parallel=%d "
				+ "phase2=%d/%d/%d "
				+ "mobilized=%d resource_peace=%d "
				+ "ally=%d leave=%d "
				+ "war_pairs=%d alliance_pairs=%d capital_armies=%d border_armies=%d "
				+ "defended_cities=%d force_mismatches=%d/%d "
				+ "orders=%d redeploy=%d role_deploy=%d "
				+ "max_idle_stack=%d/%d/%d stack_at=%s "
				+ "hostile_stationed=%d commit_failures=%d ms=%d"
			)
			% [
				world_seed,
				state.day,
				alive,
				eliminated_war_relations,
				1 if terminal_alliance_lock else 0,
				state.armies.size(),
				troops,
				manpower,
				food,
				invalid_finance,
				starving,
				captures,
				turnovers,
				ordered,
				invalid,
				diplomatic_counts[DiplomacyAI.Action.MAKE_PEACE],
				diplomatic_counts[DiplomacyAI.Action.PREPARE_WAR],
				diplomatic_counts[DiplomacyAI.Action.CANCEL_WAR_PREPARATION],
				diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR],
				objective_declarations,
				offensive_events.size(),
				full_preparation_events.size(),
				multi_target_preparations.size(),
				max_parallel_targets,
				post_capture_attacks,
				post_capture_edge_holds,
				post_capture_city_holds,
				mobilization_armies,
				resource_peaces,
				diplomatic_counts[DiplomacyAI.Action.FORM_ALLIANCE],
				diplomatic_counts[DiplomacyAI.Action.LEAVE_ALLIANCE],
				war_pairs,
				alliance_pairs,
				capital_armies,
				border_armies,
				defended_cities_total,
				force_structure_mismatches.size(),
				persistent_force_structure_mismatches.size(),
				ai_orders,
				redeployment_orders,
				role_deployment_orders,
				max_idle_city_stack,
				max_frontier_idle_stack,
				max_interior_idle_stack,
				max_idle_stack_context,
				hostile_stationed_events,
				simulation.ai_command_commit_failure_total,
				elapsed,
			]
		)
		if simulation.ai_command_commit_failure_total > 0:
			print(
				"  commit_failure_log=%s"
				% str(simulation.ai_command_commit_failure_log)
			)
		if (
			ordered == 0
			or invalid > 0
			or invalid_finance > 0
			or eliminated_war_relations > 0
			or terminal_alliance_lock
			or hostile_stationed_events > 0
			or simulation.ai_command_commit_failure_total > 0
			or food <= 0
			or (
				defended_cities_total > 0
				and border_armies == 0
			)
			or not persistent_force_structure_mismatches.is_empty()
			or state.diplomatic_history.is_empty()
			or objective_declarations
				!= int(diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR])
			or int(diplomatic_counts[DiplomacyAI.Action.PREPARE_WAR])
				< int(diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR])
		):
			failed = true
		if not force_structure_mismatches.is_empty():
			print(
				"  force_structure_mismatches=%s"
					% str(force_structure_mismatches)
			)
		simulation.free()
	if (
		total_turnovers == 0
		or total_war_declarations == 0
		or total_offensives <= total_war_declarations
	):
		failed = true
	print(
		(
			"mode=%s total_net_captures=%d total_turnovers=%d "
			+ "total_wars=%d total_offensives=%d total_full_prep=%d "
			+ "total_multi_prep=%d max_parallel=%d "
			+ "total_phase2=%d/%d/%d total_mobilized=%d "
			+ "total_orders=%d total_redeploy=%d "
			+ "total_role_deploy=%d max_idle_stack=%d/%d/%d"
		)
		% [
			"legacy_fort" if legacy_capture_fort else "recovery_fort",
			total_net_captures,
			total_turnovers,
			total_war_declarations,
			total_offensives,
			total_full_preparation_offensives,
			total_multi_target_preparations,
			global_max_parallel_targets,
			total_post_capture_attacks,
			total_post_capture_edge_holds,
			total_post_capture_city_holds,
			total_mobilization_armies,
			total_ai_orders,
			total_redeployment_orders,
			total_role_deployment_orders,
			global_max_idle_city_stack,
			global_max_frontier_idle_stack,
			global_max_interior_idle_stack,
		]
	)
	var total_elapsed_ms := Time.get_ticks_msec() - total_start
	print("total_ms=%d" % total_elapsed_ms)
	quit(1 if failed else 0)
