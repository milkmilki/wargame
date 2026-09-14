extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := GameState.new()
	state.generate_grid_world(96001)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(state, simulation)
	await process_frame
	var nation_id := 0
	var nation := state.nations[nation_id]
	var old_name := nation.ruler_name
	var old_started_day := nation.ruler_started_day
	var old_revision := nation.ruler_revision
	_check(
		simulation.set_ruler_profile(
			nation_id,
			RulerProfile.CONQUEROR,
			[
				RulerProfile.TRAIT_MARTIAL,
				RulerProfile.TRAIT_AMBITIOUS,
			] as Array[String]
		),
		"合法君主配置必须立即应用"
	)
	_check(
		nation.ruler_archetype == RulerProfile.CONQUEROR
			and nation.ruler_traits.has(RulerProfile.TRAIT_MARTIAL)
			and nation.ruler_traits.has(RulerProfile.TRAIT_AMBITIOUS),
		"原型和特质必须写入当前君主"
	)
	_check(
		nation.trade_policy == RulerProfile.trade_policy_for(nation),
		"手动调校后贸易政策必须与新君主配置一致"
	)
	var nation_army: Army = null
	for army in state.armies:
		if army.owner_nation == nation_id:
			nation_army = army
			break
	_check(
		nation_army != null
			and is_equal_approx(
				nation_army.ruler_defense_multiplier,
				RulerProfile.defense_multiplier(nation)
			),
		"现有军队的君主派生倍率必须立即刷新"
	)
	_check(
		nation.ruler_name == old_name
			and nation.ruler_started_day == old_started_day
			and nation.ruler_revision == old_revision,
		"手动调校不得触发继位或重置任期"
	)
	_check(
		not simulation.set_ruler_profile(
			nation_id,
			RulerProfile.BALANCED,
			[
				RulerProfile.TRAIT_MARTIAL,
				RulerProfile.TRAIT_FRUGAL,
				RulerProfile.TRAIT_DILIGENT,
			] as Array[String]
		),
		"超过两个特质的配置必须拒绝"
	)
	_check(
		not simulation.set_ruler_profile(
			nation_id,
			RulerProfile.BALANCED,
			[
				RulerProfile.TRAIT_CENTRALIZER,
				RulerProfile.TRAIT_FEUDALIST,
			] as Array[String]
		),
		"集权倾向和分封倾向不得同时存在"
	)

	renderer.select_nation(nation_id)
	var detail_rect := renderer._selection_detail_rect(
		renderer._selection_detail_line_count()
	)
	var trigger_rect := renderer.ruler_profile_trigger_rect(
		detail_rect, renderer.get("_display_scale")
	)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = trigger_rect.get_center()
	renderer._handle_mouse_button(press)
	var menu := renderer.get("_ruler_profile_menu") as PopupMenu
	_check(menu != null and menu.visible, "点击君主特质行必须打开下拉框")
	renderer._on_ruler_profile_menu_id_pressed(
		MapRenderer.RULER_MENU_ARCHETYPE_BASE + RulerProfile.MERCHANT
	)
	_check(
		nation.ruler_archetype == RulerProfile.MERCHANT,
		"下拉框必须能即时切换君主原型"
	)
	simulation.set_ruler_profile(
		nation_id,
		nation.ruler_archetype,
		[RulerProfile.TRAIT_CENTRALIZER] as Array[String]
	)
	renderer._on_ruler_profile_menu_id_pressed(
		MapRenderer.RULER_MENU_TRAIT_BASE
			+ RulerProfile.all_traits().find(RulerProfile.TRAIT_FEUDALIST)
	)
	_check(
		nation.ruler_traits.has(RulerProfile.TRAIT_FEUDALIST)
			and not nation.ruler_traits.has(RulerProfile.TRAIT_CENTRALIZER),
		"从下拉框选择互斥特质时必须自动替换旧特质"
	)
	renderer.set_display_state(state, true)
	_check(
		not renderer.open_ruler_profile_menu(Vector2.ZERO),
		"历史回看状态不得打开君主编辑下拉框"
	)
	renderer.free()
	simulation.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("RULER_PROFILE_EDITOR_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("RULER_PROFILE_EDITOR_FAIL: " + failure)
	quit(1)
