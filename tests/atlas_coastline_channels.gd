extends SceneTree
## Real straits represented by the source must survive meshing across seeds.
const Earth=preload("res://scripts/atlas/earth_surface.gd")
const Coast=preload("res://scripts/atlas/coastline_mesh.gd")
const Regions=preload("res://scripts/atlas/regions.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("COAST_CHANNEL_FAIL ",label)
func closest(mesh:Dictionary,lon:float,lat:float,kind:int) -> int:
	var x:=cos(deg_to_rad(lat))*cos(deg_to_rad(lon));var y:=cos(deg_to_rad(lat))*sin(deg_to_rad(lon));var z:=sin(deg_to_rad(lat))
	var best:=-1;var distance:=INF
	for cell in range(mesh.n):
		if mesh.water[cell]!=kind:continue
		var dx:float=mesh.xyz[cell*3]-x;var dy:float=mesh.xyz[cell*3+1]-y;var dz:float=mesh.xyz[cell*3+2]-z
		var d:=dx*dx+dy*dy+dz*dz
		if d<distance:distance=d;best=cell
	return best
func channel(mesh:Dictionary,a:Vector2,b:Vector2,bounds:Rect2) -> bool:
	var first:=closest(mesh,a.x,a.y,1);var last:=closest(mesh,b.x,b.y,1)
	var seen:={first:true};var queue:Array[int]=[first]
	while not queue.is_empty():
		var cell:int=queue.pop_back()
		if cell==last:return true
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next:int=mesh.adj[slot]
			if mesh.water[next]!=1 or seen.has(next):continue
			var point:=Vector2(mesh.x[next]/2048.*360.-180.,90.-mesh.y[next]/1024.*180.)
			if bounds.has_point(point):seen[next]=true;queue.append(next)
	return false
func run() -> void:
	var surface:=Earth.load_surface();var partition:=Coast.partition(surface)
	check(not partition.has("error"),"real coastline partition loads")
	if partition.has("error"):printerr(partition);quit(1);return
	for seed_value in [1,2,3,7,19,97]:
		var mesh:=Coast.build(seed_value,36000,partition)
		check(not mesh.has("error"),"real sphere has valid coastal faces for seed %d"%seed_value)
		if mesh.has("error"):printerr(mesh);continue
		if seed_value in [2,3]:check(mesh.boundary_sample_rejections>0,"nearshore sample rejection repairs the previously inverted mesh, seed %d"%seed_value)
		var land:=Regions.landmasses(mesh,mesh.water)
		check(land.of[closest(mesh,-1.,51.,0)]!=land.of[closest(mesh,1.,49.,0)],"English Channel does not invent a Britain/France land bridge, seed %d"%seed_value)
		check(land.of[closest(mesh,121.,24.,0)]!=land.of[closest(mesh,118.,25.,0)],"Taiwan Strait separates the island from mainland, seed %d"%seed_value)
		check(channel(mesh,Vector2(-6.4,36.2),Vector2(-4.5,36.1),Rect2(-7.,35.2,3.5,1.6)),"Atlantic and Mediterranean connect through Gibraltar locally, seed %d"%seed_value)
		check(channel(mesh,Vector2(-4.,49.),Vector2(2.3,51.5),Rect2(-6.,48.,9.,4.)),"English Channel opens into North Sea locally, seed %d"%seed_value)
	print("COAST_CHANNELS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
