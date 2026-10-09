extends SceneTree
const Climate = preload("res://scripts/atlas/climate_settlement.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("SEASONAL_CAPACITY_FAIL ",message)

func score(t: Array,p: Array) -> float:
	return Climate.seasonal_suitability(PackedFloat32Array(t),PackedFloat32Array(p),35.).factor

func _initialize() -> void:
	check(Climate.VERSION=="climate_capacity_v6","new formula must invalidate generation caches")
	check(is_equal_approx(score([10,20,-10,-10],[200,800,0,0]),1.),"two optimum seasons must reach full suitability")
	check(is_equal_approx(score([15,-10,-10,-10],[500,0,0,0]),.625),"one optimum season must not equal two")
	check(score([-10,15,-10,15],[500,0,500,0])==0.,"rain and warmth in different seasons must not combine")
	check(score([-10,15,15,-10],[0,300,300,0])==1.,"cold winter must not penalize two suitable seasons")
	check(score([15,15,15,15],[50,50,50,50])==0.,"quarterly rainfall below dry cutoff must not support cities")
	check(score([15,15,15,15],[1400,1400,1400,1400])==0.,"waterlogged seasons must not retain high scores")
	check(score([30,30,30,30],[500,500,500,500])==0.,"hot cutoff must remove tropical heat support")
	check(score([20.2,20.2,20.2,20.2],[563,563,563,563])>.95,"small excess above 20 C must not collapse Central Plains support")
	check(score([27,27,27,27],[500,500,500,500])<score([24,24,24,24],[500,500,500,500])*.5,"hot-side decline must accelerate after 24 C")
	check(score([15,15,15,15],[500,500,500,500])>score([15,15,15,15],[1000,1000,1000,1000]),"excessive rainfall must reduce suitability")
	for t in range(-20,45,2):
		for p in range(0,2000,100):
			var value := score([t,t,t,t],[p,p,p,p])
			check(is_finite(value) and value>=0. and value<=1.,"score out of range")
	print("ATLAS_SEASONAL_CAPACITY failures=",failures); quit(1 if failures else 0)
