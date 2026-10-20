extends RefCounted
## Climatological root-zone bucket; potential natural vegetation, not land cover.
## Water enters as precipitation, leaves as ET/runoff, or remains in storage.
## https://pubs.usgs.gov/publication/pp1894E/full
const Climate=preload("res://scripts/atlas/climate_settlement_v3.gd")
const Temperature=preload("res://scripts/atlas/climate.gd")
const VERSION="forest_root_zone_v1"
const SEASONS=[-.85,.4,.85,-.4]

static func quarter(storage:float,precipitation:float,potential_evaporation:float,forest:float,temperature:float) -> Dictionary:
	# Quarterly rates represent sustained climatological fluxes, not one storm
	# followed by three dry months. Monthly substeps prevent false overflow and
	# exhausted wet-forest storage. Drainage retains its quarterly time constant.
	var start:=maxf(0.,storage);var evaporation:=0.;var runoff:=0.;var result:Dictionary
	for month in range(3):
		result=water_step(start if month==0 else result.storage,precipitation/3.,potential_evaporation/3.,forest,temperature)
		evaporation+=result.evaporation;runoff+=result.runoff
	return {"input_storage":start,"precipitation":maxf(0.,precipitation),"capacity":result.capacity,"storage":result.storage,"evaporation":evaporation,"runoff":runoff}

static func water_step(storage:float,precipitation:float,potential_evaporation:float,forest:float,temperature:float) -> Dictionary:
	forest=clampf(forest,0.,1.);storage=maxf(0.,storage);precipitation=maxf(0.,precipitation)
	var capacity:=75.+225.*forest # mm of plant-accessible water; game proxy.
	var demand:=maxf(0.,potential_evaporation)*smoothstep(-2.,5.,temperature)
	var interception:=minf(precipitation*.12*forest,demand*.2*forest)
	var throughfall:=precipitation-interception
	var infiltration:=throughfall*(.5+.4*forest)
	var runoff:=throughfall-infiltration+maxf(0.,storage+infiltration-capacity)
	var available:=minf(capacity,storage+infiltration)
	var transpiration:=minf(available,maxf(0.,demand-interception)*(.55+.45*forest))
	available-=transpiration
	var drainage:=available*(1.-pow(1.-(.05-.02*forest),1./3.))
	return {"input_storage":storage,"precipitation":precipitation,"capacity":capacity,"storage":available-drainage,
		"evaporation":interception+transpiration,"runoff":runoff+drainage}

static func cycle(rain:PackedFloat32Array,pet:PackedFloat32Array,temperatures:PackedFloat32Array,forest:float) -> Dictionary:
	assert(rain.size()==4 and pet.size()==4 and temperatures.size()==4)
	var storage:=0.;var start:=0.;var evaporation:=PackedFloat32Array();var runoff:=PackedFloat32Array();var moisture:=PackedFloat32Array()
	var annual_evaporation:=0.;var annual_runoff:=0.;var years:=0
	# Repeat the prescribed climatological year, never seed a free full bucket.
	for year in range(64):
		start=storage;evaporation.clear();runoff.clear();moisture.clear();annual_evaporation=0.;annual_runoff=0.;years=year+1
		for q in range(4):
			var result:=quarter(storage,rain[q],pet[q],forest,temperatures[q]);storage=result.storage
			evaporation.append(result.evaporation);runoff.append(result.runoff);moisture.append(storage)
			annual_evaporation+=result.evaporation;annual_runoff+=result.runoff
		if absf(storage-start)<.001:break
	return {"start_storage":start,"end_storage":storage,"evaporation":evaporation,"runoff":runoff,"storage":moisture,
		"annual_evaporation":annual_evaporation,"annual_runoff":annual_runoff,"spinup_years":years}

static func zeros(n:int) -> PackedFloat32Array:
	var values:=PackedFloat32Array();values.resize(n);return values

static func fields(elevation:PackedFloat32Array,land:PackedByteArray,size:Vector2i,quarters:Array,temperature_offset:float=0.) -> Dictionary:
	var n:=land.size();var forest:=zeros(n);var annual_et:=zeros(n);var annual_runoff:=zeros(n);var closure:=zeros(n)
	var evaporation:Array=[];var runoff:Array=[];var storage:Array=[];var pet_fields:Array=[]
	for q in range(4):evaporation.append(zeros(n));runoff.append(zeros(n));storage.append(zeros(n));pet_fields.append(zeros(n))
	var max_years:=0;var max_year_change:=0.
	for i in range(n):
		if not land[i]:continue
		var latitude:=90.-(floori(float(i)/size.x)+.5)/size.y*180.
		var base:=Temperature.piecewise(Temperature.TEMP,absf(latitude))-.0065*elevation[i]+temperature_offset
		var rain:=PackedFloat32Array();var pet:=PackedFloat32Array();var temperatures:=PackedFloat32Array()
		var total_rain:=0.;var total_pet:=0.;var warmest:=-100.
		for q in range(4):
			var t:float=base+12.*SEASONS[q]*sin(deg_to_rad(latitude))
			var p:=maxf(0.,float(quarters[q][i]))*.25
			var demand:=Climate.potential_evaporation(t,latitude,q,10.)
			var effective_demand:=demand*smoothstep(-2.,5.,t)
			rain.append(p);pet.append(demand);temperatures.append(t);pet_fields[q][i]=effective_demand
			total_rain+=p;total_pet+=effective_demand;warmest=maxf(warmest,t)
		var cover:=smoothstep(.30,.85,total_rain/maxf(1.,total_pet))*smoothstep(5.,14.,warmest)
		forest[i]=cover
		var water:=cycle(rain,pet,temperatures,cover)
		annual_et[i]=water.annual_evaporation;annual_runoff[i]=water.annual_runoff
		closure[i]=total_rain+water.start_storage-water.end_storage-water.annual_evaporation-water.annual_runoff
		max_years=maxi(max_years,water.spinup_years);max_year_change=maxf(max_year_change,absf(water.end_storage-water.start_storage))
		for q in range(4):evaporation[q][i]=water.evaporation[q];runoff[q][i]=water.runoff[q];storage[q][i]=water.storage[q]
	return {"forest_cover":forest,"surface_evaporation":evaporation,"surface_runoff":runoff,"soil_moisture":storage,
		"surface_potential_evaporation":pet_fields,"annual_evaporation":annual_et,"annual_runoff":annual_runoff,"surface_water_error":closure,
		"surface_water_metadata":{"version":VERSION,"units":"mm; quarters are totals, storage is end-of-quarter","capacity_mm":[75.,300.],
		"observed_land_cover":false,"snowpack":false,"substeps_per_quarter":3,"within_quarter_forcing":"uniform climatological rates; not a storm sequence","frozen_evaporation_ramp_C":[-2.,5.],"spinup_years_max":max_years,"periodic_storage_error_mm":max_year_change,
		"rules":"finite precipitation-fed root zone, canopy interception, water-limited ET, infiltration, overflow and slow drainage; forest ET can reduce annual runoff"}}
