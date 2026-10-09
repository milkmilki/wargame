extends "res://tests/ultimatum_e2e.gd"
## Actual submissions must reuse validated fiscal forecasts without carrying
## previous resource reports across actions or dropping pending-supply mode.

class SubmissionSimulation extends Simulation:
	var preseed := false
	var submission_route_builds := 0
	var submissions := 0

	func _execute_ultimatum(action: Dictionary, cache: Dictionary, flows: Array[Dictionary]) -> bool:
		if preseed and not cache.has("monthly_gold_flows"):
			_seed_trade_forecast(cache)
		var before := TradeNetwork.connectivity_prefilter_counters()
		var result := super._execute_ultimatum(action, cache, flows)
		var after := TradeNetwork.connectivity_prefilter_counters()
		submission_route_builds += int(after.structure_builds) - int(before.structure_builds)
		submissions += 1
		return result

func _run() -> void:
	for outcome in [UltimatumRules.Outcome.REFUSE, UltimatumRules.Outcome.SUBMIT, UltimatumRules.Outcome.ANNEX]:
		for pending in [false, true]:
			var reference := _fixture(outcome)
			var candidate := _fixture(outcome)
			var reference_cache: Dictionary = reference.sim._seed_trade_forecast({"__forecast_pending_supply": pending})
			reference_cache["__disable_structure_cache"] = true
			candidate.sim._seed_trade_forecast({})
			var actions: Array[Dictionary] = []
			DiplomacyAI._collect_existing_war_preparation(reference.state, 0, actions, {}, reference_cache)
			_check(not actions.is_empty(), "healthy action outcome=%d pending=%s" % [outcome, pending])
			if not actions.is_empty():
				TradeNetwork.reset_connectivity_prefilter_counters()
				var expected: bool = reference.sim._execute_diplomatic_action(actions[0].duplicate(true), reference_cache)
				var reference_counts := TradeNetwork.connectivity_prefilter_counters()
				var candidate_cache := {"__forecast_pending_supply": pending}
				var profile := {"enabled": true}
				candidate_cache["__disable_structure_cache"] = true
				candidate_cache["__profile"] = profile
				TradeNetwork.reset_connectivity_prefilter_counters()
				var actual: bool = candidate.sim._execute_diplomatic_action(actions[0].duplicate(true), candidate_cache)
				var candidate_counts := TradeNetwork.connectivity_prefilter_counters()
				_check(expected and actual, "healthy submission succeeds outcome=%d" % outcome)
				_check(
					var_to_bytes(NativeSnapshotBuilder.build(reference.state)) == var_to_bytes(NativeSnapshotBuilder.build(candidate.state)),
					"full committed snapshot outcome=%d pending=%s" % [outcome, pending]
				)
				_check(bool(candidate_cache.get("__forecast_pending_supply", false)) == pending, "pending-supply mode retained")
				if outcome != UltimatumRules.Outcome.REFUSE:
					_check(bool(candidate_cache.get("__disable_structure_cache", false)), "explicit structure-cache disable retained")
					_check(candidate_cache.has("__profile"), "profile retained")
					if candidate_cache.has("__profile"):
						candidate_cache["__profile"]["probe"] = 1
						_check(int(profile.get("probe", 0)) == 1, "profile retains original reference")
				for key in ["structure_builds"]:
					_check(int(candidate_counts[key]) == int(reference_counts[key]), "no cold trade rebuild outcome=%d key=%s expected=%d actual=%d" % [outcome, key, reference_counts[key], candidate_counts[key]])
				_check(not candidate.sim._execute_diplomatic_action(actions[0].duplicate(true)), "submission commits once")
			reference.sim.free()
			candidate.sim.free()
	for mutation in ["food", "arrival"]:
		var fixture := _fixture(UltimatumRules.Outcome.SUBMIT)
		var cache: Dictionary = fixture.sim._seed_trade_forecast({})
		var actions: Array[Dictionary] = []
		DiplomacyAI._collect_existing_war_preparation(fixture.state, 0, actions, {}, cache)
		_check(not actions.is_empty(), "healthy fixture before mutation=" + mutation)
		if mutation == "food":
			for city in fixture.state.cities:
				if city.owner_nation == 0:
					city.food_storage = 0
		else:
			for army in fixture.state.armies:
				if army.owner_nation == 0:
					army.state = Army.State.RECOVERING
		if not actions.is_empty():
			_check(not fixture.sim._execute_diplomatic_action(actions[0], cache), "warm scoring cache rejects after " + mutation)
			_check(fixture.state.overlord_of(1) < 0 and not fixture.state.is_enemy(0, 1), "rejected mutation remains peaceful")
		fixture.sim.free()
	var fixture := _fixture(UltimatumRules.Outcome.SUBMIT)
	var cache: Dictionary = fixture.sim._seed_trade_forecast({"__forecast_pending_supply": true})
	DiplomacyAI.resource_report(fixture.state, 0, cache)
	fixture.state.day += 1
	fixture.sim._seed_trade_forecast(cache)
	_check(cache.has("trade_network_result") and cache.has("monthly_gold_flows"), "newly seeded fiscal data survives revision invalidation")
	_check(not cache.has("resource:0"), "old derived resource report removed on revision change")
	_check(bool(cache.get("__forecast_pending_supply", false)), "revision invalidation retains pending-supply mode")
	_check(DiplomacyAI.resource_report(fixture.state, 0, cache) == DiplomacyAI.resource_report(fixture.state, 0, fixture.sim._seed_trade_forecast({"__forecast_pending_supply": true})), "reseeded report matches fresh report")
	fixture.sim.free()
	var reference := SubmissionSimulation.new()
	var candidate := SubmissionSimulation.new()
	reference.preseed = true
	for sim in [reference, candidate]:
		var state := preload("res://tests/support/grid_world.gd").new()
		state.generate_world(12345, 40, 160)
		root.add_child(sim)
		sim.setup(state)
	for day in range(60):
		reference._advance_day(false)
		candidate._advance_day(false)
		_check(var_to_bytes(NativeSnapshotBuilder.build(reference.state)) == var_to_bytes(NativeSnapshotBuilder.build(candidate.state)), "live daily snapshot day=%d" % candidate.state.day)
	_check(reference.submissions > 0 and candidate.submissions == reference.submissions, "live world exercises the same ultimatum submissions")
	_check(candidate.submission_route_builds == reference.submission_route_builds, "live submissions avoid cold route builds expected=%d actual=%d" % [reference.submission_route_builds, candidate.submission_route_builds])
	print("ULTIMATUM_ROUTE_BUILDS reference=%d candidate=%d submissions=%d" % [reference.submission_route_builds, candidate.submission_route_builds, candidate.submissions])
	reference.free()
	candidate.free()
	print("ULTIMATUM_FORECAST_CACHE_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
