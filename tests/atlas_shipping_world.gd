extends SceneTree
const Inputs = preload("res://tests/atlas_military_inputs.gd")
const Shipping = preload("res://scripts/atlas/shipping.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("SHIPPING_WORLD_FAIL ",message)
func run():
	var payload := Inputs.eurasia_military()
	var source_hash := hash(payload)
	var without := payload.duplicate()
	without.shipping={"version":Shipping.VERSION,"ports":[],"routes":[],"fingerprint":"disabled"}
	var land := GameState.new(); land.generate_from_atlas(without)
	var world := GameState.new(); world.generate_from_atlas(payload)
	check(world.region_ids==land.region_ids and world.administrative_center_by_city==land.administrative_center_by_city,"trade/admin/state partitions remain exactly land-derived")
	check(TradeNetwork.trade_region_ids(world)==TradeNetwork.trade_region_ids(land),"trade market partitions do not use shipping")
	check(world.rng.state==land.rng.state,"shipping never consumes simulation randomness")
	check(world.cities.map(func(c):return [c.name,c.short_name,c.gold_per_month,c.manpower_per_month,c.food_per_half_year])==land.cities.map(func(c):return [c.name,c.short_name,c.gold_per_month,c.manpower_per_month,c.food_per_half_year]),"names and city base attributes are independent of shipping")
	check(world.edges.size()==land.edges.size(),"shipping does not add military edges")
	for id in range(world.cities.size()): check(world.strategic_neighbors(id)==land.strategic_neighbors(id),"military strategic adjacency remains land-only")
	var routes: Array=world.atlas_layout.shipping.routes
	check(not routes.is_empty(),"real Eurasia has generated sea routes")
	for route in routes:
		for index in range(1,route.cells.size()-1): check(payload.data.environment.water[route.cells[index]]==1,"real shipping does not cut through land or lakes")
	var network := TradeNetwork.build(world)
	var water_count := 0
	for route in network.routes:
		if route.get("uses_water",false): water_count+=1
	check(water_count>0,"actual settled regional trade is allowed to use sea links")
	var land_network := TradeNetwork.build(land)
	check(network.routes.map(func(route):return [route.city_path,route.transport_cost,route.gold])!=land_network.routes.map(func(route):return [route.city_path,route.transport_cost,route.gold]),"sea trade changes actual routes/costs/returns while regional partitions stay fixed")
	check(hash(payload)==source_hash,"shipping leaves the cached source payload unchanged")
	print("SHIPPING_WORLD checks=",checks," failures=",failures," shipping_routes=",routes.size()," ports=",world.atlas_layout.shipping.ports.size()," trade_routes=",network.routes.size()," sea_trade_routes=",water_count)
	quit(1 if failures else 0)
