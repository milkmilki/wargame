extends SceneTree
var failures:=0
func check(ok:bool,label:String) -> void:
	if not ok:failures+=1;printerr("SURFACE_WATER_FAIL ",label)
func _initialize() -> void:
	var path:="res://scripts/atlas/surface_water.gd"
	if not ResourceLoader.exists(path):check(false,"finite soil/forest water model exists");finish();return
	var model=load(path)
	var empty:Dictionary=model.quarter(0.,0.,200.,1.,20.)
	check(empty.evaporation==0. and empty.runoff==0. and empty.storage==0.,"dry forest cannot invent water")
	var forest:Dictionary=model.quarter(0.,200.,50.,1.,20.)
	var bare:Dictionary=model.quarter(0.,200.,50.,0.,20.)
	check(forest.storage>bare.storage and forest.runoff<bare.runoff,"forest root zone retains more of a wet-season pulse")
	var dry_forest:Dictionary=model.quarter(forest.storage,0.,80.,1.,20.)
	var dry_bare:Dictionary=model.quarter(bare.storage,0.,80.,0.,20.)
	check(dry_forest.evaporation>dry_bare.evaporation and dry_forest.storage<forest.storage,"stored wet-season rain supports subsequent dry-season evapotranspiration")
	for state in [empty,forest,bare,dry_forest,dry_bare]:
		check(state.storage>=0. and state.storage<=state.capacity and state.evaporation>=0. and state.runoff>=0.,"bounded finite water pools")
		check(absf(state.input_storage+state.precipitation-state.storage-state.evaporation-state.runoff)<1e-7,"quarter water ledger closes")
	var frozen:Dictionary=model.quarter(100.,20.,100.,1.,-10.)
	check(frozen.evaporation==0.,"frozen land does not recycle liquid water immediately")
	var wet:Dictionary=model.cycle(PackedFloat32Array([350,100,0,50]),PackedFloat32Array([40,100,150,60]),PackedFloat32Array([10,20,25,15]),1.)
	check(absf(wet.end_storage-wet.start_storage)<.01,"periodic climate root zone reaches a repeating year")
	check(absf(500.+wet.start_storage-wet.end_storage-wet.annual_evaporation-wet.annual_runoff)<.001,"annual surface water ledger closes")
	var drought:Dictionary=model.cycle(PackedFloat32Array([0,0,0,0]),PackedFloat32Array([100,100,100,100]),PackedFloat32Array([20,20,20,20]),1.)
	check(drought.annual_evaporation==0. and drought.annual_runoff==0.,"multi-year dry climate has no persistent free reservoir")
	var rainforest:Dictionary=model.cycle(PackedFloat32Array([1200,1200,1200,1200]),PackedFloat32Array([400,400,400,400]),PackedFloat32Array([25,25,25,25]),1.)
	check(Array(rainforest.storage).min()>50.,"persistent wet-season rainfall must not overflow first and then leave rainforest root zones empty")
	var world=preload("res://scripts/atlas/world.gd").new()
	check(world.has_method("forest_biome"),"generated forest types consume seasonal root-zone diagnostics")
	if world.has_method("forest_biome"):
		check(world.forest_biome(25.,14,.9,.1)==13,"a severe root-zone dry season prevents evergreen rainforest assignment")
		check(world.forest_biome(25.,14,.9,.9)==14,"water-supported rainforest remains rainforest")
		check(world.forest_biome(25.,14,.1,.1)==12,"low cover and dry root zone cannot retain a forest biome")
		check(world.forest_biome(-10.,3,1.,1.)==3,"storage cannot turn permanent ice into forest")
	finish()
func finish() -> void:
	print("ATLAS_SURFACE_WATER failures=",failures);quit(1 if failures else 0)
