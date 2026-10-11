extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_TRADE_VIEW_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var module=load("res://scripts/atlas/trade_view.gd")
	if module==null: check(false,"trade region view is missing"); quit(1); return
	var payload: Dictionary=preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	var state := GameState.new(); state.generate_from_atlas(payload)
	var provinces: PackedInt32Array=payload.district_pixels
	var region_by_city := TradeNetwork.trade_region_ids(state)
	var districts: PackedInt32Array=payload.hierarchy.district_of_cell
	var input := {"chains":preload("res://scripts/atlas/borders.gd").trace(payload.data.mesh,districts),"owners":region_by_city,"mesh":payload.data.mesh,"raster":payload.raster,"region_of":districts,"provinces":provinces,"weak":PackedByteArray(),"count":state.region_count}
	input.weak.resize(provinces.size())
	var rng_state:=state.rng.state; var revision:=state.road_network_revision
	var plan: Dictionary=module.calculate(input)
	check(plan.labels.size()==2048*1024 and not plan.lines.is_empty(),"complete region fill and curved borders")
	for c in range(payload.hierarchy.cities.size()):
		var p:=state.cities[c].map_position*Vector2(2048,1024)
		var k:=clampi(floori(p.y),0,1023)*2048+posmod(floori(p.x),2048)
		check(plan.labels[k]==region_by_city[c],"trade center geometry uses actual trade region")
	for line in plan.lines: check(line.left!=line.right,"internal same-region district boundaries are removed")
	check(state.rng.state==rng_state and state.road_network_revision==revision,"view is purely derived")
	var history:=PoliticalHistory.new(); history.reset(state)
	var past:=history.build_view_state(state,0)
	check(past.region_count==state.region_count,"history retains trade region count")
	var original:=state.region_ids.duplicate(); state.region_ids.fill(999); state.region_analysis_revision+=1; state.naming_revision+=1
	var frozen:=history.build_view_state(state,0)
	check(frozen.region_ids==original,"historical trade geometry ignores later live partition")
	print("ATLAS_TRADE_VIEW regions=",state.region_count," lines=",plan.lines.size()," failures=",failures)
	quit(1 if failures else 0)
