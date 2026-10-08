extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	# Three valid banks, no initial roads. A large interval gives one regular
	# ferry, so the remaining bank needs exactly one extra crossing.
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,.54))
	var positions: Array[Vector2] = [Vector2(.3,.25),Vector2(.3,.75),Vector2(.7,.5)]
	var ids := PackedInt32Array(); ids.resize(1024)
	for y in range(32):
		for x in range(32): ids[y*32+x]=2 if x>=16 else (0 if y<16 else 1)
	var provinces := {"size":Vector2i(32,32),"ids":ids}
	var feature := MapFeatureContract.make_river(1,PackedVector2Array([Vector2(.5,.2),Vector2(.5,.8)]),MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)
	var input := {"features":[feature],"navigation_image":image,"local_navigation":false,"river_pair_keys":{},"paths":MapFeatureContract.major_paths([feature])}
	var candidates: Array[Dictionary] = []
	for entry in [{"y":.3,"bank":0},{"y":.7,"bank":1}]:
		candidates.append({"river_id":1,"river_progress":(entry.y-.2)/.6,"position":Vector2(.5,entry.y),"pixel_position":Vector2(.5,entry.y)*32-Vector2(.5,.5),"height":.07,"relief":0.0,"bank_a":entry.bank,"bank_b":2,"reference_bank":entry.bank,"cell_a":Vector2i(15,int(entry.y*32)),"cell_b":Vector2i(16,int(entry.y*32)),"lowland":true})
	var roads: Array[Dictionary] = []
	var result := TerrainMapGenerator._build_spaced_ferries(image,provinces,positions,roads,input,candidates,3,1,1)
	assert(result.diagnostics.regular==1 and result.diagnostics.necessary==1,"one regular / one necessary ferry")
	var required: Array[int] = [0,1,2]
	assert(TerrainMapGenerator._ferry_mainland_connected(roads,result.docks,input,1,3,required))
	for i in range(result.docks.size()):
		if result.docks[i].ferry_reason!="connectivity": continue
		var trial: Array[Dictionary] = result.docks.duplicate(); trial.remove_at(i)
		assert(not TerrainMapGenerator._ferry_mainland_connected(roads,trial,input,1,3,required),"retained supplement is individually necessary")
	# Exercise actual landing-road creation as well as component selection.
	var river := {"river_id":1,"path":feature.points,"pixel_path":[],"edge_indices":[],"dock_samples":[{"path_index":0,"ratio":1.0/6.0,"graph_index":0},{"path_index":0,"ratio":5.0/6.0,"graph_index":1}],"hydrological":true,"strict_transport":false}
	var rivers: Array[Dictionary] = [river]
	var segments: Array[Dictionary] = [{"a":0,"b":2,"cell_a":Vector2i(15,9),"cell_b":Vector2i(16,9)},{"a":1,"b":2,"cell_a":Vector2i(15,22),"cell_b":Vector2i(16,22)}]
	input.merge({"rivers":rivers,"graph":{"segments":segments},"ferry_interval":1.0,"hydrological":true},true)
	var samples := {"positions":positions,"heights":[.07,.07,.07]}
	var built := TerrainMapGenerator._build_boundary_river_transport(image,samples,roads,provinces,input,3,1,1)
	assert(built.get("ok",true),str(built.get("error","")))
	assert(built.ferry_spacing.necessary==1 and built.roads.size()>=4,"supplement reaches both real bank cities")
	input["ferry_max_per_river"]=2
	var capped := TerrainMapGenerator._build_spaced_ferries(image,provinces,positions,roads,input,candidates,3,1,1)
	assert(capped.diagnostics.total==2 and capped.diagnostics.necessary==1,"regular and necessary ferry share quota")
	input["ferry_max_per_river"]=1
	var exhausted := TerrainMapGenerator._build_spaced_ferries(image,provinces,positions,roads,input,candidates,3,1,1)
	assert(exhausted.docks.size()==1,"exhausted quota never adds an illegal exception")
	assert(not TerrainMapGenerator._ferry_mainland_connected(roads,exhausted.docks,input,1,3,required),"unconnectable capped result is rejected by final connectivity check")
	print("RIVER_FERRY_CONNECTIVITY_OK ",result.diagnostics)
	quit(0)
