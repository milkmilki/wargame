extends SceneTree
const Climate = preload("res://scripts/atlas/climate_settlement.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
const Circulation = preload("res://scripts/atlas/seasonal_circulation.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("CLIMATE_LIMIT_FAIL ",message)

func habitat_value(temperature: float,rain: float) -> float:
	# Deliberately keep a high forest baseline and abundant freshwater: neither
	# may bypass an unsuitable climate. No slope/altitude differences to hide it.
	var mesh := {"n":2,"width":2048,"height":1024,"x":PackedFloat32Array([1000,1001]),"y":PackedFloat32Array([512,512]),"adj_start":PackedInt32Array([0,1,2]),"adj":PackedInt32Array([1,0]),"lengths":PackedFloat32Array([1,1]),"areas":PackedFloat32Array([1,1])}
	var env := {"params":{"settlement_model":Climate.VERSION},"water":PackedByteArray([0,0]),"biome":PackedByteArray([9,9]),"elevation":PackedFloat32Array([0,0]),"temperature":PackedFloat32Array([temperature,temperature]),"flux":PackedFloat32Array([1000,1000]),"riverThreshold":1.,"precipitation":PackedFloat32Array([rain,rain]),"quarter_precipitation":[]}
	for q in range(4): env.quarter_precipitation.append(PackedFloat32Array([rain,rain]))
	return Habitat.build(mesh,env).suitability[0]

func _initialize() -> void:
	var optimum := Climate.farming_potential(18.,1000.,250.)
	check(Climate.potential_evaporation(25.,30.,2)>Climate.potential_evaporation(10.,30.,2),"hot season has no greater evaporative demand")
	check(Climate.potential_evaporation(-5.,89.,0)<1.,"polar night invents solar evaporation")
	check(Climate.farming_potential(35.,1000.,250.)<optimum*.5,"extreme heat almost as suitable as temperate climate")
	check(Climate.farming_potential(18.,5600.,1400.)==0.,"quarterly wet cutoff must eliminate excessive rainfall support")
	check(habitat_value(-5.,1200.)==0.,"forest/freshwater bypass frozen climate")
	check(habitat_value(35.,1000.)<habitat_value(18.,1000.)*.5,"forest/freshwater bypass heat stress")
	var seasonal_model = Climate.new()
	check(seasonal_model.has_method("seasonal_suitability"),"missing joint seasonal suitability")
	if seasonal_model.has_method("seasonal_suitability"):
		var distributed: Dictionary = seasonal_model.seasonal_suitability(PackedFloat32Array([20,20,20,20]),PackedFloat32Array([300,300,300,300]),0.)
		var concentrated: Dictionary = seasonal_model.seasonal_suitability(PackedFloat32Array([20,20,20,20]),PackedFloat32Array([1200,0,0,0]),0.)
		check(distributed.factor>concentrated.factor*1.5,"one wet quarter masks long warm-season drought")
		var frozen: Dictionary = seasonal_model.seasonal_suitability(PackedFloat32Array([-10,-5,-2,-5]),PackedFloat32Array([300,300,300,300]),65.)
		check(frozen.factor==0.,"cold rainy world supports farming")
		var dry: Dictionary = seasonal_model.seasonal_suitability(PackedFloat32Array([20,20,20,20]),PackedFloat32Array([0,0,0,0]),0.)
		check(dry.factor==0. and dry.growing_months==0,"seasonal scoring invents water in desert")
	var size := Vector2i(72,36); var n := size.x*size.y
	var height := Circulation.zeros(n); var land := PackedByteArray(); land.resize(n); land.fill(1)
	var neutral := Circulation.zeros(n); var cold := neutral.duplicate(); cold.fill(-6.)
	for y in range(size.y):
		for x in range(24): land[y*size.x+x] = 0
	var warm: Dictionary = Circulation.build_fields(height,land,size,{"spinup_steps":60,"sea_temperature_anomaly":neutral})
	var cool: Dictionary = Circulation.build_fields(height,land,size,{"spinup_steps":60,"sea_temperature_anomaly":cold})
	var warm_sum := 0.; var cool_sum := 0.
	for y in range(20,24):
		for x in range(24,29): warm_sum += warm.annual[y*size.x+x]; cool_sum += cool.annual[y*size.x+x]
	check(warm_sum>0. and cool_sum<warm_sum*.5,"cold ocean has no rain-suppressing effect on adjacent subtropical land")
	print("ATLAS_CLIMATE_LIMITS failures=",failures); quit(1 if failures else 0)
