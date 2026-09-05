extends SceneTree

var _failed: Array[String] = []


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(12345)
	var history := PoliticalHistory.new()
	history.reset(state, Simulation.DAYS_PER_MONTH)
	_check(history.snapshot_count() == 1, "reset should capture day zero")

	state.day = Simulation.DAYS_PER_MONTH - 1
	state.month = state.day / Simulation.DAYS_PER_MONTH
	_check(not history.maybe_capture(state), "non-interval day must not capture")
	state.day = Simulation.DAYS_PER_MONTH
	state.month = 1
	_check(history.maybe_capture(state), "interval day should capture")
	_check(history.snapshot_count() == 2, "monthly snapshot should be appended")

	var historical_owner := state.cities[0].owner_nation
	var other_owner := (historical_owner + 1) % state.nations.size()
	state.set_diplomatic_relation(
		historical_owner,
		other_owner,
		GameState.DiplomaticRelation.ALLIED
	)
	state.day = Simulation.DAYS_PER_MONTH * 2
	state.month = 2
	history.maybe_capture(state)
	state.cities[0].owner_nation = other_owner
	state.set_diplomatic_relation(
		historical_owner,
		other_owner,
		GameState.DiplomaticRelation.WAR
	)

	var view := history.build_view_state(state, 2)
	_check(view != state, "history view must be detached from live state")
	_check(
		view.cities[0] != state.cities[0]
		and view.cities[0].owner_nation == historical_owner,
		"history view should retain captured territory"
	)
	_check(
		view.relation_between(historical_owner, other_owner)
			== GameState.DiplomaticRelation.ALLIED,
		"history view should retain captured diplomacy"
	)
	_check(
		view.armies.is_empty()
		and view.battles.is_empty()
		and view.campaign_visual_events.is_empty(),
		"history view must omit military visuals"
	)
	var first_view_instance := view.get_instance_id()
	var earlier_view := history.build_view_state(state, 0)
	_check(
		earlier_view.get_instance_id() == first_view_instance,
		"history scrubbing should reuse one detached display state"
	)
	_check(
		earlier_view.day == 0,
		"reused display state should apply the selected snapshot"
	)

	if _failed.is_empty():
		print("POLITICAL_HISTORY_TEST PASS")
		quit(0)
	else:
		for message in _failed:
			push_error(message)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed.append(message)
