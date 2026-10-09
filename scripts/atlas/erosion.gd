extends RefCounted
## civ-atlas gen/erosion.ts Priority-Flood and implicit stream erosion. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Geometry = preload("res://scripts/atlas/surface_geometry.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")

static func drainage(mesh: Dictionary,land: PackedByteArray,height: PackedFloat32Array,eps: float,lengths: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	var n: int = mesh.n
	if lengths.is_empty(): lengths = Geometry.new(mesh).lengths
	var order := PackedInt32Array(); order.resize(n); var receiver := order.duplicate(); receiver.fill(-1)
	var filled := PackedFloat32Array(); filled.resize(n); var state := PackedByteArray(); state.resize(n)
	var heap := Maths.Heap.new()
	for i in range(n):
		if not land[i]: state[i] = 2; filled[i] = minf(height[i],0)
	for i in range(n):
		if land[i]: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if land[j] and state[j]==0: state[j] = 1; filled[j] = maxf(height[j],eps); heap.push(j,filled[j])
	var count := 0
	while not heap.empty():
		var i := heap.pop(); state[i] = 2; order[count] = i; count += 1
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if state[j]!=0: continue
			state[j] = 1; filled[j] = maxf(height[j],filled[i]+eps); heap.push(j,filled[j])
	for a in range(count):
		var i := order[a]; var best := -1; var best_slope := -INF
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]; var fj := filled[j] if land[j] else minf(filled[j],0)
			if fj>=filled[i] and land[j]: continue
			var slope := (filled[i]-fj)/lengths[k]
			if slope>best_slope: best_slope = slope; best = j
		receiver[i] = best
	return {"order":order,"orderLen":count,"receiver":receiver,"filled":filled}

static func accumulate(d: Dictionary,land: PackedByteArray,weight: PackedFloat32Array) -> PackedFloat32Array:
	var out := weight.duplicate()
	for a in range(d.orderLen-1,-1,-1):
		var i: int = d.order[a]; var r: int = d.receiver[i]
		if r>=0 and land[r]: out[r] += out[i]
	return out

static func erode(mesh: Dictionary,land: PackedByteArray,height: PackedFloat32Array,uplift: PackedFloat32Array,rain: PackedFloat32Array,params: Dictionary,step_callback: Callable = Callable()) -> void:
	var lengths := Geometry.new(mesh).lengths
	for s in range(params.steps):
		var d := drainage(mesh,land,height,1e-5,lengths); var area := accumulate(d,land,rain)
		for a in range(d.orderLen):
			var i: int = d.order[a]; var r: int = d.receiver[i]
			if r<0: continue
			var hr := height[r] if land[r] else 0.0
			var dist: float = Sphere.distance(mesh,r,i)/mesh.spacing
			var f: float = params.K*params.dt*pow(area[i],params.m)/dist
			height[i] = (height[i]+params.dt*uplift[i]+f*hr)/(1+f)
		if step_callback.is_valid(): step_callback.call(s)
