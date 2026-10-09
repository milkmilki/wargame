extends RefCounted
## civ-atlas 103afd3 gen/world.ts default planet pipeline. AGPL-3.0-only.
## Hydrology is retained as environmental data; rivers are never rendered or routed.
const Maths = preload("res://scripts/atlas/math.gd")
const MeshBuilder = preload("res://scripts/atlas/sphere_mesh.gd")
const Geometry = preload("res://scripts/atlas/surface_geometry.gd")
const Tectonics = preload("res://scripts/atlas/tectonics.gd")
const Erosion = preload("res://scripts/atlas/erosion.gd")
const Climate = preload("res://scripts/atlas/climate.gd")
const Currents = preload("res://scripts/atlas/currents.gd")
const Ice = preload("res://scripts/atlas/sea_ice.gd")
const Earth = preload("res://scripts/atlas/earth_surface.gd")
const Monsoon = preload("res://scripts/atlas/monsoon_rainfall.gd")
const Circulation = preload("res://scripts/atlas/circulation_rainfall.gd")
const SettlementClimate = preload("res://scripts/atlas/climate_settlement.gd")
const TwoSeasonBaseline = preload("res://scripts/atlas/climate_settlement_v5.gd")
const FrozenSettlementClimate = preload("res://scripts/atlas/climate_settlement_v4.gd")
const PreviousSettlementClimate = preload("res://scripts/atlas/climate_settlement_v3.gd")
const DEFAULTS := {"seed":1,"cells":36000,"landFraction":.33,"plates":30,"mountains":1,"temperature":0,"rainfall":1}

static func meters(height: PackedFloat32Array,land: PackedByteArray,ocean: PackedFloat32Array,plateau: PackedFloat32Array,peak: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for i in range(height.size()):
		if land[i]: values.append(height[i])
	values.sort()
	var reference := 1.0 if values.is_empty() else float(values[clampi(int(floor(values.size()*.997)),0,values.size()-1)])
	if reference==0: reference = 1
	var scale_value := peak/reference; var knee := peak*.85
	var out := PackedFloat32Array(); out.resize(height.size())
	for i in range(height.size()):
		if not land[i]: out[i] = ocean[i]; continue
		var e := height[i]*scale_value+plateau[i]; out[i] = knee+(e-knee)*.45 if e>knee else e
	return out

static func rain_weight(mesh: Dictionary,elevation: PackedFloat32Array,water: PackedByteArray,params: Dictionary,cached_base: Dictionary) -> PackedFloat32Array:
	var climate := Climate.build(mesh,elevation,water,params,{},cached_base)
	var out := PackedFloat32Array(); out.resize(mesh.n)
	for i in range(mesh.n): out[i] = clampf(climate.precipitation[i]/1200.0,.1,2.5) if water[i]==0 else 0.0
	return out

static func biome(t: float,rain: float,water: int,ice: float) -> int:
	if water==1: return 2 if ice>=.5 else 0
	if water==2: return 3 if t < -6 else 1
	if t < -9: return 3
	if t < -2: return 6 if rain<150 else 4
	if t<5: return 6 if rain<280 else 5
	if t<18: return 7 if rain<250 else 8 if rain<600 else 9 if rain<1700 else 10
	return 11 if rain<320 else 12 if rain<950 else 13 if rain<1800 else 14

static func moisture_biome(t: float,rain: float,pet: float,water: int,ice: float) -> int:
	var original := biome(t,rain,water,ice)
	if water!=0 or t< -2.: return original
	var aridity := rain/maxf(1.,pet)
	if aridity<.20: return 6 if t<12. else 11
	if aridity<.5 and original in [8,9,10,13,14]: return 7 if t<18. else 12
	return original

static func generate(options: Dictionary = {},progress: Callable = Callable()) -> Dictionary:
	var params := DEFAULTS.duplicate(); params.merge(options,true)
	if params.get("terrain_model","planet")=="earth": return generate_earth(params,progress)
	if progress.is_valid(): progress.call("球面网格")
	var mesh := MeshBuilder.build(int(params.seed),int(params.cells)); var n: int = mesh.n; var geo := Geometry.new(mesh)
	if progress.is_valid(): progress.call("板块与海陆")
	var tect := Tectonics.build(mesh,params); var land: PackedByteArray = tect.land
	var height := Tectonics.floats(n); var noise = geo.fbm(Maths.sub_seed(int(params.seed),"h0"),4)
	var water0 := PackedByteArray(); water0.resize(n)
	for i in range(n):
		if land[i]: height[i] = .05+.05*(noise.at_scale(i,300)+1)
		else: water0[i] = 1
	var peak := 3600+1700*clampf(params.mountains,0,2)
	var proxy := Tectonics.floats(n)
	for i in range(n): proxy[i] = tect.uplift[i]*2500+tect.plateau[i] if land[i] else tect.oceanDepth[i]
	var climate_base := Climate.base(mesh,geo,int(params.seed))
	var rain := rain_weight(mesh,proxy,water0,params,climate_base)
	var erosion_params := {"steps":18,"dt":.9,"K":1.0,"m":.5}
	if progress.is_valid(): progress.call("造山与侵蚀")
	Erosion.erode(mesh,land,height,tect.uplift,rain,erosion_params)
	rain = rain_weight(mesh,meters(height,land,tect.oceanDepth,tect.plateau,peak),water0,params,climate_base)
	Erosion.erode(mesh,land,height,tect.uplift,rain,erosion_params)
	var flow := Erosion.drainage(mesh,land,height,1e-5,geo.lengths)
	var samples := PackedFloat32Array()
	for i in range(n):
		if land[i]: samples.append(height[i])
	samples.sort()
	var ref_height := 1.0 if samples.is_empty() else float(samples[clampi(int(floor(samples.size()*.997)),0,samples.size()-1)])
	if ref_height==0: ref_height = 1.0
	var scale_value := peak/ref_height; var base: PackedFloat32Array = tect.plateau.duplicate()
	for a in range(flow.orderLen-1,-1,-1):
		var i: int = flow.order[a]; var r: int = flow.receiver[i]
		if r<0 or not land[r]: continue
		var limit: float = base[i]+(flow.filled[i]-flow.filled[r])*scale_value
		if base[r]>limit: base[r] = limit
	var elevation := meters(height,land,tect.oceanDepth,base,peak)
	if progress.is_valid(): progress.call("湖泊与排水")
	for i in range(n):
		if not land[i]: continue
		var continental := 1.0 if tect.plateContinental[tect.plate[i]] else .5
		var d: float = tect.distDiv[i]/20.0
		var rift := 220*continental*Maths.smoothstep(.2,.65,tect.strengthDiv[i])*exp(-d*d)
		elevation[i] -= minf(rift,.7*maxf(0,elevation[i]))
	var dent_seed := Maths.sub_seed(int(params.seed),"lakes-at"); var high_land := 0; var dents: Array[int] = []
	for c in range(n):
		if not land[c] or elevation[c]<=60: continue
		high_land += 1
		if Maths.keyed(dent_seed,c,0)<1.0/600.0: dents.append(c)
	for c in dents:
		var r: float = mesh.spacing*(1.6+Maths.keyed(dent_seed,c,1)*2.8); var depth := 40+Maths.keyed(dent_seed,c,2)*160
		for i in range(n):
			if not land[i]: continue
			var distance := MeshBuilder.distance(mesh,i,c)
			if distance<=r*3: elevation[i] -= depth*exp(-(distance*distance)/(r*r))
	var pool := Erosion.drainage(mesh,land,elevation,0,geo.lengths)
	var water := PackedByteArray(); water.resize(n); var water_level := Tectonics.floats(n)
	for i in range(n):
		if not land[i]: water[i] = 1
		elif pool.filled[i]-elevation[i]>3: water[i] = 2; water_level[i] = pool.filled[i]
	var max_lake := maxi(40,int(floor(high_land*.004+.5))); var seen := PackedByteArray(); seen.resize(n)
	for i in range(n):
		if water[i]!=2 or seen[i]: continue
		var component: Array[int] = [i]; seen[i] = 1; var head := 0
		while head<component.size():
			var c := component[head]; head += 1
			for k in range(mesh.adj_start[c],mesh.adj_start[c+1]):
				var j: int = mesh.adj[k]
				if water[j]==2 and not seen[j]: seen[j] = 1; component.append(j)
		if component.size()>max_lake:
			for c in component: water[c] = 0; elevation[c] = pool.filled[c]-1
	if progress.is_valid(): progress.call("气候、洋流与海冰")
	var currents := Currents.build(mesh,water)
	var climate := Climate.build(mesh,elevation,water,params,currents,climate_base)
	var ice := Ice.build(mesh,elevation,water,climate.temperature,climate.windX,climate.windY,int(params.seed))
	var route := Erosion.drainage(mesh,land,elevation,.001,geo.lengths); var runoff := Tectonics.floats(n)
	for i in range(n):
		if land[i]: runoff[i] = maxf(.03,(climate.precipitation[i]-.45*(250+22*maxf(0,climate.temperature[i])))/1000.0)
	var flux := Erosion.accumulate(route,land,runoff); var biomes := PackedByteArray(); biomes.resize(n); var max_elevation := 0.0
	for i in range(n):
		biomes[i] = biome(climate.temperature[i],climate.precipitation[i],water[i],ice[i])
		if land[i]: max_elevation = maxf(max_elevation,elevation[i])
	return {"params":params,"width":mesh.width,"height":mesh.height,"mesh":mesh,"tect":tect,"elevation":elevation,"water":water,
		"waterLevel":water_level,"temperature":climate.temperature,"precipitation":climate.precipitation,"seaIce":ice,"currents":currents,
		"biome":biomes,"flux":flux,"riverThreshold":14.0*n/36000.0,"rivers":[],"volcanoes":[],"maxElevation":max_elevation}

static func generate_earth(params: Dictionary,progress: Callable) -> Dictionary:
	if progress.is_valid(): progress.call("真实地球高程与海岸")
	var surface := Earth.load_surface()
	if surface.is_empty(): return {"error":"真实地球数据缺失或 SHA256 校验失败"}
	params = params.duplicate()
	# These random-planet controls do not participate in the Earth preset.
	for key in ["plates","mountains","landFraction"]: params.erase(key)
	params.terrain_source = surface.metadata
	if progress.is_valid(): progress.call("球面网格与真实高程取样")
	var mesh := MeshBuilder.build(int(params.seed),int(params.cells)); var n: int = mesh.n; var geo := Geometry.new(mesh)
	var elevation := Tectonics.floats(n); var water := PackedByteArray(); water.resize(n)
	var land := water.duplicate(); var level := Tectonics.floats(n); var maximum := 0.
	for i in range(n):
		var lon: float = mesh.x[i]/mesh.width*360.-180.; var lat: float = 90.-mesh.y[i]/mesh.height*180.
		elevation[i] = Earth.elevation_at(surface,lon,lat); water[i] = Earth.water_at(surface,lon,lat)
		land[i] = 1 if water[i]==0 else 0
		if water[i]==1: elevation[i] = minf(-1,elevation[i])
		elif water[i]==2: level[i] = elevation[i]
		else: maximum = maxf(maximum,elevation[i])
	if progress.is_valid(): progress.call("地球气候、洋流与海冰（模型计算）")
	var currents := Currents.build(mesh,water)
	var climate := Climate.build(mesh,elevation,water,params,currents,Climate.base(mesh,geo,int(params.seed)))
	var rainfall_model: String = params.get("rainfall_model",Circulation.VERSION); params.rainfall_model = rainfall_model
	var default_settlement := SettlementClimate.VERSION if rainfall_model==Circulation.VERSION else FrozenSettlementClimate.VERSION if rainfall_model in ["seasonal_circulation_v4","seasonal_circulation_v3"] else "climate_capacity_v2" if rainfall_model=="seasonal_circulation_v2" else "atlas_original"
	params.settlement_model = params.get("settlement_model",default_settlement)
	if params.settlement_model not in [SettlementClimate.VERSION,TwoSeasonBaseline.VERSION,FrozenSettlementClimate.VERSION,PreviousSettlementClimate.VERSION,"climate_capacity_v2","atlas_original"]: return {"error":"不支持的城市布局模型："+str(params.settlement_model)}
	var rain_detail := {}
	if rainfall_model==Monsoon.VERSION:
		if progress.is_valid(): progress.call("复用季风模型：海洋水汽输送与高山雨影")
		rain_detail = Monsoon.build(surface,mesh,float(params.rainfall)); params.rainfall_transport = rain_detail.metadata
		for i in range(n):
			if water[i]==0: climate.precipitation[i] = rain_detail.precipitation[i]
	elif rainfall_model in [Circulation.VERSION,"seasonal_circulation_v4","seasonal_circulation_v3","seasonal_circulation_v2"]:
		if progress.is_valid(): progress.call("季节大气环流：辐合雨带、陆海季风与西风水汽")
		rain_detail = Circulation.build(surface,mesh,float(params.rainfall),currents,water,rainfall_model); params.rainfall_transport = rain_detail.metadata
		for i in range(n):
			if water[i]==0: climate.precipitation[i] = rain_detail.precipitation[i]
		climate.windX = rain_detail.windX; climate.windY = rain_detail.windY
	elif rainfall_model!="atlas_original": return {"error":"不支持的降雨模型："+rainfall_model}
	var ice := Ice.build(mesh,elevation,water,climate.temperature,climate.windX,climate.windY,int(params.seed))
	if progress.is_valid(): progress.call("真实地形排水与环境供水")
	# Drainage fills depressions for flow only. It does not re-erode the DEM,
	# flood below-sea-level land, or invent visible lakes/river transport.
	var route := Erosion.drainage(mesh,land,elevation,.001,geo.lengths); var runoff := Tectonics.floats(n)
	var biomes := PackedByteArray(); biomes.resize(n)
	for i in range(n):
		if land[i]: runoff[i] = maxf(.03,(climate.precipitation[i]-.45*(250+22*maxf(0,climate.temperature[i])))/1000.)
		biomes[i] = biome(climate.temperature[i],climate.precipitation[i],water[i],ice[i])
	var result := {"params":params,"width":mesh.width,"height":mesh.height,"mesh":mesh,"elevation":elevation,"water":water,
		"waterLevel":level,"temperature":climate.temperature,"precipitation":climate.precipitation,"seaIce":ice,"currents":currents,
		"biome":biomes,"flux":Erosion.accumulate(route,land,runoff),"riverThreshold":14.*n/36000.,"rivers":[],"volcanoes":[],"maxElevation":maximum}
	if not rain_detail.is_empty():
		result.annual_precipitation = rain_detail.annual_precipitation; result.seasonal_precipitation = rain_detail.seasonal_precipitation
		if rain_detail.has("quarter_precipitation"):
			result.quarter_precipitation = rain_detail.quarter_precipitation; result.seasonal_winds = rain_detail.seasonal_winds
			result.windX = rain_detail.windX; result.windY = rain_detail.windY
	if rainfall_model in [Circulation.VERSION,"seasonal_circulation_v4","seasonal_circulation_v3"]:
		# The v3 diagnostics keep biome assignment independent of city scoring.
		var biome_fields := PreviousSettlementClimate.fields(mesh,result)
		var climate_fields := biome_fields
		if params.settlement_model==SettlementClimate.VERSION:
			params.climate_water_balance = SettlementClimate.METADATA.duplicate()
			climate_fields = SettlementClimate.fields(mesh,result)
			result.merge(climate_fields,true)
		elif params.settlement_model==TwoSeasonBaseline.VERSION:
			params.climate_water_balance = TwoSeasonBaseline.METADATA.duplicate()
			climate_fields = TwoSeasonBaseline.fields(mesh,result)
			result.merge(climate_fields,true)
		elif params.settlement_model==FrozenSettlementClimate.VERSION:
			params.climate_water_balance = FrozenSettlementClimate.METADATA.duplicate()
			climate_fields = FrozenSettlementClimate.fields(mesh,result)
			result.merge(climate_fields,true)
		elif params.settlement_model==PreviousSettlementClimate.VERSION:
			params.climate_water_balance = PreviousSettlementClimate.METADATA.duplicate()
			result.merge(climate_fields,true)
		for i in range(n): biomes[i] = moisture_biome(climate.temperature[i],climate.precipitation[i],biome_fields.potential_evaporation[i],water[i],ice[i])
		result.biome = biomes
	return result
