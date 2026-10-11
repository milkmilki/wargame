extends "res://tests/atlas_daily_reserves.gd"
## Enemy numerical superiority alone must not create pre-contact withdrawals.

func run() -> void:
	# Manual RED reproduction may supply the archived pre-change implementation.
	var utility: Script = UtilityAI
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--utility="): utility = load(arg.trim_prefix("--utility="))
	for locked in [false, true]:
		var state := fixture("precontact")
		state.uses_heightmap = true
		state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
		add_army(state, 0, 4)
		var army := state.armies[0]
		army.ai_order_until_day = state.day + 30 if locked else 0
		var view := CountingView.new()
		view.state = state; view.nation_id = 0; view.day = state.day
		view.friendly_cities.assign(state.cities.filter(func(c): return c.owner_nation == 0))
		view.friendly_armies = [army]
		var snapshot := StrategicMapSnapshot.new()
		var threat := ThreatField.new()
		threat.threat_by_city = {4: 100000000.0, 5: 100000000.0}
		threat.support_by_city = {}
		var plan := CityDefensePlan.new(); plan.view = view
		var choice: ActionCandidate = utility.choose(view, snapshot, threat, ArmyCoordinator.new(), army, 0.35, plan)
		check(choice.kind == ActionCandidate.Kind.NONE, "outnumbered idle army stays at its city, locked=%s" % locked)
		check(view.fields == 0, "idle defense does not search for a safe withdrawal city")
		army.state = Army.State.HOLDING; army.on_edge = true
		army.move_from = 4; army.move_to = 5; army.move_progress = 0.35
		choice = utility.choose(view, snapshot, threat, ArmyCoordinator.new(), army, 0.35, plan)
		check(choice.kind == ActionCandidate.Kind.HOLD, "outnumbered edge army continues holding, locked=%s" % locked)
		check(army.state == Army.State.HOLDING and army.move_progress == 0.35, "decision leaves existing deployment intact")
		army.state = Army.State.RETREATING; army.forced_retreat = true
		choice = utility.choose(view, snapshot, threat, ArmyCoordinator.new(), army, 0.35, plan)
		check(choice.kind == ActionCandidate.Kind.NONE and army.forced_retreat, "AI does not redirect an automatic retreat")
	for failure in failures: printerr("PRECONTACT_HOLD_FAIL ", failure)
	print("PRECONTACT_HOLD_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
