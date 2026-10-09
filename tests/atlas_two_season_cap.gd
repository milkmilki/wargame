extends SceneTree
const Climate = preload("res://scripts/atlas/climate_settlement.gd")
var failures := 0

func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("TWO_SEASON_CAP_FAIL ",message)

func result(temperature: Array,rain: Array) -> Dictionary:
	return Climate.seasonal_suitability(PackedFloat32Array(temperature),PackedFloat32Array(rain),30.)

func _initialize() -> void:
	check(Climate.VERSION=="climate_capacity_v6","new scoring must invalidate generation metadata/caches")
	check(is_equal_approx(result([22,22,-10,-10],[300,300,0,0]).factor,1.),"two high-scoring seasons must saturate without requiring perfect scores")
	var one := result([15,-10,-10,-10],[300,0,0,0])
	check(is_equal_approx(one.factor,.625),"one perfect season must provide partial support, below the cap")
	var two := result([15,15,-10,-10],[300,300,0,0])
	var four := result([15,15,15,15],[300,300,300,300])
	check(two.factor==1. and four.factor==two.factor,"extra good seasons must not increase capped support")
	var hot_wet := result([15,15,27,27],[300,300,1500,1500])
	check(hot_wet.factor==two.factor and hot_wet.annual_penalty==1.,"other seasons must not subtract productive-season support")
	check(result([15,-10,15,-10],[0,300,0,300]).factor==0.,"rain and warmth must coincide within a season")
	check(result([30,30,30,30],[300,300,300,300]).factor==0.,"unchanged heat cutoff must still apply")
	check(result([15,15,15,15],[1400,1400,1400,1400]).factor==0.,"unchanged per-season wet cutoff must still apply")
	check(result([15,15,15,15],[0,0,0,0]).factor==0.,"no water must provide no support")
	# Permuting the same seasons cannot change the two-best aggregation.
	var partial := result([15,22,-5,29],[120,300,200,1000])
	check(is_equal_approx(partial.factor,result([29,-5,22,15],[1000,200,300,120]).factor),"season-order dependence introduced")
	check(is_equal_approx(partial.quarter_scores[0],Climate.rainfall_factor(120.)),"per-season rainfall curve changed")
	check(is_equal_approx(partial.quarter_scores[1],Climate.thermal_factor(22.)),"per-season temperature curve changed")
	for t in range(-20,45,2):
		for p in range(0,2000,100):
			var value: float = result([t,t,t,t],[p,p,p,p]).factor
			check(is_finite(value) and value>=0. and value<=1.,"non-finite or out-of-range support")
	print("ATLAS_TWO_SEASON_CAP failures=",failures); quit(1 if failures else 0)
