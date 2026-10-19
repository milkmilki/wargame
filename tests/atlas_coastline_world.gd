extends SceneTree
## Fresh Eurasia generation; never substitutes an older cached world.
const Generator=preload("res://scripts/atlas/generator.gd")
const Military=preload("res://scripts/atlas/military_map.gd")
const Mask=preload("res://scripts/atlas/settlement_mask.gd")
const Coast=preload("res://scripts/atlas/coastline_mesh.gd")
var failures:=0
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("COASTLINE_WORLD_FAIL ",label)
func run() -> void:
	var options:Dictionary={"terrain_model":"earth","rainfall_model":"seasonal_circulation_v5","settlement_model":"climate_capacity_v6","settlement_mask":Mask.EURASIA}
	var base:=Generator.generate(1,1.,func(stage):print("COAST_STAGE ",stage),options)
	check(not base.has("error"),"fresh Earth generation succeeds")
	if base.has("error"):printerr(base);quit(1);return
	check(base.data.mesh.get("model","")==Coast.MODEL,"Earth generation uses the coastline-constrained mesh")
	check(base.data.params.settlement_mask==Mask.EURASIA,"actual generation uses the Eurasia performance mask")
	var mixed_pixels:=0
	for pixel in range(base.raster.water.size()):
		if base.raster.water[pixel]!=base.data.environment.water[base.raster.cell[pixel]]:mixed_pixels+=1
	check(mixed_pixels==0,"raster smoothing and noise preserve the authoritative cell water class")
	var payload:=Military.prepare(base,40)
	check(not payload.has("error"),"original hierarchy and military graph accept the new mesh")
	if payload.has("error"):printerr(payload);quit(1);return
	check(payload.nations.size()==40,"baseline creates forty nations")
	var support_seats:=0
	for city in payload.hierarchy.cities:
		if payload.data.mesh.get("settlement_sample",PackedByteArray())[city.cell]==0:support_seats+=1
	check(support_seats==0,"coastline refinement does not create extra city candidates")
	check(payload.raster.water==base.raster.water,"military preparation cannot paint land across source coastline")
	var bad_land:=0;var bad_sea:=0
	for route in payload.network.connections:
		for cell in route.cells:
			if base.data.environment.water[cell]!=0:bad_land+=1
	for route in payload.shipping.routes:
		for index in range(1,route.cells.size()-1):
			if base.data.environment.water[route.cells[index]]!=1:bad_sea+=1
	check(bad_land==0,"roads use land cells only")
	check(bad_sea==0,"shipping uses ocean cells only")
	check(not payload.shipping.routes.is_empty(),"coastal contact adjacency still produces sea trade")
	var state:=GameState.new();var report:=state.generate_from_atlas(payload)
	check(not report.has("error"),"original runtime import succeeds")
	check(state.territory_structure_valid(),"generated territorial hierarchy is consistent")
	print("COASTLINE_WORLD ",JSON.stringify({"checks":checks,"failures":failures,"cells":base.data.mesh.n,"generation_ms":base.timing,"military_ms":payload.timing,"settlements":payload.hierarchy.cities.size(),"road_edges":payload.graph.edges.size(),"shipping_routes":payload.shipping.routes.size(),"mask":base.data.params.settlement_mask,"seed":base.data.seed,"nations":payload.nations.size()}))
	if failures==0:
		DirAccess.make_dir_recursive_absolute("res://.dbg")
		FileAccess.open("res://.dbg/atlas-military-eurasia-mask.bin",FileAccess.WRITE).store_var(payload,false)
	quit(1 if failures else 0)
