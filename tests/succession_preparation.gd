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
	x.a.state=Army.State.MOVING; x.a.on_edge=true; x.a.move_from=1; x.a.move_to=0
	x.state.cities[0].garrison_manpower=999999
	x.state.edge_of(0,1).max_manpower=0
	check(not SuccessionRules.proposal(x.state,0,x.challenger).is_empty(),"in_transit_no_route_or_garrison_gate")
	check(SuccessionRules.begin_preparation(x.state,0,x.challenger),"immediate_private_start")
	check(not SuccessionRules.begin_preparation(x.state,0,x.challenger),"one_per_country")
	var c: SuccessionConflict=x.state.succession_conflicts[0]
	check(c.launched() and c.battle.round_no==0,"no_physical_preparation")
	x.a.size=1; x.a.attack=500
	check(c.battle.side_a[0].size==15000 and c.battle.side_a[0].attack!=500,"frozen_copies")
	x.sim.free()
	for failure in failures: push_error("SUCCESSION_PREPARATION_FAIL: "+failure)
	print("SUCCESSION_PREPARATION: %d failures"%failures.size()); quit(0 if failures.is_empty() else 1)
