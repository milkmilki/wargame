extends SceneTree
const Reference = preload("res://tests/support/trade_fingerprint_reference.gd")
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok: failures.append(label)
func dependency(state: GameState,change: Callable,restore: Callable,label: String):
	var old_before := Reference.fingerprint(state); var new_before := TradeNetwork.structure_fingerprint(state)
	change.call()
	var old_after := Reference.fingerprint(state); var new_after := TradeNetwork.structure_fingerprint(state)
	check((old_before==old_after)==(new_before==new_after),"same dependency partition: "+label)
	check(original_bytes(new_after)==old_after,"every mutated dependency reconstructs exactly: "+label)
	restore.call()
	check(Reference.fingerprint(state)==old_before and TradeNetwork.structure_fingerprint(state)==new_before,"exact restore: "+label)
func original_bytes(packed: PackedByteArray) -> PackedByteArray:
	var fields: Array = bytes_to_var(packed);var expanded: Array = []
	for field in fields:
		if field is Array and field.size()>1 and field[0]=="cities_packed":
			var records: PackedInt64Array = field[1];var positions: PackedVector2Array = field[2]
			for i in range(positions.size()):
				var o := i*14
				expanded.append(["city",records[o],records[o+1],bool(records[o+2]),records[o+3],positions[i],records[o+4],records[o+5],records[o+6],bool(records[o+7]),bool(records[o+8]),bool(records[o+9]),bool(records[o+10]),bool(records[o+11]),records[o+12],records[o+13]])
		elif field is Array and field.size()>1 and field[0]=="edges_packed":
			var records: PackedInt64Array = field[1];var values: PackedFloat64Array = field[2]
			for i in range(records.size()/8):
				var o := i*8;var f := i*4
				expanded.append(["edge",records[o],records[o+1],records[o+2],records[o+3],records[o+4],records[o+5],values[f],records[o+6],values[f+1],values[f+2],values[f+3],records[o+7]])
		else: expanded.append(field)
	expanded[0]="trade_structure_v5"
	return var_to_bytes(expanded)
func run():
	for seed_value in [1,7,2024]:
		var state := preload("res://tests/support/grid_world.gd").new(); state.generate_world(seed_value,4,32);state.trade_enabled=true
		var fields: Array = bytes_to_var(TradeNetwork.structure_fingerprint(state))
		var city_packed := false; var edge_packed := false
		for field in fields:
			if field is Array and field.size()>1:
				if field[0]=="cities_packed": city_packed = field[1] is PackedInt64Array and field[2] is PackedVector2Array
				if field[0]=="edges_packed": edge_packed = field[1] is PackedInt64Array and field[2] is PackedFloat64Array
		check(city_packed and edge_packed,"city and edge records stored in contiguous exact arrays")
		if city_packed and edge_packed: check(original_bytes(TradeNetwork.structure_fingerprint(state))==Reference.fingerprint(state),"all original dependencies reconstruct byte for byte")
		var city := state.cities[0]; var edge := state.edges[0]; var nation := state.nations[0]
		for property in ["gold_per_month","food_per_half_year","owner_nation","id","node_kind"]:
			var saved = city.get(property)
			dependency(state,func():city.set(property,int(saved)+1),func():city.set(property,saved),property)
		for property in ["is_capital","has_warehouse","is_port_market","is_crossroads","is_food_hub"]:
			var saved = city.get(property)
			dependency(state,func():city.set(property,not bool(saved)),func():city.set(property,saved),property)
		for property in ["max_manpower","base_max_manpower","distance","control_city_id","kind","road_tier"]:
			var saved = edge.get(property)
			for value in [0,-1,1<<32,(1<<54)+1]:
				dependency(state,func():edge.set(property,value),func():edge.set(property,saved),property+str(value))
		for property in ["precise_distance","travel_time_multiplier","danger","supply_loss_multiplier"]:
			var saved = edge.get(property)
			for value in [0.0,-0.0,.123456789012345,INF,-INF,NAN]:
				dependency(state,func():edge.set(property,value),func():edge.set(property,saved),property+str(value))
			dependency(state,func():edge.set(property,float(saved)+1e-14),func():edge.set(property,saved),"sub-float32 "+property)
		var saved_position := city.map_position
		dependency(state,func():city.map_position+=Vector2(.125,-.25),func():city.map_position=saved_position,"position")
		var saved_capital := nation.capital_city_id
		dependency(state,func():nation.capital_city_id+=1,func():nation.capital_city_id=saved_capital,"capital")
		var saved_gold := city.gold_per_month;city.gold_per_month=1<<54
		dependency(state,func():city.gold_per_month+=1,func():city.gold_per_month=1<<54,"adjacent 64-bit integers")
		city.gold_per_month=saved_gold
		dependency(state,func():state.edges.reverse(),func():state.edges.reverse(),"edge order")
		dependency(state,func():state.region_ids[0]+=1,func():state.region_ids[0]-=1,"region")
		var meta = city.get_meta("initial_owner_city",-1)
		dependency(state,func():city.set_meta("initial_owner_city",123),func():city.set_meta("initial_owner_city",meta),"initial owner metadata")
		var expected := TradeNetwork.build_structure(state,true,{}, {},Reference.fingerprint(state))
		var actual := TradeNetwork.build_structure(state)
		expected.fingerprint=actual.fingerprint
		check(var_to_bytes(expected)==var_to_bytes(actual),"complete route structure matches original fingerprint")
	var atlas := GameState.new(); atlas.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").eurasia_military()); atlas.trade_enabled=true
	for mutation in ["initial","war","conquest","policy"]:
		if mutation == "war": atlas.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
		if mutation == "conquest":
			var city := atlas.cities[atlas.administrative_center_city_ids[0]]
			var transfer := atlas.transfer_city_control(city.id,1,1,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"packed_fingerprint_test")
			check(bool(transfer.get("ok",false)),"actual ownership transfer")
		if mutation == "policy": atlas.nations[0].trade_policy=TradeNetwork.GOLD
		check(original_bytes(TradeNetwork.structure_fingerprint(atlas))==Reference.fingerprint(atlas),"Atlas original fields reconstruct byte for byte")
		var expected := TradeNetwork.build_structure(atlas,true,{}, {},Reference.fingerprint(atlas))
		var actual := TradeNetwork.build_structure(atlas); expected.fingerprint=actual.fingerprint
		check(var_to_bytes(actual)==var_to_bytes(expected),"full Atlas structure preserves "+mutation)
	var empty := GameState.new()
	check(not TradeNetwork.structure_fingerprint(empty).is_empty(),"empty world fingerprint")
	check(not TradeNetwork.structure_fingerprint(null).is_empty(),"null world fingerprint")
	for failure in failures: printerr("TRADE_PACKED_FINGERPRINT_FAIL ",failure)
	print("TRADE_PACKED_FINGERPRINT_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
