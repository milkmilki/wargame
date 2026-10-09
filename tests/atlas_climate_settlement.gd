extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("CLIMATE_SETTLEMENT_FAIL ",message)
func _initialize() -> void:
	var model = load("res://scripts/atlas/climate_settlement.gd")
	if not model: print("CLIMATE_SETTLEMENT_FAIL missing model"); quit(1); return
	check(model.farming_potential(18.,800.,300.)>90.,"wet temperate plain must support agriculture")
	check(model.farming_potential(26.,100.,30.)==0.,"desert invented crop support")
	check(model.farming_potential(-5.,1200.,300.)==0.,"frozen plateau invented crop support")
	check(model.farming_potential(18.,500.,250.)>model.farming_potential(18.,250.,60.),"water supply did not improve farmland")
	check(model.seed_radius(22.)<model.seed_radius(8.),"productive land not denser")
	check(model.seed_radius(.5)>1.5,"dry land still has dense provinces")
	print("ATLAS_CLIMATE_SETTLEMENT failures=",failures); quit(1 if failures else 0)
