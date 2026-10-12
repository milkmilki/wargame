extends SceneTree
const Fixture = preload("res://tests/succession_chain.gd")
var failures: Array[String]=[]
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func setup_contest() -> Dictionary:
	var state: GameState=Fixture.fixture(); var n:=state.nations[0]; var challenger:=n.prince_person_ids[1]
	PrincePolitics.person(state,0,challenger).archetype=RulerProfile.CONQUEROR
	var a:=state.create_army(0,1,15000); a.political_person_id=challenger
	var b:=state.create_army(0,0,10000); b.political_person_id=n.crown_prince_person_id
	var sim:=Simulation.new(); sim.setup(state)
	return {"state":state,"nation":n,"a":a,"b":b,"challenger":challenger,"sim":sim}
func run() -> void:
	var x:=setup_contest()
	check(SuccessionRules.begin_preparation(x.state,0,x.challenger),"begin")
	var c: SuccessionConflict=x.state.succession_conflicts[0]
	var old: int=x.nation.ruler_person_id
	x.state.day=RulerProfile.succession_due_day(x.nation,x.state.world_seed)
	x.sim._resolve_ruler_successions()
	check(c.succession_delayed and x.nation.ruler_person_id==old,"due_accession_delayed")
	c.pending_outcome=SuccessionConflict.Outcome.CROWN_CHANGED
	x.sim._update_succession_conflicts()
	check(x.nation.ruler_person_id==x.challenger and not x.state.succession_conflicts.has(0),"due_accession_after_result")
	check(x.a.size==15000 and x.b.size==10000,"no_true_casualties")
	x.sim.free()
	for failure in failures: push_error("SUCCESSION_LIFECYCLE_FAIL: "+failure)
	print("SUCCESSION_LIFECYCLE: %d failures"%failures.size()); quit(0 if failures.is_empty() else 1)
