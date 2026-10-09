extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; print("ZHOUFU_FAIL ", message)
func _initialize() -> void:
	var builder = load("res://scripts/atlas/zhoufu.gd")
	if builder == null: print("ZHOUFU_FAIL missing native hierarchy builder"); quit(1); return
	var payload: Dictionary = preload("res://tests/atlas_military_inputs.gd").base()
	var data: Dictionary = payload.get("data",payload)
	var original := var_to_bytes(data.regions)
	var climate := var_to_bytes(data.environment)
	var h: Dictionary = builder.build(data.mesh,data.environment,data.regions,data.cities,1,1.0)
	check(h.cities.size() >= data.cities.size(),"all original centers retained")
	check(h.cities.size()>data.cities.size(),"eligible Earth states gain prefectures")
	for state in range(h.members.size()):
		check(h.members[state].size()<=4,"at most three prefectures")
		for c in h.members[state]:
			if c==state: continue
			var count := 0
			for cell in h.district_of_cell: count += 1 if cell==c else 0
			check(count>=2,"prefecture has at least two land cells")
	check(var_to_bytes(data.regions)==original and var_to_bytes(data.environment)==climate,"parent geometry and climate immutable")
	for c in range(data.cities.size()):
		check(h.cities[c].cell==data.cities[c].cell and h.center_by_city[c]==c,"original centers and their order retained")
	var total := [0,0,0]
	for c in range(h.cities.size()):
		var city: Dictionary = h.cities[c]
		check(data.regions.of[city.cell]==city.region,"settlement stays in parent")
		check(h.district_of_cell[city.cell]==c,"settlement owns seed")
		check(data.environment.suitability[city.cell]>1.,"settlement eligibility")
		for k in range(3): total[k] += city.budget[k]
	check(total==[data.cities.size()*3000,data.cities.size()*28,data.cities.size()*680],"fixed global budget conserved")
	for i in range(data.mesh.n):
		if data.environment.water[i]!=0: check(h.district_of_cell[i]==-1,"water never assigned"); continue
		var parent: int = data.regions.of[i]
		if parent<0: continue
		check(h.district_of_cell[i]>=0,"all parent land assigned")
		var district: int = h.district_of_cell[i]
		if h.state_by_parent[parent]>=0: check(h.cities[district].region==parent,"child never crosses parent boundary")
	var repeated: Dictionary = builder.build(data.mesh,data.environment,data.regions,data.cities,1,1.)
	check(var_to_bytes(h)==var_to_bytes(repeated),"deterministic hierarchy")
	print("ATLAS_ZHOUFU centers=",data.cities.size()," settlements=",h.cities.size()," failures=",failures)
	quit(1 if failures else 0)
