extends SceneTree
const Legacy = preload("res://tests/support/legacy_alliance_state.gd")
var checks := 0
var failures: Array[String] = []
class CountingState extends "res://tests/support/grid_world.gd":
	var relation_queries := 0
	func relation_between(a: int, b: int) -> int:
		relation_queries += 1
		return super.relation_between(a, b)
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func compare(state: GameState, label: String):
	var oracle := Legacy.new()
	oracle.nations = state.nations
	oracle.diplomatic_relations = state.diplomatic_relations
	oracle.succession_conflicts = state.succession_conflicts
	for alive_only in [true, false]:
		for id in range(-1, state.nations.size() + 1):
			check(state.alliance_bloc(id, alive_only) == oracle.alliance_bloc(id, alive_only), label + ": exact original query %d/%s" % [id, str(alive_only)])
func run():
	var state := CountingState.new(); state.generate_world(1, 4, 36)
	state.atlas_layout = {"model": "alliance-cache-test", "territorial_pairs": [] as Array[Vector2i]}
	compare(state, "initial")
	state.relation_queries = 0
	for id in range(4): state.alliance_bloc(id)
	check(state.relation_queries == 0, "all observers reuse the complete warm alliance graph")
	var rng_state := state.rng.state
	var mutable := state.alliance_bloc(0); mutable.clear()
	check(not state.alliance_bloc(0).is_empty(), "returned array cannot corrupt cache")
	for pair in [[0, 1], [1, 2], [2, 3]]:
		state.set_diplomatic_relation(pair[0], pair[1], GameState.DiplomaticRelation.ALLIED)
		compare(state, "alliance join")
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.WAR)
	compare(state, "contradictory alliance excludes hostile co-members")
	state.diplomatic_relations[state._diplomacy_key(0, 3)] = GameState.DiplomaticRelation.NEUTRAL
	compare(state, "in-place diplomatic change")
	state.nations[1].alive = false
	compare(state, "alive filtering separates cache variants")
	state.nations[1].alive = true
	state.nations[3].succession_identity = true
	var conflict := SuccessionConflict.new()
	conflict.nation_id = 0; conflict.rebel_nation_id = 3; conflict.war_id = -1
	state.succession_conflicts[0] = conflict
	compare(state, "pending succession identity")
	conflict.war_id = 100
	compare(state, "launched succession conflict")
	conflict.rebel_nation_id = 2
	compare(state, "in-place succession participants")
	state.succession_conflicts.clear(); state.nations[3].succession_identity = false
	compare(state, "succession resolved")
	state.relation_queries = 0; state.day += 1; state.ownership_revision += 1; state.family_revision += 1
	state.armies[0].size -= 1
	for id in range(4): state.alliance_bloc(id)
	check(state.relation_queries == 0, "army, date, ownership and unrelated family changes do not rebuild alliance membership")
	check(state.rng.state == rng_state, "cache never consumes random stream")
	var jobs := []; var tasks := []
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	for id in range(4):
		var job := {"id": id, "result": []}; jobs.append(job)
		tasks.append(WorkerThreadPool.add_task(func(): job.result = state.alliance_bloc(int(job.id))))
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	for job in jobs: check(job.result == state.alliance_bloc(int(job.id)), "concurrent cold queries publish one coherent graph")
	state.atlas_layout.clear(); state.relation_queries = 0
	state.alliance_bloc(0); state.alliance_bloc(0)
	check(state.relation_queries > 0, "legacy grid keeps original query path")
	state.generate_world(7, 3, 12)
	state.atlas_layout = {"model": "alliance-cache-test", "territorial_pairs": [] as Array[Vector2i]}
	compare(state, "regenerated same object")
	var random := RandomNumberGenerator.new(); random.seed = 5190855
	state.generate_world(7, 8, 24)
	state.atlas_layout = {"model": "alliance-cache-test", "territorial_pairs": [] as Array[Vector2i]}
	var relations := [GameState.DiplomaticRelation.WAR, GameState.DiplomaticRelation.NEUTRAL, GameState.DiplomaticRelation.ALLIED]
	for sample in range(64):
		var a := random.randi_range(0, 7); var b := random.randi_range(0, 7)
		if a != b: state.diplomatic_relations[state._diplomacy_key(a, b)] = relations[random.randi_range(0, 2)]
		state.nations[sample % 8].alive = random.randf() > .2
		compare(state, "mixed topology sample%d" % sample)
	for failure in failures: printerr("ATLAS_ALLIANCE_CACHE_FAIL ", failure)
	print("ATLAS_ALLIANCE_CACHE_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
