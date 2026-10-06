extends SceneTree
const Chain = preload("res://tests/succession_chain.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	var state: GameState = Chain.fixture()
	var nation := state.nations[0]
	var prince := nation.prince_person_ids[1]
	PrincePolitics.person(state, 0, prince).archetype = RulerProfile.CONQUEROR
	var rebel := state.create_army(0, 1, 15000)
	rebel.political_person_id = prince
	var crown := state.create_army(0, 0, 5000)
	crown.political_person_id = nation.crown_prince_person_id
	check(SuccessionRules.begin_preparation(state, 0, prince), "begin")
	var conflict: SuccessionConflict = state.succession_conflicts[0]
	check(SuccessionRules.launch(state, conflict), "launch")
	var sim := Simulation.new()
	sim.setup(state)
	return {"state": state, "sim": sim, "conflict": conflict, "rebel": rebel, "crown": crown}

func field(x: Dictionary, reverse: bool = false, siege: bool = false) -> Battle:
	var battle: Battle = x.state.new_battle(Battle.Kind.SIEGE if siege else Battle.Kind.FIELD)
	battle.edge = x.state.edge_of(0, 1)
	if siege:
		battle.city = x.state.cities[0]
		battle.siege_attacker_nation = x.conflict.rebel_nation_id
		battle.side_b_defends_city = true
	x.sim._enter_battle(battle, x.rebel, 2 if reverse else 1)
	x.sim._enter_battle(battle, x.crown, 1 if reverse else 2)
	return battle

func resolve(x: Dictionary, battle: Battle) -> void:
	for day in range(80):
		x.state.day += 1
		x.sim._resolve_battles()
		if battle.finished: break
	check(battle.finished, "real battle finishes")

func run() -> void:
	for reverse in [false, true]:
		var x := fixture()
		x.rebel.attack = 0
		x.crown.attack = 0
		x.rebel.morale = 0.08
		x.crown.morale = 1.0
		var battle := field(x, reverse)
		resolve(x, battle)
		check(x.rebel.size > 0 and x.state.cities[1].owner_nation == x.conflict.rebel_nation_id, "defeat has surviving rebels and an uncaptured camp")
		check(x.conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED, "field defeat locks failure independent of side A/B")
		x.sim._update_succession_conflicts()
		check(x.state.succession_conflicts.is_empty() and not x.state.nations[x.conflict.rebel_nation_id].alive, "real defeat cleans up temporary identity")
		check(x.state.nations[0].crown_prince_person_id == x.conflict.crown_person_id and not PrincePolitics.person(x.state, 0, x.conflict.challenger_person_id).alive, "defeated challenger dies and existing crown remains")
		check(x.state.cities[1].owner_nation == 0 and x.rebel.owner_nation == 0 and x.rebel.campaign_front_id == -1 and x.state.war_relation_ids.is_empty(), "camp and surviving troops return without internal war references")
		var events: int = x.state.chronicle_events.size()
		x.sim._update_succession_conflicts()
		check(x.state.chronicle_events.size() == events, "settlement records only once")
		x.sim.free()
	var city := fixture()
	city.rebel.attack = 0
	city.crown.attack = 0
	city.rebel.morale = 0.08
	city.crown.morale = 1.0
	resolve(city, field(city, false, true))
	check(city.conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED, "field combat inside a siege shell also locks failure")
	city.sim._update_succession_conflicts()
	city.sim.free()
	var assault := fixture()
	var guard := Army.new()
	guard.id = -1
	guard.is_city_garrison = true
	guard.owner_nation = 0
	guard.size = 500
	var siege: Battle = assault.state.new_battle(Battle.Kind.SIEGE)
	siege.city = assault.state.cities[0]
	siege.siege_attacker_nation = assault.conflict.rebel_nation_id
	assault.sim._enter_battle(siege, assault.rebel, 1)
	siege.side_b.append(guard)
	assault.rebel.morale = 0.01
	assault.sim._resolve_combat_round(siege)
	check(siege.finished and siege.winner_side == 2 and assault.conflict.pending_outcome == SuccessionConflict.Outcome.NONE, "virtual-garrison assault defeat is not a real field defeat")
	assault.sim.free()
	var win := fixture()
	win.rebel.attack = 0
	win.crown.attack = 0
	win.rebel.morale = 1.0
	win.crown.morale = 0.08
	resolve(win, field(win))
	check(win.conflict.pending_outcome == SuccessionConflict.Outcome.NONE, "winning a field battle alone does not replace the crown")
	win.sim.free()
	var draw := fixture()
	PrincePolitics.person(draw.state, 0, draw.conflict.crown_person_id).archetype = RulerProfile.CONQUEROR
	draw.rebel.attack = 0
	draw.crown.attack = 0
	draw.rebel.morale = 0.08
	draw.crown.morale = 0.08
	draw.crown.size = draw.rebel.size
	draw.crown.ruler_morale_multiplier = draw.rebel.ruler_morale_multiplier
	var drawn := field(draw)
	resolve(draw, drawn)
	check(drawn.winner_side == 0 and draw.conflict.pending_outcome == SuccessionConflict.Outcome.NONE, "a real draw is not a challenger defeat")
	draw.sim.free()
	var busy := fixture()
	busy.rebel.attack = 0
	busy.crown.attack = 0
	busy.rebel.morale = 0.08
	busy.crown.morale = 1.0
	var finishing := field(busy)
	var extra := Army.new()
	extra.id = busy.state._next_army_id
	busy.state._next_army_id += 1
	extra.owner_nation = busy.conflict.rebel_nation_id
	extra.location_city = 1
	extra.size = 5000
	extra.max_size = 5000
	busy.state.armies.append(extra)
	busy.conflict.army_ids.append(extra.id)
	var crown_extra: Army = busy.state.create_army(0, 0, 5000)
	crown_extra.political_person_id = busy.conflict.crown_person_id
	busy.conflict.crown_army_ids.append(crown_extra.id)
	var ongoing: Battle = busy.state.new_battle(Battle.Kind.FIELD)
	ongoing.edge = busy.state.edge_of(0, 1)
	busy.sim._enter_battle(ongoing, extra, 1)
	busy.sim._enter_battle(ongoing, crown_extra, 2)
	for day in range(40):
		busy.state.day += 1
		busy.sim._resolve_combat_round(finishing)
		if finishing.finished:
			busy.sim._finish_field_battle(finishing)
			break
	check(busy.conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED, "one completed defeat locks the whole revolt")
	busy.sim._update_succession_conflicts()
	check(busy.state.succession_conflicts.has(0) and not ongoing.finished and extra.state == Army.State.FIGHTING, "another real battle finishes naturally before political cleanup")
	check(not busy.sim._execute_ai_candidate(busy.rebel, ActionCandidate.make(ActionCandidate.Kind.ATTACK, 2000, "stale", 0)), "a locked result rejects new participant orders")
	busy.sim._capture_city(busy.rebel, busy.state.cities[0])
	check(busy.conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED, "later capture cannot overwrite a locked defeat")
	extra.attack = 0
	crown_extra.attack = 0
	extra.morale = 0.08
	crown_extra.morale = 1.0
	resolve(busy, ongoing)
	busy.sim._update_succession_conflicts()
	check(busy.state.succession_conflicts.is_empty(), "cleanup completes after the remaining field battle")
	check(busy.state.succession_events.filter(func(e: Dictionary) -> bool: return e.event == "result_locked").size() == 1, "multiple defeats lock and record the result once")
	busy.sim.free()
	var idle := fixture()
	var snapshot := NativeSnapshotBuilder.build(idle.state)
	check(snapshot.succession_conflicts[0].last_progress_day == idle.state.day and snapshot.succession_conflicts[0].has("resolution_reason"), "native snapshot freezes additive resolution and progress fields")
	var start: int = idle.state.day
	for day in range(1, 181):
		idle.state.day = start + day
		idle.state.cities[0].garrison_manpower += 1
		idle.sim._update_succession_conflicts()
	check(idle.state.succession_conflicts.is_empty(), "180 days of no military progress closes the revolt")
	check(idle.state.succession_events.any(func(e: Dictionary) -> bool: return e.event == "result_locked" and e.details.get("reason", "") == "no_progress"), "timeout records its actual reason")
	idle.sim.free()
	var legacy := fixture()
	legacy.conflict.last_progress_day = -1
	legacy.conflict.progress_positions.clear()
	legacy.state.day = 10000
	legacy.sim._update_succession_conflicts()
	check(legacy.state.succession_conflicts.has(0) and legacy.conflict.last_progress_day == 10000, "legacy missing progress fields start the timer at first observation")
	legacy.sim.free()
	var moving := fixture()
	moving.state.edge_of(0, 1).distance = 10000.0
	moving.sim._plan_succession_conflicts()
	for day in range(1, 201):
		moving.state.day = day
		moving.sim._resolve_supply()
		moving.sim._advance_movement()
		moving.sim._update_succession_conflicts()
	check(moving.rebel.on_edge and moving.state.succession_conflicts.has(0) and moving.conflict.last_progress_day == moving.state.day, "real slow marching prevents a false no-progress timeout")
	moving.sim.free()
	var ui := fixture()
	var center_army: Army = ui.state.create_army(0, 0, 15000)
	center_army.political_person_id = -1
	var requirement := SuccessionRules.attack_requirement(ui.state, ui.conflict)
	var sections := MapRenderer._nation_war_detail_sections(ui.state, ui.conflict.rebel_nation_id)
	check(sections[0].title.begins_with("争位战"), "internal war has an explicit display identity")
	check((sections[0].lines as Array).any(func(line: String) -> bool: return line == "争位需求：出发最低%d" % requirement), "UI uses the actual succession launch gate")
	check(not (sections[0].lines as Array).any(func(line: String) -> bool: return line.contains("45000") or line.contains("可调预备")), "unrelated central reserves and ordinary allocation floor are not presented as succession requirements")
	ui.sim.free()
	var single := fixture()
	var battle := field(single)
	single.rebel.attack = 0
	single.crown.attack = 0
	var reinforcement := Army.new()
	reinforcement.id = single.state._next_army_id
	single.state._next_army_id += 1
	reinforcement.owner_nation = single.conflict.rebel_nation_id
	reinforcement.location_city = 1
	reinforcement.size = 15000
	reinforcement.max_size = 15000
	reinforcement.morale = 1.0
	reinforcement.attack = 0
	single.state.armies.append(reinforcement)
	single.conflict.army_ids.append(reinforcement.id)
	single.sim._enter_battle(battle, reinforcement, 1)
	single.rebel.morale = 0.01
	single.state.day += 1
	single.sim._resolve_battles()
	check(not battle.finished and single.conflict.pending_outcome == SuccessionConflict.Outcome.NONE, "one army routing does not end a still-capable side")
	single.sim.free()
	check(MapRenderer.campaign_phase_text(CoalitionCampaignFront.Mode.DEFENSE, CoalitionCampaignFront.Phase.ASSEMBLE).begins_with("防守"), "default defense phase never claims to be attacking")
	for failure in failures: push_error("SUCCESSION_RESOLUTION_FAIL: " + failure)
	print("SUCCESSION_RESOLUTION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
