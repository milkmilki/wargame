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
	x.a.morale=.2; x.a.attack=1; x.b.attack=100; x.b.morale=1.
	check(SuccessionRules.begin_preparation(x.state,0,x.challenger),"begin")
	var c: SuccessionConflict=x.state.succession_conflicts[0]
	for tick in range(180):
		x.state.day+=1; x.sim._update_succession_conflicts()
		if not x.state.succession_conflicts.has(0): break
	check(c.pending_outcome==SuccessionConflict.Outcome.SUPPRESSED,"defending_crown_wins_real_resolver")
	check(x.nation.crown_prince_person_id==c.crown_person_id and not PrincePolitics.person(x.state,0,x.challenger).alive,"political_result")
	check(x.a.size==15000 and x.b.size==10000 and x.a.location_city==1 and x.b.location_city==0,"copies_only")
	check(x.state.campaign_pairs.is_empty() and x.state.battles.is_empty(),"no_map_counterattack")
	x.sim.free()
	for failure in failures: push_error("SUCCESSION_COUNTERATTACK_FAIL: "+failure)
	print("SUCCESSION_COUNTERATTACK: %d failures"%failures.size()); quit(0 if failures.is_empty() else 1)
