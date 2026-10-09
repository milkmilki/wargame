extends RefCounted
## Port of civ-atlas 103afd3 gen/civ/habitat.ts. AGPL-3.0-only.
## Environmental river flux contributes freshwater, never transport cost.
const Maths = preload("res://scripts/atlas/math.gd")
const SettlementClimate = preload("res://scripts/atlas/climate_settlement.gd")
const TwoSeasonBaseline = preload("res://scripts/atlas/climate_settlement_v5.gd")
const FrozenSettlementClimate = preload("res://scripts/atlas/climate_settlement_v4.gd")
const PreviousSettlementClimate = preload("res://scripts/atlas/climate_settlement_v3.gd")
const LegacySettlementClimate = preload("res://scripts/atlas/climate_settlement_v2.gd")
const BASE = [0,0,0,0,4,12,10,7,30,100,90,4,22,50,80,12]

static func build(mesh: Dictionary,env: Dictionary) -> Dictionary:
	var n: int = mesh.n
	var start: PackedInt32Array = mesh.adj_start; var adj: PackedInt32Array = mesh.adj
	var lengths: PackedFloat32Array = mesh.lengths; var areas: PackedFloat32Array = mesh.areas
	var water := PackedByteArray(env.water); var biome := PackedByteArray(env.biome)
	var elevation := PackedFloat32Array(env.elevation); var temp := PackedFloat32Array(env.temperature)
	var flux := PackedFloat32Array(env.flux); var threshold: float = env.riverThreshold
	var suit := PackedFloat32Array(); suit.resize(n)
	var capacity := PackedFloat32Array(); capacity.resize(n)
	var harbor := PackedByteArray(); harbor.resize(n)
	# Signed int8 in upstream; int32 here preserves -127..127 without wrapping.
	var coast := PackedInt32Array(); coast.resize(n)
	var queue := PackedInt32Array(); queue.resize(n); var head := 0; var tail := 0
	for i in range(n):
		var sea := water[i] == 1
		for k in range(start[i],start[i+1]):
			if (water[adj[k]] == 1) != sea:
				coast[i] = -1 if sea else 1; queue[tail] = i; tail += 1; break
	while head < tail:
		var i := queue[head]; head += 1; var d := coast[i]
		var next := mini(127,d+1) if d>0 else maxi(-127,d-1)
		for k in range(start[i],start[i+1]):
			var j := adj[k]
			if coast[j] != 0 or (water[j] == 1) != (d<0): continue
			coast[j] = next; queue[tail] = j; tail += 1
	for i in range(n):
		if coast[i] == 0: coast[i] = -127 if water[i] == 1 else 127
	var km_per_unit := 40000.0/float(mesh.width)
	var ref_area := float(mesh.width)*float(mesh.height)/36000.0
	var farmland := PackedFloat32Array()
	var climate_fields := {}
	var settlement_model: String = env.get("params",{}).get("settlement_model","")
	if settlement_model in [SettlementClimate.VERSION,TwoSeasonBaseline.VERSION,FrozenSettlementClimate.VERSION,PreviousSettlementClimate.VERSION]:
		if env.has("climate_suitability"):
			for field in ["agricultural_potential","climate_suitability","potential_evaporation","aridity_index","growing_months"]: climate_fields[field] = env[field]
		else:
			var model = SettlementClimate if settlement_model==SettlementClimate.VERSION else TwoSeasonBaseline if settlement_model==TwoSeasonBaseline.VERSION else FrozenSettlementClimate if settlement_model==FrozenSettlementClimate.VERSION else PreviousSettlementClimate
			climate_fields = model.fields(mesh,env)
		farmland = climate_fields.agricultural_potential
	elif settlement_model==LegacySettlementClimate.VERSION:
		farmland = LegacySettlementClimate.potentials(mesh,env)
	for i in range(n):
		if water[i] != 0: continue
		var base: float = BASE[biome[i]]
		if settlement_model==LegacySettlementClimate.VERSION: base = maxf(base,farmland[i])
		elif not climate_fields.is_empty(): base = 110.
		var sea_count := 0; var open_sea := false; var lake := 0.0; var bank := 0.0
		var slope_sum := 0.0; var slope_count := 0
		for k in range(start[i],start[i+1]):
			var j := adj[k]
			if water[j] == 1:
				sea_count += 1
				if biome[j] != 2 and temp[j] >= -8.0: open_sea = true
			elif water[j] == 2: lake = maxf(lake,1.0 if biome[j] == 3 else 30.0)
			else:
				if flux[j] >= 6.0*threshold and flux[j] > bank: bank = flux[j]
				slope_sum += absf(elevation[j]-elevation[i])/(lengths[k]*km_per_unit); slope_count += 1
		harbor[i] = sea_count
		if base <= 0: continue
		var river := flux[i]/threshold
		var value := base+maxf(fresh(river),0.75*fresh(bank/threshold))+lake
		if open_sea:
			value += 5.0
			if river >= 1.0: value += 15.0
			if sea_count == 1: value += 20.0
		# Climate limits all land-use/freshwater/harbor bonuses together. A biome
		# score cannot revive a frozen, scorching, waterlogged or desert cell.
		if not climate_fields.is_empty(): value *= climate_fields.climate_suitability[i]
		value -= maxf(0,elevation[i])/150.0
		value -= minf(30.0,1.6*(slope_sum/slope_count if slope_count else 0.0))
		var v := maxf(0,value)/5.0
		suit[i] = v; capacity[i] = v*areas[i]/ref_area
	var result := {"suitability":suit,"capacity":capacity,"coastDist":coast,"harbor":harbor}
	if not farmland.is_empty(): result.agricultural_potential = farmland
	result.merge(climate_fields,true)
	return result

static func fresh(value: float) -> float:
	return minf(40.0,12.0*Maths.flog2(1.0+value))
