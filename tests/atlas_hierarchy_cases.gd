extends SceneTree
const Hierarchy = preload("res://scripts/atlas/zhoufu.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_HIERARCHY_CASE_FAIL ",message)
func patch_mesh(count: int,origin_x: float = 100.) -> Dictionary:
	var x := PackedFloat32Array(); var y := PackedFloat32Array(); var xyz := PackedFloat32Array(); var start := PackedInt32Array(); var adjacent := PackedInt32Array()
	for cell in range(count):
		x.append(fposmod(origin_x+cell*3.,2048.)); y.append(512.)
		var longitude := x[cell]/2048.*TAU-PI; xyz.append(cos(longitude)); xyz.append(sin(longitude)); xyz.append(0.)
		start.append(adjacent.size())
		if cell>0: adjacent.append(cell-1)
		if cell<count-1: adjacent.append(cell+1)
	start.append(adjacent.size())
	var mesh := {"n":count,"width":2048.,"height":1024.,"x":x,"y":y,"xyz":xyz,"adj_start":start,"adj":adjacent}
	mesh.lengths = Sphere.edge_lengths(mesh); mesh.areas = PackedFloat32Array()
	for _cell in range(count): mesh.areas.append(9.)
	return mesh
func inputs(count: int,origin_x: float = 100.) -> Dictionary:
	var mesh := patch_mesh(count,origin_x)
	var of := PackedInt32Array(); var elevation := PackedFloat32Array(); var water := PackedByteArray(); var suitability := PackedFloat32Array(); var biome := PackedByteArray(); var cells := PackedInt32Array()
	for i in range(count): of.append(0); elevation.append(0.); water.append(0); suitability.append(2.); biome.append(0); cells.append(i)
	return {"mesh":mesh,"env":{"elevation":elevation,"water":water,"biome":biome,"suitability":suitability},
		"regions":{"count":1,"seat":PackedInt32Array([0]),"of":of,"area":PackedFloat32Array([count*9.]),"cellStart":PackedInt32Array([0,count]),"cells":cells},
		"centers":[{"cell":0,"region":0,"major":true,"port":false,"founded":0}]}
func _initialize() -> void:
	for seed_value in [1,7,2024]:
		for count in [1,2,3,12]:
			var p := inputs(count,2046.)
			var h := Hierarchy.build(p.mesh,p.env,p.regions,p.centers,seed_value,1.)
			check(h.members[0].size()<=4,"skinny date-line state bounded settlement count")
			check(h.district_of_cell[0]==0,"center never removed")
			var totals := [0,0,0]
			for city in h.cities:
				for k in range(3): totals[k] += city.budget[k]
			check(totals==[3000,28,680],"small state retains fixed budget")
			if count==1: check(h.cities.size()==1,"one-cell state has zero prefectures")
	var barrier := inputs(12)
	barrier.env.biome[3] = 3
	var h := Hierarchy.build(barrier.mesh,barrier.env,barrier.regions,barrier.centers,1,1.)
	for city in h.cities: check(city.cell<3,"no town beyond impassable divide")
	for district in h.district_of_cell: check(district>=0,"impassable/disconnected parent land still administered")
	var unsuitable := inputs(12)
	for i in range(1,12): unsuitable.env.suitability[i] = 1.
	h = Hierarchy.build(unsuitable.mesh,unsuitable.env,unsuitable.regions,unsuitable.centers,1,1.)
	check(h.cities.size()==1,"strict threshold excludes boundary-equal candidates")
	var empty := Hierarchy.build(unsuitable.mesh,unsuitable.env,unsuitable.regions,[],1,1.)
	check(empty.cities.is_empty() and empty.guardian_by_parent[0]==-1,"no center fabricated when none exists")
	check(Hierarchy.allocate(7,[1.,1.,1.])==PackedInt32Array([3,2,2]),"stable largest remainder ties")
	print("ATLAS_HIERARCHY_CASES failures=",failures); quit(1 if failures else 0)
