extends SceneTree
const Template = preload("res://scripts/atlas/military_template.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_TEMPLATE_FAIL ",message)
func rejected(payload: Dictionary,message: String) -> void:
	var definition := {"format":"world-war-map","version":9,"map_kind":"atlas_military","atlas_payload":Marshalls.raw_to_base64(var_to_bytes(payload))}
	check(not Template.validate(definition).is_empty(),message)
func _initialize() -> void:
	var state := GameState.new()
	state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").military())
	var definition := Template.encode(state); var payload := Template.decode(definition)
	check(Template.validate(definition).is_empty(),"valid template: "+Template.validate(definition))
	for field in ["nations","district_pixels","network","display","strategic_routes"]:
		var previous: Variant = payload[field]; payload[field] = null
		rejected(payload,"missing "+field); payload[field] = previous
	var city: Dictionary = payload.hierarchy.cities[0]
	var cell: int = city.cell; city.cell = -1; rejected(payload,"negative seed cell"); city.cell = cell
	var node: Variant = payload.graph.nodes[0]; payload.graph.nodes[0] = "broken"
	rejected(payload,"non dictionary node"); payload.graph.nodes[0] = node
	var edge: Dictionary = payload.graph.edges[0]
	var temperature: Variant = payload.raster.temp; payload.raster.temp = null
	rejected(payload,"missing display temperature"); payload.raster.temp = temperature
	var forest: Variant = payload.display.forest; payload.display.forest = null
	rejected(payload,"missing forest input"); payload.display.forest = forest
	var endpoint: int = edge.a; edge.a = 0.5; rejected(payload,"fractional endpoint"); edge.a = endpoint
	var path: PackedVector2Array = edge.path; edge.path = PackedVector2Array([Vector2(10,10),Vector2(20,20)])
	rejected(payload,"path detached from graph endpoint"); edge.path = path
	var district: int = payload.hierarchy.district_of_cell[cell]; payload.hierarchy.district_of_cell[cell] = payload.hierarchy.cities.size()
	rejected(payload,"invalid district"); payload.hierarchy.district_of_cell[cell] = district
	print("ATLAS_TEMPLATE_INVALID failures=",failures); quit(1 if failures else 0)
