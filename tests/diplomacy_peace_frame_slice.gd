extends SceneTree
const Factory = preload("res://tests/native_graph_equivalence.gd")
const Fixture = preload("res://tests/support/native_runtime_fixture.gd")
class CountingState extends GameState:
	var enemy_calls := 0
	func is_enemy(a: int, b: int) -> bool:
		enemy_calls += 1
		return super.is_enemy(a,b)
var checks := 0
var failures := 0
var frames := 0
var peace_actions := 0

func _initialize() -> void:
	process_frame.connect(func(): frames += 1)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PEACE_SLICE_FAIL ", label)

func make_state(mirror: bool, allied: bool) -> GameState:
	var factory := Factory.new()
	var state: GameState = factory.fixture(mirror)
	factory.free()
	state.day = 900
	state.month = 30
	if allied:
		state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
		state.set_diplomatic_relation(2,1,GameState.DiplomaticRelation.WAR)
	return state

func compare(mirror: bool, allied: bool, blocked: bool, budget: int) -> void:
	var state := make_state(mirror, allied)
	var initial := var_to_bytes(Fixture.snapshot(state))
	var rng_before := state.rng.state
	var expected: Array[Dictionary] = []
	var actual: Array[Dictionary] = []
	var expected_committed := {0:true} if blocked else {}
	var actual_committed := expected_committed.duplicate()
	var expected_cache := {}
	var actual_cache := {}
	DiplomacyAI._collect_peace_actions(state,expected,expected_committed,expected_cache)
	var before_frame := frames
	var api: Script = load("res://scripts/ai/diplomacy_ai.gd")
	var clock: int = await api.call("_collect_peace_actions_over_frames",
		state,actual,actual_committed,actual_cache,Time.get_ticks_usec(),budget
	)
	check(var_to_bytes(expected) == var_to_bytes(actual),"exact action values, reason text and order")
	check(var_to_bytes(expected_committed) == var_to_bytes(actual_committed),"same coalition commitments")
	check(clock > 0,"returns the remaining slice clock")
	if not blocked and budget > 0:
		check(frames > before_frame,"eligible peace evaluation yields within its work")
	if budget == 0:
		check(frames == before_frame,"disabled budget keeps synchronous scheduling")
	for key in expected_cache:
		if str(key).begins_with("peace:") or str(key).begins_with("coalition_peace:"):
			check(actual_cache.has(key) and var_to_bytes(expected_cache[key]) == var_to_bytes(actual_cache[key]),"exact cached individual and weighted coalition scores")
	peace_actions += actual.size()
	check(state.rng.state == rng_before,"evaluation consumes no RNG")
	check(var_to_bytes(Fixture.snapshot(state)) == initial,"evaluation does not mutate gameplay state")

func run() -> void:
	var api: Script = load("res://scripts/ai/diplomacy_ai.gd")
	check(api.has_method("_collect_peace_actions_over_frames"),"peace collection supports resumable evaluation")
	if failures > 0:
		quit(1)
		return
	var probe := Simulation.new()
	check(probe.has_method("_prepare_diplomacy_over_frames"),"diplomacy preparation separates regional updates and war synchronization")
	probe.free()
	if failures > 0:
		quit(1)
		return
	for mirror in [false,true]:
		for allied in [false,true]:
			await compare(mirror,allied,false,1)
			await compare(mirror,allied,true,1)
			await compare(mirror,allied,false,0)
	check(peace_actions > 0,"equivalence covers accepted peace actions")
	await compare_preparation()
	await compare_custom_state()
	await compare_cached_rejection()
	print("DIPLOMACY_PEACE_SLICE checks=%d failures=%d accepted=%d" % [checks,failures,peace_actions])
	quit(0 if failures == 0 else 1)

func compare_preparation() -> void:
	var sims: Array[Simulation] = []
	for _index in range(2):
		var sim := Simulation.new()
		root.add_child(sim)
		sim.setup(make_state(false,true))
		sim.paused = true
		sims.append(sim)
	RegionalStrategy.update_targets(sims[0].state)
	sims[0]._normalize_alliance_wars()
	var before_frame := frames
	await sims[1].call("_prepare_diplomacy_over_frames",1)
	check(frames > before_frame,"preparation yields between independent phases")
	check(sims[0].state.rng.state == sims[1].state.rng.state,"preparation RNG remains exact")
	check(var_to_bytes(Fixture.snapshot(sims[0].state)) == var_to_bytes(Fixture.snapshot(sims[1].state)),"same regional targets and synchronized war relations")
	for sim in sims: sim.free()

func counting_state() -> CountingState:
	var source := make_state(false,true)
	var result := CountingState.new()
	for info in source.get_property_list():
		if int(info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and info.name != "script":
			result.set(info.name,source.get(info.name))
	return result

func compare_custom_state() -> void:
	var states: Array[CountingState] = [counting_state(),counting_state()]
	var expected: Array[Dictionary] = []
	var actual: Array[Dictionary] = []
	var expected_committed := {}
	var actual_committed := {}
	DiplomacyAI._collect_peace_actions(states[0],expected,expected_committed,{})
	var api: Script = load("res://scripts/ai/diplomacy_ai.gd")
	await api.call("_collect_peace_actions_over_frames",states[1],actual,actual_committed,{},Time.get_ticks_usec(),1)
	check(var_to_bytes(expected) == var_to_bytes(actual),"custom state retains exact actions")
	check(states[0].enemy_calls == states[1].enemy_calls,"custom callbacks retain original call order and count")
	check(var_to_bytes(expected_committed) == var_to_bytes(actual_committed),"custom state commitments remain exact")

func compare_cached_rejection() -> void:
	var state := make_state(false,true)
	var own: Array[int] = [0,2]
	var enemy: Array[int] = [1]
	var cache := {}
	DiplomacyAI._coalition_peace_breakdown(state,own,enemy,cache)
	DiplomacyAI._coalition_peace_breakdown(state,enemy,own,cache)
	for key in cache:
		if str(key).begins_with("coalition_peace:"):
			cache[key] = (cache[key] as Dictionary).duplicate()
			cache[key].score = -5.0
	var expected: Array[Dictionary] = []
	var actual: Array[Dictionary] = []
	var expected_committed := {}
	var actual_committed := {}
	DiplomacyAI._collect_peace_actions(state,expected,expected_committed,cache.duplicate(true))
	var api: Script = load("res://scripts/ai/diplomacy_ai.gd")
	await api.call("_collect_peace_actions_over_frames",state,actual,actual_committed,cache.duplicate(true),Time.get_ticks_usec(),1)
	check(expected.is_empty() and actual.is_empty(),"cached rejected coalition is not reconsidered through another member")
	check(expected_committed.is_empty() and actual_committed.is_empty(),"rejected coalition leaves no commitment")
