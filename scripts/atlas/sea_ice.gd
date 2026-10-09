extends RefCounted
## civ-atlas gen/seaice.ts computeSeaIce. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Geometry = preload("res://scripts/atlas/surface_geometry.gd")

static func build(mesh: Dictionary,elev: PackedFloat32Array,water: PackedByteArray,temp: PackedFloat32Array,wind_x: PackedFloat32Array,wind_y: PackedFloat32Array,seed_value: int) -> PackedFloat32Array:
	var n: int = mesh.n; var geo := Geometry.new(mesh); var cuts := geo.wind_cuts(water)
	var key := PackedFloat32Array(); key.resize(n); var order: Array[int] = []
	for i in range(n): key[i] = geo.downwind(i,wind_x[i],wind_y[i],cuts); order.append(i)
	order.sort_custom(func(a,b): return a<b if key[a]==key[b] else key[a]<key[b])
	var chill := PackedFloat32Array(); chill.resize(n)
	for _sweep in range(2):
		for i in order:
			var sw := 0.0; var sc := 0.0
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var j: int = mesh.adj[k]; var dot := geo.edge_dot(i,j,-wind_x[i],-wind_y[i])
				if dot<=.1: continue
				sw += dot; sc += dot*chill[j]
			var up := sc/sw if sw>0 else 0.0
			chill[i] = up+(-10*Maths.smoothstep(14,-6,temp[i])-up)*.2 if water[i]!=1 else up*.95
	var land := PackedFloat32Array(); land.resize(n)
	for i in range(n): land[i] = 0 if water[i]==1 else 1
	var near := Geometry.blur(mesh,land,5); var far := Geometry.blur(mesh,near,30)
	var current = geo.fbm(Maths.sub_seed(seed_value,"seaice-current"),2)
	var ice := PackedFloat32Array(); ice.resize(n)
	for i in range(n):
		if water[i]!=1: continue
		var open := 1-clampf(far[i]*2.2,0,1); var deep := Maths.smoothstep(-200,-2500,elev[i])
		var effective: float = temp[i]+chill[i]-3*clampf(near[i]*1.6,0,1)+1.5*open+.8*deep+(3.5+4.5*open)*current.stretched(i,1.0/300,.55)
		ice[i] = Maths.smoothstep(-3,-11,effective)
	return ice
