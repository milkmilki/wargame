extends RefCounted
## civ-atlas 103afd3 gen/climate.ts, native scalar/F32 computation. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Surface = preload("res://scripts/atlas/surface_geometry.gd")
const TEMP = [0,27,15,26,30,20,45,11,60,1,75,-11,90,-24]
const RAIN = [0,1.25,8,1.1,16,.7,24,.38,32,.5,42,.85,55,.9,65,.6,78,.35,90,.2]

static func piecewise(values: Array,x: float) -> float:
	if x<=values[0]: return values[1]
	for i in range(2,values.size(),2):
		if x<=values[i]: return values[i-1]+(values[i+1]-values[i-1])*(x-values[i-2])/(values[i]-values[i-2])
	return values[-1]

static func base(mesh: Dictionary,geo,seed_value: int) -> Dictionary:
	var n: int = mesh.n
	var wx := PackedFloat64Array(); wx.resize(n); var wy := wx.duplicate(); var sea_temp := wx.duplicate(); var zonal := wx.duplicate()
	var wind_x := PackedFloat32Array(); wind_x.resize(n); var wind_y := wind_x.duplicate(); var strength := wind_x.duplicate()
	var up := PackedFloat32Array(); up.resize(mesh.adj.size()); var down := PackedByteArray(); down.resize(up.size())
	var up_count := PackedInt32Array(); up_count.resize(n)
	for i in range(n):
		var lat: float = geo.latitude(i); var a := absf(lat)
		var s30 := Maths.smoothstep(25,35,a); var s60 := Maths.smoothstep(55,65,a)
		var angle := atan2(.4,-1.0)-PI*s30+PI*s60
		wx[i] = cos(angle); wy[i] = sin(angle)*(1 if lat>=0 else -1)
		wind_x[i] = wx[i]; wind_y[i] = wy[i]
		var b30 := 1-2*s30; var b60 := 1-2*s60; strength[i] = b30*b30*b60*b60
		sea_temp[i] = piecewise(TEMP,a); zonal[i] = piecewise(RAIN,a)
	for i in range(n):
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var dot: float = geo.edge_dot(i,mesh.adj[k],-wind_x[i],-wind_y[i])
			if dot>.1: up[k] = dot
	for i in range(n):
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if j<=i or up[k]==0: continue
			for m in range(mesh.adj_start[j],mesh.adj_start[j+1]):
				if mesh.adj[m]!=i: continue
				if up[m]>0: up[k] = 0; up[m] = 0
				break
	for i in range(n):
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			if up[k]>0: up_count[i] += 1
	for j in range(n):
		for k in range(mesh.adj_start[j],mesh.adj_start[j+1]):
			var i: int = mesh.adj[k]
			for m in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				if mesh.adj[m]!=j: continue
				if up[m]>0: down[k] = 1
				break
	var tn = geo.fbm(Maths.sub_seed(seed_value,"temp"),4); var pn = geo.fbm(Maths.sub_seed(seed_value,"rain"),4)
	var t_noise := wx.duplicate(); var p_noise := wx.duplicate()
	for i in range(n): t_noise[i] = tn.at(i,4.0/mesh.width); p_noise[i] = pn.at(i,4.0/mesh.width)
	return {"wx":wx,"wy":wy,"windX":wind_x,"windY":wind_y,"strength":strength,"seaTemp":sea_temp,"zonal":zonal,"upW":up,"upCount":up_count,"downstream":down,"tNoise":t_noise,"pNoise":p_noise}

static func build(mesh: Dictionary,elev: PackedFloat32Array,water: PackedByteArray,params: Dictionary,currents: Dictionary = {},cached_base: Dictionary = {}) -> Dictionary:
	var n: int = mesh.n; var geo := Surface.new(mesh)
	var b := base(mesh,geo,int(params.seed)) if cached_base.is_empty() else cached_base
	var temperature := PackedFloat32Array(); temperature.resize(n); var key := temperature.duplicate()
	var cuts := geo.wind_cuts(water); var sst := PackedFloat32Array(currents.get("sst",[]))
	for i in range(n):
		key[i] = geo.downwind(i,b.wx[i],b.wy[i],cuts)
		var e := 0.0 if water[i]==1 else maxf(0,elev[i])
		temperature[i] = b.seaTemp[i]+params.temperature-.0065*e+1.5*b.tNoise[i]
		if not sst.is_empty() and water[i]==1: temperature[i] += sst[i]
	var coast_sst := PackedFloat32Array(); coast_sst.resize(n); var coast_w := coast_sst.duplicate()
	if not sst.is_empty():
		var sea_f := PackedFloat32Array(); sea_f.resize(n)
		for i in range(n): sea_f[i] = 1 if water[i]==1 else 0
		var num := Surface.blur(mesh,sst,5); var den := Surface.blur(mesh,sea_f,5)
		for i in range(n):
			if water[i]==1 or den[i]==0: continue
			coast_sst[i] = num[i]/den[i]; coast_w[i] = .85*clampf(den[i]*3,0,1)
	var waiting := PackedInt32Array(b.upCount); var by_key: Array[int] = []
	for i in range(n): by_key.append(i)
	by_key.sort_custom(func(a,c): return a<c if key[a]==key[c] else key[a]<key[c])
	var order := PackedInt32Array(); order.resize(n); var queued := PackedByteArray(); queued.resize(n)
	var head := 0; var tail := 0; var next_key := 0; var cycles := 0
	for i in by_key:
		if waiting[i]==0: order[tail] = i; tail += 1; queued[i] = 1
	while tail<n:
		if head==tail:
			cycles += 1
			while queued[by_key[next_key]]: next_key += 1
			var i := by_key[next_key]; order[tail] = i; tail += 1; queued[i] = 1
		var j := order[head]; head += 1
		for k in range(mesh.adj_start[j],mesh.adj_start[j+1]):
			var i: int = mesh.adj[k]
			if queued[i]: continue
			if b.downstream[k]:
				waiting[i] -= 1
				if waiting[i]==0: order[tail] = i; tail += 1; queued[i] = 1
	var land_elev := PackedFloat32Array(); land_elev.resize(n)
	for i in range(n): land_elev[i] = 0.0 if water[i]==1 else maxf(0,elev[i])
	var smooth_elev := Surface.blur(mesh,land_elev,3)
	var hum := PackedFloat32Array(); hum.resize(n); var rain := hum.duplicate(); var heat := hum.duplicate(); var land_heat := hum.duplicate()
	var heat_keep := Maths.round24(pow(Maths.round24(exp(-1.0/(1500.0/(40000.0/2048.0)))),float(mesh.spacing)))
	for i in range(n): hum[i] = clampf((temperature[i]+12)/38,.12,1) if water[i]!=0 else .3
	for _sweep in range(2 if cycles>0 else 1):
		for i in order:
			var sw := 0.0; var sh := 0.0; var se := 0.0; var sq := 0.0
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var dot := float(b.upW[k])
				if dot==0: continue
				var j: int = mesh.adj[k]; sw += dot; sh += dot*hum[j]; se += dot*smooth_elev[j]; sq += dot*heat[j]
			var is_sea := water[i]!=0; var sat := clampf((temperature[i]+12)/38,.12,1); var local := sat if is_sea else .3
			var hm: float = local+(sh/sw-local)*b.strength[i] if sw>0 else local
			var ue := se/sw if sw>0 else 0.0
			if is_sea: hm += (sat-hm)*.22; rain[i] = hm*.01*1.2
			else:
				var rise := maxf(0,smooth_elev[i]-ue); var frac := clampf(.01+.00018*rise,0,.6)
				if not sst.is_empty():
					var q: float = sq/sw*sqrt(b.strength[i]) if sw>0 else 0.0
					q += (coast_sst[i]-q)*coast_w[i]
					frac *= maxf(.2,1+.2*q) if q<0 else 1+.04*minf(q,5)
					heat[i] = q*heat_keep*Maths.round24(exp(-rise/1500.0)); land_heat[i] = q
				var r := hm*frac; hm = hm-r+r*.7*clampf(sat,.3,1); rain[i] = r
			if not sst.is_empty() and is_sea:
				var up: float = sq/sw*b.strength[i] if sw>0 else 0.0; heat[i] = up+(sst[i]-up)*.35
			hum[i] = hm
	if not sst.is_empty():
		for i in range(n): temperature[i] += land_heat[i]
	var precipitation := PackedFloat32Array(); precipitation.resize(n); var rain_s := Surface.blur(mesh,rain,2)
	for i in range(n): precipitation[i] = maxf(0,rain_s[i]/.01*b.zonal[i]*(1+.18*b.pNoise[i])*1500.0*params.rainfall)
	return {"temperature":temperature,"precipitation":precipitation,"windX":PackedFloat32Array(b.windX),"windY":PackedFloat32Array(b.windY),"base":b}
