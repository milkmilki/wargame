extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := GameState.new()
	state.generate_grid_world(13579)
	var before := state.chronicle_events.size()
	ChronicleRules.begin_war(state, 777, [0], [1])
	ChronicleRules.record_casualties(state, 777, 1, 18200)
	ChronicleRules.mark_pending(state, 777)
	state.war_relation_ids.clear()
	ChronicleRules.finalize_pending(state)
	_check(state.chronicle_events.size() == before + 1, "war writes one final event")
	_check(str(state.chronicle_events[-1].text).begins_with("1年 伐"), "active perspective frozen")
	_check(int(state.chronicle_events[-1].casualties) == 18200, "actual losses retained")
	_check(str(state.chronicle_events[-1].views[1]).contains("伐我"), "defender perspective retained")
	var snapshot := NativeSnapshotBuilder.build(state)
	_check(snapshot.schema_version == 22 and snapshot.has("chronicle_events"), "chronicle snapshot persisted")
	ChronicleRules.record_ultimatum(state, 0, 1, UltimatumRules.Outcome.ANNEX)
	_check(str(state.chronicle_events[-1].text).contains("威服"), "ultimatum event")
	ChronicleRules.record_rebellion(state, 2, 0, "张角", ["巨鹿"], false, "")
	_check(str(state.chronicle_events[-1].text).contains("张角"), "rebellion event")
	_test_war_perspectives()
	_test_coalition_names()
	_test_coalition_declaration()
	_test_defender_annexation()
	_test_defender_annexation(true)
	await _test_history_style(state)
	if not failures.is_empty():
		for failure in failures: push_error("CHRONICLE_SMOKE_FAIL: " + failure)
		quit(1)
	else:
		print("CHRONICLE_SMOKE_OK")
		quit(0)

func _check(condition: bool, name: String) -> void:
	if not condition: failures.append(name)

func _perspective_fixture() -> GameState:
	var state := GameState.new()
	for id in range(3):
		var nation := Nation.new()
		nation.id = id
		nation.name = ["秦", "赵", "韩"][id]
		nation.alive = true
		state.nations.append(nation)
	for id in range(3):
		var city := City.new()
		city.id = id
		city.name = ["函谷", "晋阳", "邯郸"][id]
		city.owner_nation = [0, 0, 1][id]
		state.cities.append(city)
	state.recognized_city_owners = PackedInt32Array([0, 0, 1])
	state.administrative_center_city_ids = PackedInt32Array([0, 1, 2])
	state.day = 720
	return state

func _test_war_perspectives() -> void:
	var state := _perspective_fixture()
	ChronicleRules.begin_war(state, 10, [0], [1])
	ChronicleRules.record_casualties(state, 10, 0, 18200)
	ChronicleRules.record_casualties(state, 10, 1, 4000)
	state.recognized_city_owners[0] = 1
	state.recognized_city_owners[1] = 1
	state.nations[0].alive = false
	_check(ChronicleRules.finalize_war(state, 10), "counterattack war finalizes")
	var event: Dictionary = state.chronicle_events[-1]
	_check(event.views[1] == "3年 秦伐我，破之，斩敌18200，取函谷、晋阳 灭秦为郡", "defender conquering attacker records victory gains and enemy extinction")
	_check(event.views[0] == "3年 伐赵，败绩，斩敌4000，函谷、晋阳州陷 国除", "defeated initiator records own losses and extinction")
	_check(str(event.text) == str(event.views[0]), "primary war text matches initiator perspective")
	_check(not ChronicleRules.finalize_war(state, 10) and state.chronicle_events.size() == 1, "counterattack summary written once")
	var frozen := str(event.views[1])
	state.nations[0].name = "改名"
	_check(event.views[1] == frozen, "extinction text remains frozen after rename")

	state = _perspective_fixture()
	ChronicleRules.begin_war(state, 11, [0], [1])
	ChronicleRules.record_casualties(state, 11, 1, 18200)
	state.recognized_city_owners[2] = 0
	state.nations[1].alive = false
	ChronicleRules.finalize_war(state, 11)
	event = state.chronicle_events[-1]
	_check(event.views[0] == "3年 伐赵，破之，斩敌18200，取邯郸 灭赵为郡", "initiator conquering defender still records victory")
	_check(event.views[1] == "3年 秦伐我，败绩，邯郸州陷 国除", "defender losing capital records own lost state and extinction")

	state = _perspective_fixture()
	ChronicleRules.begin_war(state, 12, [0, 2], [1])
	state.recognized_city_owners[0] = 1
	state.recognized_city_owners[1] = 1
	state.nations[0].alive = false
	ChronicleRules.finalize_war(state, 12)
	event = state.chronicle_events[-1]
	_check(not str(event.views[2]).contains("国除"), "surviving coalition member is not declared extinct")
	_check(str(event.views[0]).ends_with("国除"), "extinct coalition member has own extinction suffix")
	_check(str(event.views[1]).begins_with("3年 秦、韩伐我，"), "defender names whole attacking coalition including eliminated member")

	state = _perspective_fixture()
	state.nations[1].name = "赵国"
	ChronicleRules.begin_war(state, 13, [0], [1])
	state.nations[1].alive = false
	ChronicleRules.finalize_war(state, 13)
	event = state.chronicle_events[-1]
	_check(str(event.views[0]).begins_with("3年 伐赵国，") and str(event.views[0]).ends_with("灭赵国为郡"), "literal country name preserved without suffix rewriting")

func _test_coalition_names() -> void:
	var state := _perspective_fixture()
	var nation := Nation.new()
	nation.id = 3
	nation.name = "吴"
	state.nations.append(nation)
	state.nations[2].name = "蜀"
	ChronicleRules.begin_war(state, 20, [3, 0, 3], [2, 1, 2])
	state.nations[0].name = "改秦"
	state.nations[1].name = "改赵"
	ChronicleRules.add_war_members(state, 20, [0, 3], [1, 2])
	_check(ChronicleRules.finalize_war(state, 20), "coalition summary finalizes")
	var event: Dictionary = state.chronicle_events[-1]
	for id in [0, 3]:
		_check(str(event.views[id]) == "3年 伐赵、蜀，败绩", "each attacker names complete frozen defending coalition")
	for id in [1, 2]:
		_check(str(event.views[id]) == "3年 秦、吴伐我，败绩", "each defender names complete frozen attacking coalition")
	_check(event.target_names == ["赵", "蜀"], "coalition metadata retains stable deduplicated names")
	_check(not ChronicleRules.finalize_war(state, 20) and state.chronicle_events.size() == 1, "coalition summary is written once")

	state = _perspective_fixture()
	ChronicleRules.begin_war(state, 21, [0], [1])
	ChronicleRules.begin_war(state, 22, [2, 0], [1])
	ChronicleRules.record_casualties(state, 21, 1, 100)
	ChronicleRules.record_casualties(state, 22, 1, 200)
	state.merge_war_ids(21, 22)
	state.nations[2].name = "改韩"
	_check(ChronicleRules.finalize_war(state, 21), "merged coalition finalizes")
	event = state.chronicle_events[-1]
	_check(event.views[1] == "3年 秦、韩伐我，败绩", "merged war includes all original attacker names once")
	_check(event.views[0] == "3年 伐赵，破之，斩敌300", "merged war preserves casualty accounting")
	_check(not ChronicleRules.finalize_war(state, 22) and state.chronicle_events.size() == 1, "merged ledger cannot emit a second summary")

	state = _perspective_fixture()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(2, 1, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(2, 1, GameState.DiplomaticRelation.WAR)
	var war_id := state.war_id_between(0, 1)
	state.merge_war_ids(war_id, state.war_id_between(2, 1))
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	ChronicleRules.finalize_pending(state)
	_check(state.chronicle_events.is_empty(), "partial peace waits for all remaining war relations")
	state.nations[0].name = "改秦"
	state.set_diplomatic_relation(2, 1, GameState.DiplomaticRelation.NEUTRAL)
	ChronicleRules.finalize_pending(state)
	_check(state.chronicle_events.size() == 1, "final partial peace releases one merged summary")
	if not state.chronicle_events.is_empty():
		_check(state.chronicle_events[-1].views[1] == "3年 秦、韩伐我，败绩", "finished participant remains in frozen opponent list")

func _test_coalition_declaration() -> void:
	var state := GameState.new()
	state.generate_grid_world(13579)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	for id in range(4):
		state.nations[id].name = ["秦", "蜀", "韩", "吴"][id]
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1, 3, GameState.DiplomaticRelation.ALLIED)
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR
	var objective_city := -1
	for city_id in state.administrative_center_city_ids:
		if state.cities[city_id].owner_nation == 1:
			objective_city = city_id
			break
	state.nations[0].strategic_region_anchor_city_id = objective_city
	var simulation := Simulation.new()
	simulation.state = state
	var declared := simulation._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR, "a": 0, "b": 1,
		"objective_city": objective_city
	})
	_check(declared, "real diplomacy declares two allied coalitions")
	if declared:
		ChronicleRules.record_casualties(state, state.war_id_between(0, 1), 3, 1200)
		_check(simulation._execute_diplomatic_action({
			"kind": DiplomacyAI.Action.MAKE_PEACE, "a": 0, "b": 1
		}), "real diplomacy makes coalition peace")
		ChronicleRules.finalize_pending(state)
		_check(state.chronicle_events.size() == 1, "real coalition war emits only one final event")
		if state.chronicle_events.size() == 1:
			var views: Dictionary = state.chronicle_events[0].views
			for id in [0, 2]:
				_check(str(views.get(id, "")) == "1年 伐蜀、吴，破之，斩敌1200", "real attacking coalition has full enemy list")
			for id in [1, 3]:
				_check(str(views.get(id, "")) == "1年 秦、韩伐我，败绩", "real defending coalition has full enemy list")
	simulation.queue_free()

func _test_defender_annexation(with_ally: bool = false) -> void:
	var state := GameState.new()
	state.generate_grid_world(13579)
	state.nations[0].name = "秦"
	state.nations[1].name = "赵"
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	_check(state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR), "counterattack integration declares war")
	var war_id := state.war_id_between(0, 1)
	_check(war_id >= 0, "counterattack integration has a war ledger")
	if with_ally:
		state.nations[2].name = "韩"
		state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
		state.set_diplomatic_relation(2, 1, GameState.DiplomaticRelation.NEUTRAL)
		state.set_diplomatic_relation(2, 1, GameState.DiplomaticRelation.WAR)
		state.merge_war_ids(war_id, state.war_id_between(2, 1))
	ChronicleRules.record_casualties(state, war_id, 0, 18200)
	_check(state.annex_nation(1, 0), "defender annexation actually commits")
	_check(not state.nations[0].alive, "absorbed attacker is eliminated before war cleanup")
	_check(state.is_enemy(0, 1), "annexation waits for the normal eliminated-nation war cleanup")
	# 兼并只提交领土事务；灭国投降和战争池释放由模拟结算入口负责。
	var simulation := Simulation.new()
	simulation.state = state
	simulation._resolve_eliminated_nation_capitulations()
	simulation.queue_free()
	ChronicleRules.finalize_pending(state)
	_check(not state.is_enemy(0, 1), "eliminated attacker war relation is released")
	_check(state.war_id_between(0, 1) == -1, "eliminated attacker war id is released")
	if with_ally:
		_check(state.nations[2].alive and not state.is_enemy(2, 1), "surviving ally participates in normal coalition capitulation peace")
	_check(not state.war_chronicle_contexts.has(war_id), "released war ledger is finalized and removed")
	_check(state.chronicle_events.size() == 1, "actual annexation releases and summarizes war")
	if not state.chronicle_events.is_empty():
		var views: Dictionary = state.chronicle_events[-1].views
		if with_ally:
			_check(str(views[1]).begins_with("1年 秦、韩伐我，"), "real counter-conquest names extinct initiator and surviving ally")
			_check(str(views[2]).begins_with("1年 伐赵，") and not str(views[2]).contains("国除"), "surviving attacking ally keeps its own non-extinct perspective")
		_check(str(views[1]).contains("破之，斩敌18200，取") and str(views[1]).ends_with("灭秦为郡"), "actual counterattack annexation defender victory")
		_check(not str(views[1]).contains("州陷") and not str(views[1]).contains("国除"), "victorious defender is not marked defeated or extinct")
		_check(str(views[0]).contains("败绩") and str(views[0]).contains("州陷") and str(views[0]).ends_with("国除"), "actual defeated attacker keeps its own defeat and extinction view")
		_check(not str(views[0]).contains("破之") and not str(views[0]).contains("取"), "defeated attacker does not inherit defender gains")

func _test_history_style(state: GameState) -> void:
	state.chronicle_events.append({
		"actor_ids": [0], "target_ids": [1],
		"text": "3年 秦伐我，破之，斩敌18200，取函谷、晋阳、邯郸、巨鹿、洛阳、长安、太原、上党、河内、南阳、颍川、陈留 灭秦为郡"
	})
	var events_before := state.chronicle_events.duplicate(true)
	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	panel.open_for_nation(0)
	panel._on_mode_selected(1)
	_check(panel._history.get_child_count() > 0, "history view contains saved records")
	for child in panel._history.get_children():
		var label := child as Label
		_check(label != null and label.get_theme_color("font_color") == Color.BLACK, "history text is explicitly black")
		if label != null and FileAccess.file_exists("C:/Windows/Fonts/simfang.ttf"):
			var font_name := label.get_theme_font("font").get_font_name()
			_check(font_name.contains("FangSong") or font_name.contains("仿宋"), "history uses installed FangSong font")
	_check(state.chronicle_events == events_before, "history styling does not rewrite persisted events")
	await process_frame
	await process_frame
	_check((panel._history.get_child(0) as Label).get_line_count() > 1, "long history record wraps within the panel")
	var screenshot_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(screenshot_path) == OK, "history screenshot saved")
	panel.queue_free()
	await process_frame
