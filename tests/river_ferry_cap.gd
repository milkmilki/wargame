extends SceneTree
const Spacing = preload("res://scripts/core/river_ferry_spacing.gd")
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("FERRY_CAP_FAIL: ",message)
func feature(id: int,a: Vector2,b: Vector2) -> Dictionary:
	return {"id":id,"river_class":"major","points":PackedVector2Array([a,b])}
func candidates(features: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for f in features:
		var steps := int(round(f.points[0].distance_to(f.points[1])*100))
		for i in range(1,steps):
			var progress := float(i)/steps
			result.append({"river_id":f.id,"river_progress":progress,"position":f.points[0].lerp(f.points[1],progress),"bank_a":0,"bank_b":1,"height":0.0,"relief":0.0})
	return result
func run() -> void:
	var whole: Array = [feature(1,Vector2(0,.5),Vector2(.6,.5))]
	var split: Array = [feature(3,Vector2(.4,.5),Vector2(.6,.5)),feature(1,Vector2(0,.5),Vector2(.2,.5)),feature(2,Vector2(.2,.5),Vector2(.4,.5))]
	var a := Spacing.select(candidates(whole),whole,1,.06,.012,5)
	var b := Spacing.select(candidates(split),split,1,.06,.012,5)
	check(a.selected.size()==5,"long river has at most five ferries")
	check(a.selected.size()==b.selected.size(),"reach cuts do not reset cap")
	for i in range(mini(a.selected.size(),b.selected.size())): check(a.selected[i].position.is_equal_approx(b.selected[i].position),"split and order preserve ferry locations")
	if not a.selected.is_empty(): check(a.selected[-1].position.x>.48 and a.selected[0].position.x<.12,"five ferries spread over full river")
	var branched: Array = [feature(1,Vector2(0,.5),Vector2(.3,.5)),feature(2,Vector2(0,.8),Vector2(.3,.5)),feature(3,Vector2(.3,.5),Vector2(.6,.5))]
	check(Spacing.select(candidates(branched),branched,1,.06,.012,5).selected.size()<=5,"confluence branches share the cap")
	var separate: Array = [whole[0],feature(8,Vector2(0,.9),Vector2(.6,.9))]
	check(Spacing.select(candidates(separate),separate,1,.06,.012,5).selected.size()==10,"independent rivers have independent caps")
	check(Spacing.select(candidates(whole),whole,1,.06,.012).selected.size()==10,"absent cap retains old interval model")
	var regular: Array[Dictionary] = []
	for i in range(5): regular.append({"bank_a":0,"bank_b":1,"ferry_river":"r"})
	var bridge: Array[Dictionary] = [{"bank_a":1,"bank_b":2,"ferry_river":"r"}]
	check(Spacing.connect_components(bridge,3,[],regular,[0,1,2],Callable(),5).is_empty(),"supplement cannot exceed five total")
	regular.pop_back()
	check(Spacing.connect_components(bridge,3,[],regular,[0,1,2],Callable(),5).size()==1,"supplement can use remaining quota")
	print("RIVER_FERRY_CAP: %d failures" % failures)
	quit(1 if failures else 0)
