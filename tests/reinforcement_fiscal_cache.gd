extends SceneTree
class CountSimulation extends Simulation:
	var fiscal_calls := 0
	var summary_calls := 0
	func _forecast_trade_and_gold_flows(summary_only: bool = false) -> Dictionary:
		fiscal_calls+=1;summary_calls+=int(summary_only)
		return super._forecast_trade_and_gold_flows(summary_only)
class LegacySimulation extends Simulation:
	func _prepare_reinforcement_forecast_cache(_cache: Dictionary) -> void:pass
var checks := 0
var failures: Array[String] = []
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message)
func world(seed_value: int) -> GameState:
	var s:=preload("res://tests/support/grid_world.gd").new();s.generate_world(seed_value,4,32)
	s.trade_enabled=true;s.day=30
	for army in s.armies:army.size=1000;army.state=Army.State.IDLE;army.on_edge=false;army.battle_id=-1
	for nation in s.nations:nation.manpower_pool=5000;nation.treasury_gold=10000
	for city in s.cities:
		if city.has_warehouse:city.food_storage=1000000
	return s
func run():
	var probe:=Simulation.new()
	check(probe.has_method("_prepare_reinforcement_forecast_cache"),"Simulation fiscal adapter exists")
	if not probe.has_method("_prepare_reinforcement_forecast_cache"):probe.free();finish();return
	probe.free()
	for seed_value in [1,7,2024]:
		var actual:=world(seed_value);var expected:=world(seed_value)
		var sim:=CountSimulation.new();sim.setup(actual)
		var legacy:=LegacySimulation.new();legacy.setup(expected)
		sim._resolve_reinforcements();legacy._resolve_reinforcements()
		check(sim.fiscal_calls==1 and sim.summary_calls==0,"monthly batch uses one full fiscal forecast")
		check(var_to_bytes(NativeSnapshotBuilder.build(actual))==var_to_bytes(NativeSnapshotBuilder.build(expected)),"complete synchronous state matches static fiscal baseline")
		var cache:={"__forecast_pending_supply":true}
		var direct:=Simulation.monthly_gold_flows(actual)
		sim.call("_prepare_reinforcement_forecast_cache",cache)
		check(var_to_bytes(cache.monthly_gold_flows)==var_to_bytes(direct),"complete seeded flows equal fresh static fiscal calculation")
		check(cache.__forecast_pending_supply,"seed preserves pending supply flag")
		actual.day+=30;expected.day+=30
		for s in [actual,expected]:
			s.nations[0].treasury_gold=0
			for city in s.cities:city.garrison_manpower+=17
		direct=Simulation.monthly_gold_flows(actual);cache={"__forecast_pending_supply":true}
		sim.call("_prepare_reinforcement_forecast_cache",cache)
		check(var_to_bytes(cache.monthly_gold_flows)==var_to_bytes(direct),"treasury and garrison changes remain exact")
		root.add_child(sim);root.add_child(legacy);sim.paused=true;legacy.paused=true
		await sim._resolve_reinforcements_over_frames();await legacy._resolve_reinforcements_over_frames()
		check(var_to_bytes(NativeSnapshotBuilder.build(actual))==var_to_bytes(NativeSnapshotBuilder.build(expected)),"sliced monthly state matches static fiscal baseline")
		sim.queue_free();legacy.queue_free();await process_frame
	var idle:=CountSimulation.new();idle.setup(world(99))
	for army in idle.state.armies:army.size=army.max_size
	idle.fiscal_calls=0;idle.summary_calls=0
	idle._resolve_reinforcements()
	check(idle.fiscal_calls==0,"no refill plan does not prepare unused fiscal data")
	idle.free();finish()
func finish():
	print("REINFORCEMENT_FISCAL_CACHE checks=%d failures=%d"%[checks,failures.size()])
	for failure in failures:print("FAIL ",failure)
	quit(0 if failures.is_empty() else 1)
