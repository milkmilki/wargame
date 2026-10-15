extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("BATTLE_INFORMATION_FAIL ",message)
func run():
	if not FileAccess.file_exists("res://scripts/atlas/battle_information.gd"):
		check(false,"battle detail presentation is missing"); quit(1); return
	var model=load("res://scripts/atlas/battle_information.gd")
	var state:=preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(94002)
	state.armies.clear(); state.battles.clear()
	state.day=12684
	var a:=Army.new(); a.id=71; a.owner_nation=0; a.size=21000; a.morale=.7
	a.supply_ratio=.6; a.funding_multiplier=.8; a.ruler_attack_multiplier=1.3
	var b:=Army.new(); b.id=83; b.owner_nation=1; b.size=16000; b.morale=1.2
	b.ruler_defense_multiplier=1.2
	var reserve:=Army.new(); reserve.id=94; reserve.owner_nation=0; reserve.size=5000; reserve.morale=.3
	state.armies=[a,b,reserve]
	var battle:=Battle.new(); battle.id=17; battle.edge=state.edges[0]
	battle.edge.danger=.65; battle.edge.max_manpower=10000
	battle.holding_side=2; battle.holding_days=20.; battle.side_a=[reserve,a]; battle.side_b=[b]
	battle.ensure_opening_dice(state.world_seed,true); state.battles=[battle]
	var rng_before: int=state.rng.state; var dice_before:=battle.field_dice.duplicate()
	var original_order:=battle.side_a.duplicate()
	var snapshot: Dictionary=model.snapshot(state,battle)
	check(is_equal_approx(snapshot.a.morale,battle.shared_morale_summary(battle.side_a).effective),"field morale includes reserves and matches combat's shared morale")
	check(snapshot.a.size==26000 and snapshot.a.engaged<=snapshot.a.frontage,"actual manpower is separate from frontage and reserves")
	check(is_equal_approx(snapshot.b.holding_attack,.5) and is_equal_approx(snapshot.b.holding_defense,1.5),"holding side has actual attack and defense modifiers")
	var doc: Dictionary=model.document(state,17)
	check(doc.subtitle.ends_with(" · 36年85天"),"battle date uses the common calendar")
	check(not doc.is_empty() and model.document(state,0).is_empty(),"battle lookup uses stable ID, not list position")
	check(state.rng.state==rng_before and battle.field_dice==dice_before and battle.side_a==original_order and a.size==21000 and a.morale==.7,"inspection does not consume RNG, reorder sides or change troops")
	Combat.battle_log_enabled=true; Combat.clear_battle_log(); Combat.resolve_round(battle,state.day)
	var log_row: Dictionary=Combat.battle_log.back()
	for side in ["a","b"]:
		check(is_equal_approx(snapshot[side].fire,log_row["effective_attack_"+side]),"displayed "+side+" fire matches actual combat")
		check(is_equal_approx(snapshot[side].defense,log_row["effective_defense_"+side]),"displayed "+side+" defense matches actual combat")
	Combat.battle_log_enabled=false; Combat.clear_battle_log()
	battle.kind=Battle.Kind.SIEGE; battle.city=state.cities[state.administrative_center_city_ids[1]]
	battle.city.garrison_manpower=1500; battle.city.food_storage=0; battle.city.garrison_supply_ratio=.4
	battle.side_a=[a]; battle.side_b=[]; battle.siege_attacker_nation=0
	var before: int=battle.city.garrison_manpower
	snapshot=model.snapshot(state,battle)
	check(snapshot.b.size==1500 and battle.side_b.is_empty() and before==battle.city.garrison_manpower,"pure siege displays persistent guard without attaching it to simulation")
	var sim:=Simulation.new(); sim.setup(state)
	var attached: Army=sim._attach_city_garrison(battle)
	var attached_snapshot: Dictionary=model.snapshot(state,battle)
	check(is_equal_approx(snapshot.b.fire,attached_snapshot.b.fire) and is_equal_approx(snapshot.b.defense,attached_snapshot.b.defense),"read-only guard attributes match the real assault guard")
	sim._detach_city_garrison(battle,attached)
	battle.side_b=[b]; battle.side_b_defends_city=true
	snapshot=model.snapshot(state,battle)
	check(snapshot.field and snapshot.b.size==b.size and snapshot.guard_reserve==1500,"city guards remain separate from real city field participants")
	battle.side_b_defends_city=false
	check(model.snapshot(state,battle).guard_reserve==0,"challengers do not inherit a third-party city's guards")
	battle.field_dice=PackedInt32Array(); snapshot=model.snapshot(state,battle)
	check(not snapshot.dice_ready and battle.field_dice.is_empty(),"unopened battles never roll dice for the UI")
	battle.finished=true; battle.winner_side=2
	check(model.document(state,17).subtitle.contains("挑战方获胜"),"side B victory is shown by actual winner side")
	sim.free(); print("ATLAS_BATTLE_INFORMATION failures=",failures); quit(1 if failures else 0)
