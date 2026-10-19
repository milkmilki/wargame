extends SceneTree
## A water channel or land bridge narrower than the ordinary spacing must survive.
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const Maths = preload("res://scripts/atlas/math.gd")
const Coast = preload("res://scripts/atlas/coastline_mesh.gd")
const Raster = preload("res://scripts/atlas/raster.gd")
const Geometry = preload("res://scripts/atlas/surface_geometry.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("COASTLINE_FAIL ",label)

func grid() -> PackedByteArray:
	var water := PackedByteArray(); water.resize(72*36); water.fill(1)
	# Large continent, an east/west sea channel, and a north/south land bridge.
	for y in range(8,28):
		for x in range(18,54): water[y*72+x] = 0
	for x in range(18,54): water[18*72+x] = 1
	for y in range(8,28): water[y*72+36] = 0
	water[12*72+25] = 2 # Lake, independent of the connected ocean.
	water[5*72+10] = 0 # Small island without an interior Poisson sample.
	for y in range(13,23): # Land crosses the date line.
		water[y*72] = 0; water[y*72+71] = 0
	return water

func reaches(mesh: Dictionary, a: int, b: int, kind: int) -> bool:
	var seen := {a:true}; var queue: Array[int] = [a]
	while not queue.is_empty():
		var cell: int = queue.pop_back()
		if cell == b: return true
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if mesh.water[next] == kind and not seen.has(next): seen[next]=true; queue.append(next)
	return false

func near_cell(mesh: Dictionary, x: float, y: float, kind: int) -> int:
	var lon := x/72.*TAU-PI; var lat := PI/2.-y/36.*PI
	var p := Vector3(cos(lat)*cos(lon),cos(lat)*sin(lon),sin(lat))
	var best := -1; var distance := INF
	for id in range(mesh.water.size()):
		if mesh.water[id] != kind: continue
		var q := Vector3(mesh.xyz[id*3],mesh.xyz[id*3+1],mesh.xyz[id*3+2])
		var d := p.distance_squared_to(q)
		if d < distance: distance=d; best=id
	return best

func run() -> void:
	check(ClassDB.class_exists("NativeAtlasMesh"),"coastline triangulation API is available")
	if failures: quit(1); return
	var kernel = ClassDB.instantiate("NativeAtlasMesh")
	var water := grid(); var before := hash(water)
	var partition: Dictionary = kernel.call("partition_water",72,36,water)
	check(not partition.has("error"),"valid sea/land/lake partition is accepted")
	if partition.has("error"): printerr(partition); quit(1); return
	var samples := PackedFloat32Array(Array(Sphere.poisson(.22,Maths.Stream.new(17))))
	var mesh: Dictionary = kernel.call("build_mesh",partition,samples)
	check(not mesh.has("error"),"boundary-constrained sphere is generated")
	if mesh.has("error"): printerr(mesh); quit(1); return
	check(hash(water)==before,"source partition remains immutable")
	var mixed := 0
	for t in range(0,mesh.triangles.size(),3):
		var a: int=mesh.triangles[t]; var b: int=mesh.triangles[t+1]; var c: int=mesh.triangles[t+2]
		if mesh.water[a]!=mesh.water[b] or mesh.water[b]!=mesh.water[c]: mixed+=1
	check(mixed==0,"every triangle and its dual cell shares stay on one side of the coast")
	Coast.finish(mesh,10.)
	var area:=0.; var invalid_area:=0
	for value in mesh.areas:
		area+=value
		if value<=0. or not is_finite(value): invalid_area+=1
	check(invalid_area==0,"every cell has finite positive spherical area")
	check(absf(area-4.*PI*pow(2048./TAU,2))<.1,"cell areas partition the entire sphere exactly once")
	var bad_length:=0
	for value in mesh.lengths:
		if value<=0. or not is_finite(value): bad_length+=1
	check(bad_length==0,"coincident coastal contacts never cause zero-length division")
	var geometry:=Geometry.new(mesh)
	for value in geometry.lengths:
		if value<=0. or not is_finite(value):bad_length+=1
	check(bad_length==0,"environment geometry also handles coastal contact lengths")
	var wrong_nearest:=0
	for latitude in range(8,29,4):
		for longitude in range(8,65,4):
			var px:float=(longitude+.37)/72.*2048.;var py:float=(latitude+.29)/36.*1024.
			var frame:=geometry.point_frame(px,py)
			var actual:=geometry.nearest(px,py,0);var closest:=INF
			for id in range(mesh.n):closest=minf(closest,geometry.point_distance_squared(id,frame))
			if geometry.point_distance_squared(actual,frame)>closest+1e-12:wrong_nearest+=1
	check(wrong_nearest==0,"environmental sampling finds the actual nearest point across constrained coastlines")
	var north:=near_cell(mesh,28.5,15.5,0); var south:=near_cell(mesh,28.5,22.5,0)
	check(reaches(mesh,north,south,0),"one-pixel land bridge connects both continental halves")
	var island:=near_cell(mesh,10.5,5.5,0)
	check(not reaches(mesh,island,north,0),"small island survives without an invented land bridge")
	var channel:=near_cell(mesh,25.5,18.5,1); var sea:=near_cell(mesh,15.5,18.5,1)
	check(reaches(mesh,channel,sea,1),"one-pixel strait remains connected to the sea")
	var lake:=near_cell(mesh,25.5,12.5,2)
	check(lake>=0 and not reaches(mesh,lake,sea,2),"small lake remains separate from ocean")
	check(reaches(mesh,near_cell(mesh,.5,17.5,0),near_cell(mesh,71.5,17.5,0),0),"land remains connected across the date line")
	var seating_mesh:=mesh.duplicate()
	var eligible:=PackedByteArray();eligible.resize(mesh.n);eligible[north]=1;seating_mesh.settlement_sample=eligible
	var suitability:=PackedFloat32Array();suitability.resize(mesh.n);suitability.fill(10.)
	var biomes:=PackedByteArray();biomes.resize(mesh.n)
	var seats:=Roads.seat_cities(seating_mesh,{"water":mesh.water,"biome":biomes,"suitability":suitability},{"count":2,"seat":PackedInt32Array([north,island]),"capacity":PackedFloat32Array([100.,100.])},1.)
	check(seats.size()==1 and seats[0].cell==north,"coastline support points do not independently multiply city candidates")
	var candidate_mesh:Dictionary={"n":3,"settlement_sample":PackedByteArray([1,0,0]),"adj_start":PackedInt32Array([0,1,3,4]),"adj":PackedInt32Array([1,0,2,1]),"lengths":PackedFloat32Array([1.,1.,1.,1.])}
	check(Habitat.settlement_candidates(candidate_mesh,PackedFloat32Array([2.,10.,0.]),PackedByteArray([0,0,1]))==PackedByteArray([0,1,0]),"a sampling slot may move to the shore without adding a second city or crossing water")
	var asymmetric:=0
	for a in range(mesh.water.size()):
		for slot in range(mesh.adj_start[a],mesh.adj_start[a+1]):
			var b: int=mesh.adj[slot]; var found:=false
			for other in range(mesh.adj_start[b],mesh.adj_start[b+1]):
				if mesh.adj[other]==a: found=true; break
			if not found: asymmetric+=1
	check(asymmetric==0,"cell and coastal contact adjacency are symmetric")
	check(hash(Coast.finish(kernel.call("build_mesh",partition,samples),10.))==hash(mesh),"fixed partition and seed reproduce the complete mesh")
	check((kernel.call("partition_water",72,36,PackedByteArray()) as Dictionary).has("error"),"invalid raster fails explicitly")
	var diagonal:=PackedByteArray();diagonal.resize(72*36);diagonal.fill(1)
	diagonal[10*72+20]=0;diagonal[11*72+21]=0
	var diagonal_mesh:Dictionary=kernel.call("build_mesh",kernel.call("partition_water",72,36,diagonal),samples)
	check(not diagonal_mesh.has("error"),"diagonal shoreline junction triangulates")
	if not diagonal_mesh.has("error"):
		check(not reaches(diagonal_mesh,near_cell(diagonal_mesh,20.1,10.1,0),near_cell(diagonal_mesh,21.9,11.9,0),0),"diagonal islands are not joined at their shared corner")
	for kind in range(3):
		var uniform:=PackedByteArray();uniform.resize(72*36);uniform.fill(kind)
		var uniform_mesh:Dictionary=kernel.call("build_mesh",kernel.call("partition_water",72,36,uniform),samples)
		check(not uniform_mesh.has("error"),"uniform class %d closes the sphere without coastline constraints"%kind)
		if not uniform_mesh.has("error"):
			var wrong:=0
			for value in uniform_mesh.water:
				if value!=kind:wrong+=1
			check(wrong==0,"polar cap retains uniform class %d"%kind)
	var detail:=PackedFloat32Array();detail.resize(512*512)
	var jitter:=PackedFloat32Array();jitter.resize(256*256)
	var elevation:=PackedFloat32Array();elevation.resize(mesh.n);elevation.fill(500.)
	var temperature:=PackedFloat32Array();temperature.resize(mesh.n);temperature.fill(15.)
	var rain:=elevation.duplicate();var ice:=PackedFloat32Array();ice.resize(mesh.n)
	mesh.width=144.;mesh.height=72.
	var world:Dictionary={"mesh":mesh,"water":mesh.water,"elevation":elevation,"temperature":temperature,"precipitation":rain,"waterLevel":elevation,"seaIce":ice}
	var base:=Raster.base(world);var pixels:=Raster.pixel_band(world,base,detail,jitter,0,72)
	check(base.holes==0,"coastline-constrained triangles cover the raster without holes")
	var changed:=0
	for pixel in range(pixels.water.size()):
		if pixels.water[pixel]!=mesh.water[base.cell[pixel]]:changed+=1
	check(changed==0,"even a positive interpolated sea floor cannot repaint the authoritative ocean as land")
	print("COASTLINE_MESH checks=",checks," failures=",failures," cells=",mesh.water.size())
	quit(1 if failures else 0)
