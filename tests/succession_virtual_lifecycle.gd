extends SceneTree
const Fixture = preload("res://tests/succession_chain.gd")
var failures: Array[String]=[]
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func fixture(a_size: int = 10000,b_size: int = 10000) -> Dictionary:
	var state: GameState=Fixture.fixture(); var n:=state.nations[0]
	var challenger:=n.prince_person_ids[1]
	PrincePolitics.person(state,0,challenger).archetype=RulerProfile.BALANCED
	var a:=state.create_army(0,0,a_size); a.political_person_id=challenger
	var b:=state.create_army(0,2,maxi(b_size,1)); b.size=b_size; b.political_person_id=n.crown_prince_person_id
	return {"state":state,"a":a,"b":b,"challenger":challenger}
func run() -> void:
	var x:=fixture(9999,10000)
	check(SuccessionRules.proposal(x.state,0,x.challenger).is_empty(),"ordinary_threshold")
	PrincePolitics.person(x.state,0,x.challenger).archetype=RulerProfile.CONQUEROR
	check(not SuccessionRules.proposal(x.state,0,x.challenger).is_empty(),"conqueror_threshold")
	x=fixture(10000,0)
	check(SuccessionRules.begin_preparation(x.state,0,x.challenger),"valid_heir_zero_force")
	var c: SuccessionConflict=x.state.succession_conflicts[0]
	SuccessionRules.advance(x.state,c); check(c.battle.round_no==0,"starts_next_day")
	x.state.day+=1; SuccessionRules.advance(x.state,c)
	check(c.pending_outcome==SuccessionConflict.Outcome.CROWN_CHANGED,"zero_force_challenger_wins")
	SuccessionRules.finish(x.state,c)
	check(x.state.nations[0].crown_prince_person_id==x.challenger and x.a.size==10000,"promote_not_casualties")
	x=fixture(); x.state.nations[0].crown_prince_person_id=-1
	check(not SuccessionRules.begin_preparation(x.state,0,x.challenger),"no_heir_no_contest")
	x=fixture(); check(SuccessionRules.begin_preparation(x.state,0,x.challenger),"begin")
	c=x.state.succession_conflicts[0]
	var native := NativeSnapshotBuilder.build(x.state)
	check(NativeSnapshotBuilder.succession_validation_error(native).is_empty(),"schema28_validation")
	var legacy:=native.duplicate(true); legacy.schema_version=27
	check(not NativeSnapshotBuilder.succession_validation_error(legacy).is_empty(),"reject27")
	var saved: Dictionary=bytes_to_var(var_to_bytes(c.snapshot()))
	var restored:=SuccessionConflict.from_snapshot(saved)
	check(c.snapshot()==restored.snapshot(),"active_roundtrip")
	x.state.day+=1; SuccessionRules.advance(x.state,c); SuccessionRules.advance(x.state,restored)
	check(c.snapshot()==restored.snapshot(),"restored_same_next_round")
	var round:=c.battle.round_no; SuccessionRules.advance(x.state,c)
	check(c.battle.round_no==round,"daily_guard")
	var replay:=CombatLog.replay_records(c.round_logs)
	check(bool(replay.get("ok",false)),"private_combat_replay")
	x.state.nations[0].ruler_revision+=1; x.state.day+=1; SuccessionRules.advance(x.state,c)
	check(c.pending_outcome==SuccessionConflict.Outcome.ADMINISTRATIVE,"generation_cancel")
	SuccessionRules.finish(x.state,c)
	check(not x.state.nations[0].succession_competition_closed and x.a.size==10000 and not x.state.nations[0].succession_identity,"cancel_no_political_winner")
	x=fixture(); check(SuccessionRules.begin_preparation(x.state,0,x.challenger),"crown_fixture")
	c=x.state.succession_conflicts[0]; c.battle.side_a[0].morale=0.
	x.state.day+=1; SuccessionRules.advance(x.state,c)
	check(c.pending_outcome==SuccessionConflict.Outcome.SUPPRESSED,"crown_wins")
	SuccessionRules.finish(x.state,c)
	check(x.a.size==10000 and x.a.political_person_id<0 and not PrincePolitics.person(x.state,0,x.challenger).alive,"only_political_punishment")
	# Synthetic finite attributes make erosion smaller than floating precision.
	# This exercises the real resolver and the consecutive no-change fallback.
	x=fixture(); SuccessionRules.begin_preparation(x.state,0,x.challenger)
	c=x.state.succession_conflicts[0]
	for army in c.battle.side_a+c.battle.side_b:
		army.attack=0; army.ruler_morale_multiplier=1e30
	for day in range(179): x.state.day+=1; SuccessionRules.advance(x.state,c)
	check(c.pending_outcome==SuccessionConflict.Outcome.NONE,"no_stall_before_180")
	x.state.day+=1; SuccessionRules.advance(x.state,c)
	check(c.resolution_reason=="no_progress" and c.pending_outcome==SuccessionConflict.Outcome.SUPPRESSED,"180_unchanged_days_finish")
	for failure in failures: push_error("SUCCESSION_VIRTUAL_LIFECYCLE_FAIL: "+failure)
	print("SUCCESSION_VIRTUAL_LIFECYCLE: %d failures"%failures.size()); quit(0 if failures.is_empty() else 1)
