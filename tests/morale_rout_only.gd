extends SceneTree
var failures := 0
func _initialize():
	create_timer(15.).timeout.connect(func(): printerr("MORALE_ROUT_ONLY_TIMEOUT"); quit(1))
	call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("MORALE_ROUT_ONLY_FAIL ",message)
func troop(id: int,size: int,morale: float) -> Army:
	var army:=Army.new(); army.id=id; army.size=size; army.max_size=size; army.morale=morale
	army.attack=14; army.defense=12; army.supply_ratio=.75; army.funding_multiplier=.8
	army.ruler_attack_multiplier=1.2; army.ruler_defense_multiplier=1.1
	return army
func fixture(morale: float,kind: int,guard: bool = false) -> Battle:
	var battle:=Battle.new(); battle.kind=kind; battle.id=7
	battle.edge=Edge.new(); battle.edge.max_manpower=9000; battle.edge.danger=.6
	battle.holding_side=2; battle.holding_days=10.
	battle.side_a=[troop(1,12000,morale),troop(2,8000,morale)]
	battle.side_b=[troop(3,18000,1.5)]
	if kind==Battle.Kind.SIEGE:
		battle.city=City.new(); battle.side_b_defends_city=true
	if guard:
		battle.side_b[0].is_city_garrison=true; battle.side_b[0].max_morale=1.
		battle.side_b[0].city_garrison_combat_multiplier=.7
	battle.field_dice=PackedInt32Array([3,7,2,8]); battle.assault_dice=battle.field_dice.duplicate()
	return battle
func record(battle: Battle) -> Dictionary:
	Combat.clear_battle_log(); Combat.resolve_round(battle,1)
	return Combat.battle_log.back().duplicate(true)
func run():
	Combat.battle_log_enabled=true
	for configuration in [[Battle.Kind.FIELD,false],[Battle.Kind.SIEGE,false],[Battle.Kind.SIEGE,true]]:
		var low:=fixture(.4,configuration[0],configuration[1])
		var high:=fixture(1.5,configuration[0],configuration[1])
		var low_power:=ArmyPower.effective(low.side_a[0]); var high_power:=ArmyPower.effective(high.side_a[0])
		check(is_equal_approx(low_power,high_power),"AI quality does not discount morale, mode=%s"%str(configuration))
		check(is_equal_approx(Combat._side_attack(low.side_a),Combat._side_attack(high.side_a)),"side attack is independent of morale")
		check(is_equal_approx(Combat._side_residual(low.side_a),Combat._side_residual(high.side_a)),"simultaneous rout tie strength is independent of morale")
		var first:=record(low); var second:=record(high)
		for field in ["effective_attack_a","effective_attack_b","effective_defense_a","effective_defense_b","casualties_a","casualties_b","frontline_strength_a","frontline_strength_b"]:
			check(first[field]==second[field],"morale does not alter %s, mode=%s"%[field,configuration])
		check(not low.finished and not high.finished,"power comparison happens before either side routes")
		check(first.morale_after_a<second.morale_after_a,"morale is still tracked separately")
	var broken:=fixture(.14,Battle.Kind.FIELD)
	var healthy:=fixture(1.5,Battle.Kind.FIELD)
	record(broken); record(healthy)
	check(broken.finished and broken.winner_side==2 and not healthy.finished,"morale still determines side collapse and winner")
	for morale_pair in [[.01,.14],[.14,.01]]:
		var simultaneous:=fixture(morale_pair[0],Battle.Kind.FIELD)
		simultaneous.side_b[0].morale=morale_pair[1]; record(simultaneous)
		check(simultaneous.finished and simultaneous.winner_side==1,"simultaneous collapse compares remaining strength without discounting either morale")
	var assault:=fixture(.01,Battle.Kind.SIEGE,true); var routed: Army=assault.side_a[0]
	assault.side_a[1].morale=1.5; record(assault)
	check(assault.routed_a.has(routed) and not assault.side_a.has(routed),"garrison assault still removes individually routed formations")
	var state:=GameState.new(); var battle:=fixture(.4,Battle.Kind.FIELD); state.battles=[battle]
	for index in range(2):
		var city:=City.new(); city.id=index; city.map_position=Vector2(.4+index*.1,.5); state.cities.append(city)
	battle.edge.city_a=0; battle.edge.city_b=1
	var model=preload("res://scripts/atlas/battle_information.gd")
	var first: Dictionary=model.snapshot(state,battle); var doc: Dictionary=model.document(state,7)
	for army in battle.side_a: army.morale=1.5
	var second: Dictionary=model.snapshot(state,battle)
	check(first.a.fire==second.a.fire and first.a.defense==second.a.defense,"details show actual morale-independent power")
	check(not doc.sections[0].rows.any(func(row): return row.label=="士气战斗效率"),"details omit the obsolete morale power multiplier")
	check(doc.notice.contains("士气") and doc.notice.contains("溃败"),"details explain the remaining morale role")
	Combat.battle_log_enabled=false; Combat.clear_battle_log()
	print("MORALE_ROUT_ONLY failures=",failures); quit(1 if failures else 0)
