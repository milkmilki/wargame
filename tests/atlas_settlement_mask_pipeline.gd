extends SceneTree
const Generator = preload("res://scripts/atlas/generator.gd")
const Map = preload("res://scripts/atlas/military_map.gd")
const Mask = preload("res://scripts/atlas/settlement_mask.gd")
var failures := 0
var checks := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("ATLAS_MASK_PIPELINE_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var base := Generator.generate(1,1.,func(stage): print("MASK_STAGE ",stage),{"terrain_model":"earth","rainfall_model":"seasonal_circulation_v5","settlement_model":"climate_capacity_v6","settlement_mask":Mask.EURASIA})
	check(not base.has("error"),"native full-size generation succeeds")
	if base.has("error"): quit(1); return
	var data: Dictionary=base.data
	check(data.options.settlement_mask==Mask.EURASIA and data.params.settlement_mask==Mask.EURASIA,"actual mask stored in both options and parameters")
	var outside := 0
	for cell in range(data.mesh.n):
		if not Mask.contains_cell(data.mesh,cell,Mask.EURASIA):
			outside+=1; check(data.environment.suitability[cell]==0. and data.environment.capacity[cell]==0.,"outside suitability and capacity zero: %d"%cell)
	for city in data.cities: check(Mask.contains_cell(data.mesh,city.cell,Mask.EURASIA),"all province seats inside")
	var original: Dictionary=preload("res://tests/atlas_military_inputs.gd").base()
	check(data.mesh.x==original.data.mesh.x and data.mesh.y==original.data.mesh.y,"the mask preserves the original spherical grid")
	for field in ["elevation","water","temperature","biome","quarter_precipitation","seasonal_winds","climate_suitability"]:
		check(var_to_bytes(data.environment[field])==var_to_bytes(original.data.environment[field]),"climate/terrain unchanged: "+field)
	var pixels := Generator.pixel_regions(data,base.raster)
	var snapshot := {"format":"atlas-preview","version":1,"data":data,"display":base.display,"raster":base.raster,"provinces":pixels}
	var error := preload("res://scripts/atlas/snapshot.gd").validate(snapshot)
	check(error.is_empty(),"masked preview validates: "+error)
	var payload := Map.prepare(base)
	check(not payload.has("error"),"masked military hierarchy succeeds")
	if payload.has("error"): quit(1); return
	for city in payload.hierarchy.cities: check(Mask.contains_cell(data.mesh,city.cell,Mask.EURASIA),"all zhou and fu inside")
	var empty := base.duplicate(); empty.data=data.duplicate(); empty.data.cities=[]
	check(Map.prepare(empty).has("error"),"no eligible seats reports an error instead of importing an empty military world")
	var state := GameState.new(); state.generate_from_atlas(payload)
	var definition := MapDefinition.from_state(state)
	error=MapDefinition.validate(definition); check(error.is_empty(),"masked military template validates: "+error)
	var restored := GameState.new(); restored.generate_from_map_definition(JSON.parse_string(JSON.stringify(definition)))
	check(restored.atlas_layout.data.options.settlement_mask==Mask.EURASIA and restored.cities.size()==state.cities.size(),"mask and settlements survive template roundtrip")
	var history := PoliticalHistory.new(); history.reset(state)
	check(history.build_view_state(state,0).atlas_layout.data.options.settlement_mask==Mask.EURASIA,"history retains generation mask")
	var malformed := definition.duplicate(true)
	var malformed_payload := preload("res://scripts/atlas/military_template.gd").decode(definition)
	malformed_payload.data.options.settlement_mask.north=-40.
	malformed.atlas_payload=Marshalls.raw_to_base64(var_to_bytes(malformed_payload))
	check(not MapDefinition.validate(malformed).is_empty(),"malformed saved mask rejected")
	DirAccess.make_dir_recursive_absolute("res://.dbg")
	FileAccess.open("res://.dbg/atlas-military-eurasia-mask.bin",FileAccess.WRITE).store_var(payload,false)
	var report := {"seed":1,"mask":Mask.EURASIA,"godot":Engine.get_version_info(),"checks":checks,"failures":failures,"outside_cells":outside,"cells":data.mesh.n,"regions":data.regions.count,"zhou":payload.hierarchy.members.size(),"settlements":payload.hierarchy.cities.size(),"nodes":payload.graph.nodes.size(),"road_segments":payload.graph.edges.size(),"generation_ms":base.timing,"military_ms":payload.timing,"global_zhou":original.data.cities.size()}
	FileAccess.open("res://.dbg/atlas-settlement-mask-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ATLAS_SETTLEMENT_MASK_PIPELINE ",JSON.stringify(report)); quit(1 if failures else 0)
