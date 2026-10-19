extends RefCounted
## Earth-only boundary-constrained mesh. Planet generation keeps sphere_mesh.build.
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const Maths = preload("res://scripts/atlas/math.gd")
const MODEL := "atlas-coastline-mesh-v1"

static func kernel():
	if not ClassDB.class_exists("NativeAtlasMesh"): return null
	var instance = ClassDB.instantiate("NativeAtlasMesh")
	return instance if instance.call("api_version")==1 else null

static func partition(surface: Dictionary) -> Dictionary:
	var instance = kernel()
	if instance==null: return {"error":"海陆分割需要重建原生扩展（NativeAtlasMesh API 1）"}
	return instance.call("partition_water",surface.width,surface.height,surface.water)

static func build(seed_value: int,cells: int,coast: Dictionary) -> Dictionary:
	var instance = kernel()
	if instance==null: return {"error":"海岸约束网格需要重建原生扩展（NativeAtlasMesh API 1）"}
	var radius := Sphere.WIDTH/TAU
	var spacing := sqrt(4.*PI*radius*radius*.66/float(cells))
	var samples := PackedFloat32Array(Array(Sphere.poisson(spacing/radius,Maths.Stream.new(Maths.sub_seed(seed_value,"mesh")))))
	var mesh: Dictionary = instance.call("build_mesh",coast,samples)
	if mesh.has("error"): return mesh
	return finish(mesh,spacing)

static func finish(mesh: Dictionary,spacing: float) -> Dictionary:
	var n: int = mesh.n; var xyz: PackedFloat32Array = mesh.xyz
	var x := PackedFloat32Array(); x.resize(n); var y := x.duplicate()
	for id in range(n):
		var lon := Maths.round24(atan2(xyz[id*3+1],xyz[id*3]))
		var lat := Maths.round24(asin(clampf(xyz[id*3+2],-1.,1.)))
		var px := Maths.f32((lon+PI)/TAU*Sphere.WIDTH)
		x[id] = 0. if px>=Sphere.WIDTH else px
		y[id] = (PI/2.-lat)/PI*Sphere.HEIGHT
	mesh.width=Sphere.WIDTH; mesh.height=Sphere.HEIGHT; mesh.spacing=spacing; mesh.x=x; mesh.y=y
	# Wrapped faces first preserves the ordering expected by Atlas drawing.
	var raw: PackedInt32Array=mesh.triangles; var triangles:=PackedInt32Array()
	for wrapped in [true,false]:
		for t in range(0,raw.size(),3):
			var span:=maxf(x[raw[t]],maxf(x[raw[t+1]],x[raw[t+2]]))-minf(x[raw[t]],minf(x[raw[t+1]],x[raw[t+2]]))
			if (span>Sphere.WIDTH/2.)!=wrapped: continue
			triangles.append(raw[t]); triangles.append(raw[t+1]); triangles.append(raw[t+2])
	mesh.triangles=triangles
	mesh.lengths=Sphere.edge_lengths(mesh); mesh.areas=Sphere.cell_areas(mesh)
	return mesh
