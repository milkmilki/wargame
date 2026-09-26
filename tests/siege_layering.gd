extends SceneTree


func _army(id: int, owner: int, size: int, city_id: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner
	army.size = size
	army.max_size = maxi(size, 15000)
	army.attack = 10
	army.defense = 10
	army.morale = 2.0
	army.max_morale = 2.0
	army.state = Army.State.IDLE
	army.location_city = city_id
	army.move_from = city_id
	return army


func _fixture(seed: int) -> Dictionary:
	var state := GameState.new()
	state.generate_grid_world(seed)
	var center_id := int(state.administrative_center_city_ids[0])
	var center := state.cities[center_id]
	var defender_id := center.owner_nation
	var attacker_id := (defender_id + 1) % state.nations.size()
	state.set_diplomatic_relation(
		attacker_id,
		defender_id,
		GameState.DiplomaticRelation.WAR
	)
	var origin_id := int(state.neighbors(center_id)[0])
	var edge := state.edge_of(origin_id, center_id)
	state.armies.clear()
	state.battles.clear()
	return {
		"state": state,
		"center": center,
		"center_id": center_id,
		"origin_id": origin_id,
		"edge": edge,
		"attacker_id": attacker_id,
		"defender_id": defender_id,
	}


func _arriving_attacker(data: Dictionary, id: int, size: int) -> Army:
	var army := _army(
		id,
		int(data["attacker_id"]),
		size,
		int(data["origin_id"])
	)
	army.state = Army.State.MOVING
	army.move_to = int(data["center_id"])
	army.move_progress = 1.0
	return army


func _init() -> void:
	var valid := true
	valid = valid and MapRenderer.campaign_phase_text(
		AdministrativeCampaignPlan.Mode.OFFENSE,
		AdministrativeCampaignPlan.Phase.RAID_FU
	) == "进攻·大营分遣占府"
	valid = valid and MapRenderer.campaign_phase_text(
		AdministrativeCampaignPlan.Mode.DEFENSE,
		AdministrativeCampaignPlan.Phase.HOLD_AND_REINFORCE
	) == "防守·驻守并等待增援"
	valid = valid and MapRenderer.campaign_phase_text(
		AdministrativeCampaignPlan.Mode.DEFENSE,
		AdministrativeCampaignPlan.Phase.SORTIE
	) == "防守·出城迎击敌军"

	# 驻城野战军先单独交战，虚拟守军本轮不得出现或受损。
	var screened := _fixture(95201)
	var screened_state: GameState = screened["state"]
	var screened_center: City = screened["center"]
	var attacker := _arriving_attacker(screened, 9501, 45000)
	var defender := _army(
		9502,
		int(screened["defender_id"]),
		15000,
		int(screened["center_id"])
	)
	screened_state.armies.append_array([attacker, defender])
	var screened_sim := Simulation.new()
	screened_sim.setup(screened_state)
	var garrison_before := screened_center.garrison_manpower
	screened_sim._start_or_join_siege(
		attacker, screened_center, screened["edge"]
	)
	var screened_siege := screened_sim._siege_battle_of(screened_center)
	valid = valid and screened_siege != null
	if screened_siege != null:
		valid = valid and screened_siege.uses_field_combat_rules()
		valid = valid and (
			Combat.combat_frontage(screened_siege)
				== Combat.SIEGE_FIELD_FRONTAGE
		)
		valid = valid and screened_siege.holding_side == 2
		var detail_sections := MapRenderer.city_detail_sections(
			screened_state, int(screened["center_id"])
		)
		var military_text := ""
		for section in detail_sections:
			if str(section.get("title", "")) != "军事":
				continue
			for line in section.get("lines", []):
				military_text += "%s\n" % str(line)
		valid = valid and military_text.contains("当前行动：州治野战")
		valid = valid and military_text.contains("城下可战兵力")
		valid = valid and military_text.contains("本州已调兵力")
		valid = valid and not military_text.contains("阶段")
		valid = valid and not military_text.contains("到场C")
		var snapshot := NativeSnapshotBuilder.build(screened_state)
		valid = valid and int(
			(snapshot["battles"] as Dictionary)[
				"uses_field_combat_rules"
			][0]
		) == 1
		Combat.clear_battle_log()
		Combat.battle_log_enabled = true
		screened_sim._advance_siege(screened_siege, 0, 95201)
		var replay := CombatLog.replay_records(Combat.battle_log)
		Combat.battle_log_enabled = false
		valid = valid and bool(replay.get("ok", false))
		valid = valid and bool((Combat.battle_log[0] as Dictionary)[
			"battle_context"
		].get("uses_field_combat_rules", false))
		valid = valid and screened_center.garrison_manpower == garrison_before
		for member in screened_siege.side_b:
			valid = valid and not member.is_city_garrison
	screened_sim.free()

	# 府城同样使用统一的 50000 城下野战宽度，不读取入口道路容量。
	var fu_id := -1
	for member_id in screened_state.administrative_members(
		int(screened["center_id"])
	):
		if member_id != int(screened["center_id"]):
			fu_id = member_id
			break
	if fu_id >= 0:
		var fu_battle := Battle.new()
		fu_battle.kind = Battle.Kind.SIEGE
		fu_battle.city = screened_state.cities[fu_id]
		fu_battle.edge = Edge.new()
		fu_battle.edge.max_manpower = Edge.TERRAIN_LOW_MANPOWER
		fu_battle.side_a.append(_army(
			9503, int(screened["attacker_id"]), 15000, fu_id
		))
		fu_battle.side_b.append(_army(
			9504, int(screened["defender_id"]), 15000, fu_id
		))
		valid = valid and fu_battle.uses_field_combat_rules()
		valid = valid and (
			Combat.combat_frontage(fu_battle)
				== Combat.SIEGE_FIELD_FRONTAGE
		)
	else:
		valid = false

	# 到场兵力低于 R 时只封锁，不能消耗虚拟守军。
	var blocked := _fixture(95202)
	var blocked_state: GameState = blocked["state"]
	var blocked_center: City = blocked["center"]
	var weak_attacker := _arriving_attacker(blocked, 9511, 15000)
	var recovering := _army(
		9512,
		int(blocked["defender_id"]),
		3000,
		int(blocked["center_id"])
	)
	recovering.state = Army.State.RECOVERING
	blocked_state.armies.append_array([weak_attacker, recovering])
	var blocked_sim := Simulation.new()
	blocked_sim.setup(blocked_state)
	var blocked_garrison_before := blocked_center.garrison_manpower
	blocked_sim._start_or_join_siege(
		weak_attacker, blocked_center, blocked["edge"]
	)
	var blocked_siege := blocked_sim._siege_battle_of(blocked_center)
	valid = valid and blocked_siege != null
	if blocked_siege != null:
		valid = valid and recovering.state == Army.State.RETREATING
		valid = valid and not blocked_siege.has_army(recovering)
		valid = valid and not blocked_siege.uses_field_combat_rules()
		valid = valid and (
			Combat.combat_frontage(blocked_siege)
				== Combat.SIEGE_FRONTAGE
		)
		blocked_sim._advance_siege(blocked_siege, 0, 95202)
		valid = valid and not blocked_siege.finished
		valid = valid and blocked_center.garrison_manpower == blocked_garrison_before
		valid = valid and blocked_siege.side_b.is_empty()
	blocked_sim.free()

	# 围城中途进入的援军先触发解围野战，不能与虚拟守军同轮参战。
	var relieved := _fixture(95203)
	var relieved_state: GameState = relieved["state"]
	var relieved_center: City = relieved["center"]
	var strong_attacker := _arriving_attacker(relieved, 9521, 45000)
	relieved_state.armies.append(strong_attacker)
	var relieved_sim := Simulation.new()
	relieved_sim.setup(relieved_state)
	relieved_sim._start_or_join_siege(
		strong_attacker, relieved_center, relieved["edge"]
	)
	var relieved_siege := relieved_sim._siege_battle_of(relieved_center)
	var relief := _army(
		9522,
		int(relieved["defender_id"]),
		15000,
		int(relieved["center_id"])
	)
	relieved_state.armies.append(relief)
	var relieved_garrison_before := relieved_center.garrison_manpower
	relieved_center.food_storage = 100
	if relieved_siege != null:
		relieved_sim._advance_siege(relieved_siege, 0, 95203)
		valid = valid and relieved_siege.uses_field_combat_rules()
		valid = valid and relieved_center.garrison_manpower == relieved_garrison_before
		relieved_sim._drain_siege_food()
		valid = valid and relieved_center.food_storage == 99
		for member in relieved_siege.side_b:
			valid = valid and not member.is_city_garrison
	else:
		valid = false
	relieved_sim.free()

	# 围城外壳中的真实军队败北仍按野战规则保留当前兵力的20%。
	var routed := _fixture(95204)
	var routed_state: GameState = routed["state"]
	var routed_sim := Simulation.new()
	routed_sim.setup(routed_state)
	var routed_attacker := _army(
		9531,
		int(routed["attacker_id"]),
		45000,
		int(routed["origin_id"])
	)
	var routed_defender := _army(
		9532,
		int(routed["defender_id"]),
		10000,
		int(routed["center_id"])
	)
	routed_attacker.state = Army.State.FIGHTING
	routed_defender.state = Army.State.FIGHTING
	routed_state.armies.append_array([routed_attacker, routed_defender])
	var routed_siege := routed_state.new_battle(Battle.Kind.SIEGE)
	routed_siege.city = routed["center"]
	routed_siege.edge = routed["edge"]
	routed_siege.siege_attacker_nation = int(routed["attacker_id"])
	routed_siege.side_a.append(routed_attacker)
	routed_siege.side_b.append(routed_defender)
	routed_siege.side_b_defends_city = true
	routed_siege.winner_side = 1
	routed_siege.finished = true
	var routed_garrison_before := (routed["center"] as City).garrison_manpower
	routed_sim._finish_siege_field_engagement(routed_siege)
	valid = valid and routed_defender.size == 2000
	valid = valid and routed_siege.field_rout_attrition_multiplier == 0.20
	valid = valid and (
		(routed["center"] as City).garrison_manpower
			== routed_garrison_before
	)
	routed_sim._advance_siege(routed_siege, 0, 95204)
	valid = valid and (
		(routed["center"] as City).garrison_manpower
			< routed_garrison_before
	)
	routed_sim.free()

	if valid:
		print("SIEGE_LAYERING_OK")
		quit(0)
		return
	push_error("SIEGE_LAYERING_FAILED")
	quit(1)
