extends SceneTree
## Fresh default Earth, including the real city/road/import/template pipeline.
const Generator=preload("res://scripts/atlas/generator.gd")
const Military=preload("res://scripts/atlas/military_map.gd")
const Mask=preload("res://scripts/atlas/settlement_mask.gd")
const Snapshot=preload("res://scripts/atlas/snapshot.gd")
const Template=preload("res://scripts/atlas/military_template.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	if not ok:failures+=1;printerr("CLIMATE_V6_WORLD_FAIL ",label)
func run() -> void:
	var base:=Generator.generate(1,1.,func(stage):print("CLIMATE_STAGE ",stage),{"terrain_model":"earth","settlement_mask":Mask.EURASIA})
	check(not base.has("error"),"fresh generation succeeds")
	if base.has("error"):printerr(base);quit(1);return
	var data:Dictionary=base.data;var env:Dictionary=data.environment;var n:int=data.mesh.n
	check(data.options.rainfall_model=="seasonal_circulation_v6" and data.options.settlement_model=="climate_capacity_v6","current climate defaults reach the actual generator")
	check(data.params.rainfall_transport.revision==preload("res://scripts/atlas/seasonal_circulation.gd").REVISION,"current physics revision reaches native world metadata")
	check(data.seed==1 and data.params.settlement_mask==Mask.EURASIA and data.options.settlement_mask==Mask.EURASIA,"actual seed and all four Eurasia bounds")
	check(Snapshot.validate_surface_water(env,n).is_empty(),"all generated water fields validate")
	check(env.surface_water_metadata.observed_land_cover==false and env.surface_water_metadata.snowpack==false,"diagnostics disclose potential cover and absent snowpack")
	var maximum_balance_error:=0.;var maximum_annual_error:=0.;var forest_cells:=0;var stored_cells:=0
	for i in range(n):
		if env.water[i]!=0:continue
		maximum_balance_error=maxf(maximum_balance_error,absf(env.precipitation[i]-env.annual_evaporation[i]-env.annual_runoff[i]))
		var p:=0.
		for q in range(4):p+=env.quarter_precipitation[q][i]*.25
		maximum_annual_error=maxf(maximum_annual_error,absf(env.precipitation[i]-p))
		if env.forest_cover[i]>.5:forest_cells+=1
		if env.soil_moisture[0][i]>1.:stored_cells+=1
	check(maximum_balance_error<.01,"annual mesh rainfall equals ET plus runoff at periodic equilibrium")
	check(maximum_annual_error<.01,"rainfall units and quarter mean survive mesh interpolation")
	check(forest_cells>100 and stored_cells>100,"forest and stored moisture exist on real land")
	var original_cover:PackedFloat32Array=env.forest_cover
	var changed:=original_cover.duplicate();changed[0]=NAN;env.forest_cover=changed
	check(not Snapshot.validate_surface_water(env,n).is_empty(),"nonfinite cover is rejected")
	env.forest_cover=original_cover
	var soil:PackedFloat32Array=env.soil_moisture[0];var previous:=soil[0];soil[0]=301.;env.soil_moisture[0]=soil
	check(not Snapshot.validate_surface_water(env,n).is_empty(),"unbounded soil reservoir is rejected")
	soil[0]=previous;env.soil_moisture[0]=soil
	var partial:=env.duplicate();partial.erase("annual_runoff")
	check(not Snapshot.validate_surface_water(partial,n).is_empty(),"partial modern water state is rejected")
	check(Snapshot.validate_surface_water({},n).is_empty(),"legacy worlds without water fields remain readable")
	var payload:=Military.prepare(base,40)
	check(not payload.has("error"),"military graph accepts new climate")
	if payload.has("error"):printerr(payload);quit(1);return
	check(payload.nations.size()==40 and not payload.shipping.routes.is_empty(),"forty nations and sea trade remain available")
	var bad_land:=0;var bad_sea:=0
	for route in payload.network.connections:
		for cell in route.cells:
			if env.water[cell]!=0:bad_land+=1
	for route in payload.shipping.routes:
		for k in range(1,route.cells.size()-1):
			if env.water[route.cells[k]]!=1:bad_sea+=1
	check(bad_land==0 and bad_sea==0,"land and sea routes respect the authoritative coastline")
	var state:=GameState.new();var report:=state.generate_from_atlas(payload)
	check(not report.has("error") and state.territory_structure_valid(),"runtime import and territorial hierarchy are valid")
	var definition:=Template.encode(state)
	check(Template.validate(definition).is_empty(),"new climate survives native template validation")
	var restored:=Template.decode(definition)
	check(restored.data.environment.soil_moisture==env.soil_moisture and restored.data.environment.annual_runoff==env.annual_runoff,"root-zone fields survive template serialization")
	print("CLIMATE_V6_WORLD ",JSON.stringify({"failures":failures,"seed":data.seed,"mask":data.options.settlement_mask,"nations":payload.nations.size(),"cells":n,"generation_ms":base.timing,"military_ms":payload.timing,"settlements":payload.hierarchy.cities.size(),"road_edges":payload.graph.edges.size(),"shipping_routes":payload.shipping.routes.size(),"maximum_water_error_mm":maximum_balance_error,"maximum_annual_error_mm":maximum_annual_error}))
	if failures==0:
		payload.test_climate_source=preload("res://tests/atlas_military_inputs.gd").climate_source_fingerprint()
		DirAccess.make_dir_recursive_absolute("res://.dbg")
		FileAccess.open("res://.dbg/atlas-military-eurasia-climate-v6.bin",FileAccess.WRITE).store_var(payload,false)
	quit(1 if failures else 0)
