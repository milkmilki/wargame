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
	_check(str(state.chronicle_events[-1].text).begins_with("1年 征"), "active perspective frozen")
	_check(int(state.chronicle_events[-1].casualties) == 18200, "actual losses retained")
	_check(str(state.chronicle_events[-1].views[1]).contains("伐我"), "defender perspective retained")
	var snapshot := NativeSnapshotBuilder.build(state)
	_check(snapshot.schema_version == 21 and snapshot.has("chronicle_events"), "chronicle snapshot persisted")
	ChronicleRules.record_ultimatum(state, 0, 1, UltimatumRules.Outcome.ANNEX)
	_check(str(state.chronicle_events[-1].text).contains("威服"), "ultimatum event")
	ChronicleRules.record_rebellion(state, 2, 0, "张角", ["巨鹿"], false, "")
	_check(str(state.chronicle_events[-1].text).contains("张角"), "rebellion event")
	_test_war_perspectives()
	_test_defender_annexation()
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
	_check(event.views[0] == "3年 征赵，败绩，斩敌4000，函谷、晋阳州陷 国除", "defeated initiator records own losses and extinction")
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
	_check(event.views[0] == "3年 征赵，破之，斩敌18200，取邯郸 灭赵为郡", "initiator conquering defender still records victory")
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

	state = _perspective_fixture()
	state.nations[1].name = "赵国"
	ChronicleRules.begin_war(state, 13, [0], [1])
	state.nations[1].alive = false
	ChronicleRules.finalize_war(state, 13)
	event = state.chronicle_events[-1]
	_check(str(event.views[0]).begins_with("3年 征赵国，") and str(event.views[0]).ends_with("灭赵国为郡"), "literal country name preserved without suffix rewriting")

func _test_defender_annexation() -> void:
	var state := GameState.new()
	state.generate_grid_world(13579)
	state.nations[0].name = "秦"
	state.nations[1].name = "赵"
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	_check(state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR), "counterattack integration declares war")
	var war_id := state.war_id_between(0, 1)
	_check(war_id >= 0, "counterattack integration has a war ledger")
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
	_check(not state.war_chronicle_contexts.has(war_id), "released war ledger is finalized and removed")
	_check(state.chronicle_events.size() == 1, "actual annexation releases and summarizes war")
	if not state.chronicle_events.is_empty():
		var views: Dictionary = state.chronicle_events[-1].views
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
