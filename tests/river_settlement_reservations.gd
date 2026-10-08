extends SceneTree
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,129.0/255.0))
	var land := PackedByteArray()
	land.resize(1024)
	land.fill(1)
	var river := MapFeatureContract.make_river(0,PackedVector2Array([Vector2(.5,0),Vector2(.5,1)]),"procedural_hydrology")
	var features: Array[Dictionary] = [river]
	var blocked := TerrainMapGenerator.Hydrology.barriers(features,Vector2i(32,32))
	var components := TerrainMapGenerator.Hydrology.components(land,Vector2i(32,32),blocked)
	var environment := {"size":Vector2i(32,32),"components":components,"hydrology":{"features":features,"hydrology_id":"reservation-fixture-main"}}
	var reserved := TerrainMapGenerator._reserve_hydrology_docks(environment,image,1.0,500)
	assert(reserved.size()==1,"one crossing connects the two shores, not a full corridor")
	assert(reserved==TerrainMapGenerator._reserve_hydrology_docks(environment,image,1.0,500))
	var provinces := {"size":Vector2i(32,32),"ids":components}
	var input := TerrainMapGenerator._hydrology_transport_input(provinces,features)
	input.reserved_docks=reserved
	var positions: Array[Vector2]=[Vector2(.25,.5),Vector2(.75,.5)]
	var roads: Array[Dictionary]=[]
	var transport := TerrainMapGenerator._build_boundary_river_transport(image,{"positions":positions,"heights":[0.01,0.01]},roads,provinces,input,2,1.0,2)
	var found := false
	for dock in transport.docks:
		assert(dock.bank_a!=dock.bank_b)
		if dock.position.is_equal_approx(reserved[0].position): found=true
	assert(found,"the reserved crossing must survive optional dock selection")
	river.river_class="minor"
	environment.hydrology.hydrology_id="reservation-fixture-minor"
	assert(TerrainMapGenerator._reserve_hydrology_docks(environment,image,1.0,500).is_empty())
	var source := "res://assets/terrain/eurasia_uniform_river_map_source.json"
	assert(MapSource.validate_manifest(source).is_empty())
	assert(MapSource.river_settlement_model(source)=="uniform_v1")
	assert(MapSource.river_settlement_model()=="flow_weighted")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var path := "user://uniform-invalid-manifest.json"
	manifest.river_settlement_model="unsupported"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	assert(not MapSource.validate_manifest(path).is_empty())
	manifest.river_settlement_model="uniform_v1"
	manifest.erase("hydrology_network")
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	assert(not MapSource.validate_manifest(path).is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("UNIFORM_RESERVATIONS_OK backbone_bound=1 minor=0 manifest_validation=OK")
	quit()
