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
	var x:=setup_contest(); var old_ruler: int=x.nation.ruler_person_id
	check(SuccessionRules.begin_preparation(x.state,0,x.challenger),"begin")
	var c: SuccessionConflict=x.state.succession_conflicts[0]
	c.pending_outcome=SuccessionConflict.Outcome.CROWN_CHANGED
	check(SuccessionRules.finish(x.state,c),"finish")
	check(x.nation.crown_prince_person_id==x.challenger and x.nation.ruler_person_id==old_ruler,"change_heir_only")
	check(x.a.size==15000 and x.a.owner_nation==0 and x.state.nations.size()==1,"no_map_casualty_or_proxy")
	check(x.nation.succession_competition_closed and x.state.succession_conflicts.is_empty(),"generation_closed")
	x.sim.free()
	for failure in failures: push_error("SUCCESSION_CONFLICT_FAIL: "+failure)
	print("SUCCESSION_CONFLICT: %d failures"%failures.size()); quit(0 if failures.is_empty() else 1)
