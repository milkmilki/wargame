extends SceneTree
## Utility AI 多种子长跑诊断。手动运行，不纳入每次快速回归。

const SEEDS: Array[int] = [12345, 23456, 34567, 45678]
const DAYS: int = 1095
const FORCE_STRUCTURE_RECONCILE_DAYS: int = 30
const SuccessionAudit = preload("res://tests/succession_audit.gd")


func _init() -> void:
	var total_start := Time.get_ticks_msec()
	var failed := false
	var total_mobilization_armies := 0
	var total_net_captures := 0
	var total_turnovers := 0
	var total_war_declarations := 0
	var total_ai_orders := 0
	var total_redeployment_orders := 0
	var global_max_idle_city_stack := 0
	var global_max_frontier_idle_stack := 0
	var global_max_interior_idle_stack := 0
	var selected_seeds := SEEDS.duplicate()
	var selected_days := DAYS
	var days_override := OS.get_environment(
		"AI_LONGRUN_DAYS"
	)
	if not days_override.is_empty():
		selected_days = maxi(int(days_override), 1)
	var seed_override := OS.get_environment(
		"AI_LONGRUN_SEED"
	)
	if not seed_override.is_empty():
		selected_seeds = [int(seed_override)]
	for world_seed in selected_seeds:
		ResourceForecastRules.profiling_enabled = true
		ResourceForecastRules.reset_profile()
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
		var ai_orders := 0
		var redeployment_orders := 0
		var max_idle_city_stack := 0
		var max_frontier_idle_stack := 0
		var max_interior_idle_stack := 0
		var max_idle_stack_context := ""
		var hostile_stationed_events := 0
		var hostile_stationed_log: Array[String] = []
		var battle_binding_errors := 0
		var first_battle_binding_error := ""
		var territory_invariant_failures := 0
		var first_territory_invariant_failure_day := -1
		var known_fronts := {}
		var cooldown_violations := 0
		var duplicate_bindings := 0
		var pair_violations := 0
		var duplicate_defenses := 0
		var remnant_preparations := 0
		var last_history_size := 0
		var shortage_army_days := 0
		var arrears_nation_months := 0
		var payment_total := 0.0
		var payment_samples := 0
		var payment_min := 1.0
		var court_due := 0
		var court_paid := 0
		var seed_start := Time.get_ticks_msec()
		for _day in range(selected_days):
			if state.winner != -1:
				break
			simulation._advance_day()
			var participants := {}
			for battle in state.battles:
				if battle.finished:
					continue
				for army in battle.side_a + battle.side_b:
					if army.size <= 0 or army.is_city_garrison:
						continue
					if participants.has(army.id) or army.state != Army.State.FIGHTING or army.battle_id != battle.id:
						battle_binding_errors += 1
						if first_battle_binding_error.is_empty():
							first_battle_binding_error = "day=%d army=%d state=%d ref=%d listed=%d" % [state.day, army.id, army.state, army.battle_id, battle.id]
					participants[army.id] = battle.id
			for army in state.armies:
				if army.size > 0 and army.state == Army.State.FIGHTING and (not participants.has(army.id) or participants[army.id] != army.battle_id):
					battle_binding_errors += 1
					if first_battle_binding_error.is_empty():
						first_battle_binding_error = "day=%d army=%d missing active battle ref=%d" % [state.day, army.id, army.battle_id]
			if state.day % Simulation.DAYS_PER_MONTH == 0:
				for nation in state.nations:
					arrears_nation_months += int(nation.unpaid_military_upkeep > 0)
					if nation.alive:
						payment_total += nation.military_payment_ratio
						payment_samples += 1
						payment_min = minf(payment_min, nation.military_payment_ratio)
					court_due += nation.last_court_expense_due
					court_paid += nation.last_court_expense_paid
			var assignments := {}
			var defenses := {}
			for pair_value in state.campaign_pairs.values():
				var pair := pair_value as CoalitionCampaignPair
				if pair.battlefields.size() > CoalitionCampaignPair.MAX_BATTLEFIELDS:
					pair_violations += 1
			for front_value in state.campaign_fronts.values():
				var front := front_value as CoalitionCampaignFront
				if not front.retiring and front.mode == CoalitionCampaignFront.Mode.DEFENSE:
					var key := "%d:%s:%d" % [front.war_id, str(front.participant_nation_ids), front.center_city_id]
					if defenses.has(key):
						duplicate_defenses += 1
					defenses[key] = true
				if not known_fronts.has(front.front_id) and front.mode == CoalitionCampaignFront.Mode.OFFENSE:
					var pair := state.campaign_pairs.get(front.campaign_pair_id) as CoalitionCampaignPair
					var until_day := pair.cooldown_until(front.participant_nation_ids) if pair != null else -1
					if until_day > state.day and until_day - 60 < state.day:
						cooldown_violations += 1
				known_fronts[front.front_id] = true
				for army_id in front.army_assignments:
					if assignments.has(army_id):
						duplicate_bindings += 1
					assignments[army_id] = front.front_id
			for history_index in range(last_history_size, state.diplomatic_history.size()):
				var event: Dictionary = state.diplomatic_history[history_index]
				if int(event.get("action", -1)) == DiplomacyAI.Action.PREPARE_WAR:
					var nation_id := int(event.get("nation_a", -1))
					if nation_id >= 0:
						var integration := RegionalStrategy.integration_report(state, nation_id)
						if int(integration["integrated"]) >= 0.75 * int(integration["total"]) and not integration["complete"]:
							remnant_preparations += 1
			last_history_size = state.diplomatic_history.size()
			if not state.territory_structure_valid():
				territory_invariant_failures += 1
				if first_territory_invariant_failure_day < 0:
					first_territory_invariant_failure_day = state.day
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
			var idle_city_stacks := {}
			for army in state.armies:
				shortage_army_days += int(army.starving)
				var node_city_id := army.current_city_node()
				if (
					army.size > 0
					and node_city_id >= 0
					and node_city_id < state.cities.size()
					and not state.army_may_station(army, node_city_id)
				):
					var hostile_battle := state.battle_by_id(
						army.battle_id
					)
					var valid_hostile_siege := (
						army.state == Army.State.FIGHTING
						and hostile_battle != null
						and not hostile_battle.finished
						and hostile_battle.kind
							== Battle.Kind.SIEGE
						and hostile_battle.city != null
						and hostile_battle.city.id
							== node_city_id
						and hostile_battle.has_army(army)
					)
					if not valid_hostile_siege:
						hostile_stationed_events += 1
						if hostile_stationed_log.size() < 20:
							if OS.get_environment("AI_LONGRUN_DIAGNOSE") == "1":
								var siege: Battle = simulation._siege_battle_of(state.cities[node_city_id])
								print("HOSTILE_DIAGNOSTIC day=%d army=%d on_edge=%s location=%d path=%s action=%d target=%d siege=%d role=%d besiegers=%s defenders=%s" % [state.day, army.id, army.on_edge, army.location_city, str(army.path), army.ai_action, army.ai_target_city, siege.id if siege != null else -1, simulation._siege_role_for_nation(siege, army.owner_nation), str(siege.side_a.map(func(unit: Army): return unit.id)) if siege != null else "[]", str(siege.side_b.map(func(unit: Army): return unit.id)) if siege != null else "[]"])
							hostile_stationed_log.append(
								(
									"day=%d army=%d owner=%d state=%d "
									+ "city=%d city_owner=%d edge=%d-%d "
									+ "progress=%.3f battle=%d"
								) % [
									state.day,
									army.id,
									army.owner_nation,
									army.state,
									node_city_id,
									state.cities[
										node_city_id
									].owner_nation,
									army.move_from,
									army.move_to,
									army.move_progress,
									army.battle_id,
								]
							)
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
							"%d:S%d:A%d:G%d:T%d:%s"
							% [
								stacked_army.max_size,
								stacked_army.state,
								stacked_army.ai_action,
								stacked_army.battle_group_id,
								stacked_army.ai_target_city,
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
				and RegionalStrategy.rivalry(state, finalist_a, finalist_b) > 0.0
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
			DiplomacyAI.Action.RETARGET_WAR_PREPARATION: 0,
		}
		var objective_declarations := 0
		var illegal_regional_declarations := 0
		var region_changes := 0
		var resource_peaces := 0
		var mobilization_armies := 0
		var ultimatums := {"annex": 0, "submit": 0, "refuse": 0, "invalid": 0, "similarity_sum": 0.0}
		for event in state.diplomatic_history:
			if str(event.get("kind", "")) == "regional_strategy_goal_changed":
				region_changes += 1
			if not event.has("action"):
				continue
			var action := int(event["action"])
			if action == DiplomacyAI.Action.ISSUE_ULTIMATUM:
				var report: Dictionary = event["ultimatum"]
				var outcome := int(report["outcome"])
				var label: String = ["refuse", "submit", "annex"][outcome]
				ultimatums[label] += 1
				ultimatums.similarity_sum += float(report.similarity)
				if outcome != UltimatumRules.Outcome.REFUSE and (not report.eligible or float(report.attacker_power) <= 0.0 or not event.get("regional_objective_allowed", false)):
					ultimatums.invalid += 1
				if outcome == UltimatumRules.Outcome.ANNEX and not report.annexation_allowed:
					ultimatums.invalid += 1
			diplomatic_counts[action] = int(diplomatic_counts.get(action, 0)) + 1
			if action == DiplomacyAI.Action.DECLARE_WAR and event.has("objective_city"):
				objective_declarations += 1
				if not bool(event.get("regional_objective_allowed", false)):
					illegal_regional_declarations += 1
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
			# Shared defense and national reserves rally at state centers, not each
			# border fu. Count the owned receiving center for the same defended state.
			for city_id in defended.keys():
				var center_id := state.administrative_center_of(int(city_id))
				if center_id >= 0 and state.cities[center_id].owner_nation == nation.id:
					defended[center_id] = true
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
			var invalid_group_reasons: Array[String] = []
			var armies_by_group := {}
			var army_group_by_id := {}
			for army in state.armies:
				if army.owner_nation != nation.id or army.size <= 0:
					continue
				army_group_by_id[army.id] = army.battle_group_id
				if army.battle_group_id >= 0:
					if (
						state.battle_group_by_id(
							nation.id,
							army.battle_group_id
						) == null
					):
						invalid_group_reasons.append(
							"army%d_missing_group"
							% army.id
						)
						continue
					if not army.is_main_battle_role():
						invalid_group_reasons.append(
							"army%d_group_not_main"
							% army.id
						)
					if army.max_size != GameState.INITIAL_HEAVY_ARMY_SIZE:
						invalid_group_reasons.append(
							"army%d_nonstandard_capacity" % army.id
						)
					armies_by_group[army.battle_group_id] = (
						int(armies_by_group.get(army.battle_group_id, 0)) + 1
					)
				else:
					invalid_group_reasons.append(
						"army%d_ungrouped" % army.id
					)
			for group in nation.battle_groups:
				if (
					int(armies_by_group.get(group.id, 0))
						> BattleGroup.MAX_ARMIES
				):
					invalid_group_reasons.append(
						"group%d_over_capacity" % group.id
					)
			if not invalid_group_reasons.is_empty():
				var mismatch := {
					"nation": nation.id,
					"cities": state.cities_of(nation.id).size(),
					"invalid_groups": invalid_group_reasons,
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
		print("ULTIMATUM_LONGRUN seed=%d days=%d metrics=%s" % [world_seed, state.day, str(ultimatums)])
		if int(ultimatums.invalid) > 0:
			failed = true
		total_mobilization_armies += mobilization_armies
		total_net_captures += captures
		total_turnovers += turnovers
		total_war_declarations += int(
			diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR]
		)
		total_ai_orders += ai_orders
		total_redeployment_orders += redeployment_orders
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
				+ "mobilized=%d resource_peace=%d "
				+ "ally=%d leave=%d "
				+ "war_pairs=%d alliance_pairs=%d capital_armies=%d border_armies=%d "
				+ "defended_cities=%d force_mismatches=%d/%d "
				+ "orders=%d redeploy=%d "
				+ "max_idle_stack=%d/%d/%d stack_at=%s "
				+ "hostile_stationed=%d territory_invalid=%d@%d "
				+ "commit_failures=%d ms=%d"
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
				max_idle_city_stack,
				max_frontier_idle_stack,
				max_interior_idle_stack,
				max_idle_stack_context,
				hostile_stationed_events,
				territory_invariant_failures,
				first_territory_invariant_failure_day,
				simulation.ai_command_commit_failure_total,
				elapsed,
			]
		)
		if not hostile_stationed_log.is_empty():
			print(
				"  hostile_stationed_log=%s"
				% str(hostile_stationed_log)
			)
		if simulation.ai_command_commit_failure_total > 0:
			print(
				"  commit_failure_log=%s"
				% str(simulation.ai_command_commit_failure_log)
			)
		print("  region_changes=%d illegal_regional_declarations=%d regional_queries=%d" % [
			region_changes, illegal_regional_declarations, RegionalStrategy.query_count])
		print("  INTEGRATION_CAMPAIGN_AUDIT remnant_preparations=%d cooldown_violations=%d duplicate_bindings=%d" % [
			remnant_preparations, cooldown_violations, duplicate_bindings])
		print("  PAIR_CAMPAIGN_AUDIT overfull_pairs=%d duplicate_defenses=%d" % [pair_violations, duplicate_defenses])
		print("  RESOURCE_AUDIT shortage_army_days=%d arrears_nation_months=%d court_due=%d court_paid=%d payment_mean=%.4f payment_min=%.4f forecast=%s" % [shortage_army_days, arrears_nation_months, court_due, court_paid, payment_total / maxi(payment_samples, 1), payment_min, str(ResourceForecastRules.profile())])
		print("  BATTLE_BINDING_AUDIT errors=%d first=%s" % [battle_binding_errors, first_battle_binding_error])
		var succession := SuccessionAudit.inspect(state)
		print("  SUCCESSION_AUDIT %s" % str(succession))
		if (
			ordered == 0
			or not succession.errors.is_empty()
			or cooldown_violations > 0 or duplicate_bindings > 0 or pair_violations > 0 or duplicate_defenses > 0
			or illegal_regional_declarations > 0
			or invalid > 0
			or invalid_finance > 0
			or eliminated_war_relations > 0
			or terminal_alliance_lock
			or hostile_stationed_events > 0
			or battle_binding_errors > 0
			or territory_invariant_failures > 0
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
	if total_turnovers == 0 or total_war_declarations == 0:
		failed = true
	print(
		(
			"total_net_captures=%d total_turnovers=%d "
			+ "total_wars=%d total_mobilized=%d "
			+ "total_orders=%d total_redeploy=%d "
			+ "max_idle_stack=%d/%d/%d"
		)
		% [
			total_net_captures,
			total_turnovers,
			total_war_declarations,
			total_mobilization_armies,
			total_ai_orders,
			total_redeployment_orders,
			global_max_idle_city_stack,
			global_max_frontier_idle_stack,
			global_max_interior_idle_stack,
		]
	)
	var total_elapsed_ms := Time.get_ticks_msec() - total_start
	print("total_ms=%d" % total_elapsed_ms)
	quit(1 if failed else 0)
