extends SceneTree
const Spacing = preload("res://scripts/core/river_ferry_spacing.gd")
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("FERRY_SPACING_FAIL: ", message)
func feature(id: int, a: float, b: float) -> Dictionary:
	return {"id": id, "river_class": "major", "points": PackedVector2Array([Vector2(a,.5), Vector2(b,.5)])}
func candidates(features: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for f in features:
		for i in range(1, int(round((f.points[-1].x-f.points[0].x)/.01))):
			var x: float = f.points[0].x + i*.01
			result.append({"river_id":f.id,"river_progress":(x-f.points[0].x)/(f.points[-1].x-f.points[0].x),"position":Vector2(x,.5),"bank_a":0,"bank_b":1,"height":0.0,"relief":0.0})
	return result
func run() -> void:
	var whole: Array = [feature(1,0,.3)]
	var split: Array = [feature(2,.12,.3), feature(1,0,.12)]
	var a := Spacing.select(candidates(whole),whole,1,.06,.012)
	var b := Spacing.select(candidates(split),split,1,.06,.012)
	check(a.selected.size()==5, "length .30 gives five .06 targets")
	var with_terminal := candidates(whole)
	var terminal: Dictionary = with_terminal[-1].duplicate(); terminal.position=Vector2(.3,.5); terminal.river_progress=1.0
	with_terminal.append(terminal)
	check(Spacing.select(with_terminal,whole,1,.06,.012).selected.size()==5,"terminal does not create an extra interval")
	check(a.selected.size()==b.selected.size(), "splits do not multiply ferries")
	for i in range(mini(a.selected.size(), b.selected.size())):
		check(a.selected[i].position.is_equal_approx(b.selected[i].position), "artificial split and feature ordering invariant")
	var doubled := Spacing.select(candidates(whole),whole,2,.06,.012)
	check(doubled.selected.size()==10, "projected arc accounts for map aspect")
	var gap: Array[Dictionary] = []
	for c in candidates(whole):
		if c.position.x<.06 or c.position.x>.12: gap.append(c)
	var missing := Spacing.select(gap,whole,1,.06,.012)
	check(missing.selected.size()==4, "unbuildable interval stays empty")
	var minor := feature(8,0,.3); minor.river_class="tributary"
	check(Spacing.select(candidates([minor]),[minor],1,.06,.012).selected.is_empty(), "tributaries never produce ferry targets")
	var bridges: Array[Dictionary] = [{"bank_a":0,"bank_b":1},{"bank_a":1,"bank_b":2},{"bank_a":0,"bank_b":2},{"bank_a":2,"bank_b":3}]
	var extra := Spacing.connect_components(bridges,4,[Vector2i(0,1)],[],[0,1,2,3])
	check(extra.size()==2, "only two bridges needed for three remaining components")
	check(Spacing.connect_components(bridges,4,[Vector2i(0,1),Vector2i(1,2),Vector2i(2,3)],[],[0,1,2,3]).is_empty(), "already connected worlds need no supplements")
	print("RIVER_FERRY_SPACING: %d failures" % failures)
	quit(1 if failures else 0)
