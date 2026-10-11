extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_INFO_FAIL ",message)
func value(document: Dictionary,label: String) -> String:
	for section in document.get("sections",[]):
		for row in section.rows:
			if row.label==label: return str(row.value)
	return ""
func campaign_value(document: Dictionary,label: String) -> String:
	for section in document.get("sections",[]):
		if section.title!="州战役": continue
		for row in section.rows:
			if row.label==label: return row.value
	return ""
func _initialize():
	if not FileAccess.file_exists("res://scripts/atlas/information_model.gd"):
		printerr("ATLAS_INFO_FAIL structured city/nation information is absent"); quit(1); return
	var model = load("res://scripts/atlas/information_model.gd")
	var state := GameState.new()
	for i in range(2):
		var nation := Nation.new(); nation.id=i; nation.name="国%d"%i; nation.capital_city_id=i*2; nation.warehouse_city_ids=[i*2]; state.nations.append(nation)
	for i in range(4):
		var city := City.new(); city.id=i; city.name="城%d"%i; city.owner_nation=0 if i<2 else 1
		city.manpower_per_month=123; city.gold_per_month=7; city.food_per_half_year=60; state.cities.append(city)
	state.cities[3].node_kind=City.NodeKind.TRAFFIC
	state.recognized_city_owners=[0,0,1,1]
	state.administrative_center_by_city=PackedInt32Array([0,0,2,-1]); state.administrative_region_ids=PackedInt32Array([0,0,1,-1])
	state.cities[0].food_storage=456; state.nations[0].granary_food=999999
	var army := Army.new(); army.id=9; army.owner_nation=0; army.location_city=1; army.size=321; state.armies.append(army)
	var random_state: int = state.rng.state
	var city: Dictionary = model.city(state,1)
	check(city.title=="城1" and value(city,"月人口产出")=="123","city reports actual production, not fictitious population")
	check(value(city,"隶属州治")=="城0","fixed administrative center is linked")
	check(model.city(state,3).is_empty(),"traffic nodes are not presented as cities")
	var nation: Dictionary = model.nation(state,0)
	check(value(nation,"控制治所")=="2","country counts exclude traffic nodes")
	check(value(nation,"粮仓库存")=="456","food comes from warehouse truth, not stale derived cache")
	check(value(nation,"野战兵力")=="321","live troops use the actual army records")
	check(campaign_value(nation,"进行中")=="暂无州战役","nation card explicitly reports no state campaigns")
	check(model.army(state,9).title=="军队9","army lookup uses stable ID, not array offset")
	check(value(model.army(state,9),"战斗")=="未交战","unbound military state is readable")
	army.campaign_war_id=0
	check(value(model.army(state,9),"战争")=="1","displayed war number follows the existing ID-plus-one convention")
	state.cities[1].owner_nation=1
	check(value(model.city(state,1),"实控国家")=="国1" and value(model.city(state,1),"法理国家")=="国0","occupation distinguishes controller and legal owner")
	check(state.rng.state==random_state and state.cities[0].food_storage==456,"information queries do not mutate simulation or random flow")
	check(model.nation(state,-1).is_empty() and model.army(state,99).is_empty(),"stale selections are handled")
	var front := state.create_campaign_front(0,[0,1] as Array[int],0,CoalitionCampaignFront.Mode.OFFENSE,2)
	front.phase=CoalitionCampaignFront.Phase.RAID_FU; front.staging_city_id=0
	front.tactical_target_city_ids=[2]; front.army_assignments={9:2,12345:2}
	front.reported_effective_manpower=999999; front.combat_report_locked=true
	army.campaign_front_id=front.front_id
	var ally := Army.new(); ally.id=10; ally.owner_nation=1; ally.size=1000
	ally.campaign_front_id=front.front_id; ally.campaign_war_id=0; state.armies.append(ally)
	var stale := Army.new(); stale.id=11; stale.owner_nation=0; stale.size=5000
	stale.campaign_front_id=front.front_id; stale.campaign_war_id=99; state.armies.append(stale)
	var defense := state.create_campaign_front(1,[0] as Array[int],0,CoalitionCampaignFront.Mode.DEFENSE,0)
	defense.phase=CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE
	var retired := state.create_campaign_front(2,[0] as Array[int],0,CoalitionCampaignFront.Mode.OFFENSE,2); retired.retiring=true
	state.create_campaign_front(3,[1] as Array[int],1,CoalitionCampaignFront.Mode.OFFENSE,0)
	var document: Dictionary=model.nation(state,0)
	check(campaign_value(document,"进行中")=="2场 · 进攻1／防守1","only this country's active shared fronts appear")
	check(campaign_value(document,"战役0")=="进攻 · 战争1","war numbering and attack role are readable")
	check(campaign_value(document,"当前阶段")=="争夺属府","campaign phase is localized")
	check(campaign_value(document,"本国投入")=="1支 · 321人" and campaign_value(document,"战线总兵力")=="2支 · 1321人","live bindings separate national and allied troops, exclude stale war ids and perception snapshots")
	var linked := false
	for group in document.sections:
		if group.title=="州战役":
			for r in group.rows:
				if r.label=="目标州" and r.id==2 and r.kind=="city": linked=true
	check(linked,"state campaign objective links to its state seat")
	check(campaign_value(model.nation(state,1),"战役0")=="进攻 · 战争1","allied participants can inspect the shared campaign")
	army.size=123; front.phase=CoalitionCampaignFront.Phase.ASSAULT_CENTER
	document=model.nation(state,0)
	check(campaign_value(document,"本国投入")=="1支 · 123人" and campaign_value(document,"当前阶段")=="强攻州治","casualties and phase changes refresh from current truth")
	check(front.army_assignments=={9:2,12345:2} and state.rng.state==random_state,"campaign presentation does not replan or mutate bindings")
	if not model.get_script_method_list().any(func(m): return m.name=="historical"):
		check(false,"political snapshots must not present live economic/army values as historical")
	else:
		var past: Dictionary=model.historical(model.nation(state,0),"nation")
		check(value(past,"粮仓库存").is_empty() and value(past,"野战兵力").is_empty(),"uncaptured history values are omitted")
		check(not value(past,"经济与兵力").is_empty(),"the historical recording limit is explained")
		check(not past.sections.any(func(s): return s.title=="州战役") and value(past,"州战役")=="此政治快照未记录","history never substitutes live campaign data")
	print("ATLAS_INFORMATION_MODEL failures=",failures); quit(1 if failures else 0)
