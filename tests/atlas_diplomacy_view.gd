extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_DIPLOMACY_FAIL ",message)
func _initialize():
	if not FileAccess.file_exists("res://scripts/atlas/diplomacy_view.gd"):
		check(false,"shared diplomacy view is missing"); quit(1); return
	var view = load("res://scripts/atlas/diplomacy_view.gd")
	var state := GameState.new()
	for i in range(6):
		var n := Nation.new(); n.id=i; n.name="国%d"%i; n.color=Color(.2,.3,.7); state.nations.append(n)
	for a in range(6):
		for b in range(a+1,6): state.diplomatic_relations[state._diplomacy_key(a,b)]=GameState.DiplomaticRelation.NEUTRAL
	state.diplomatic_relations[state._diplomacy_key(0,1)]=GameState.DiplomaticRelation.WAR
	state.diplomatic_relations[state._diplomacy_key(0,2)]=GameState.DiplomaticRelation.ALLIED
	state.diplomatic_relations[state._diplomacy_key(0,3)]=GameState.DiplomaticRelation.ALLIED
	state.suzerainty[3]={"overlord_id":0,"civil_war":false}
	state.suzerainty[4]={"overlord_id":3,"civil_war":false}
	check(view.kind(state,0,0)=="self" and view.color(state,0,0)==state.nations[0].color,"observer keeps its actual color")
	check(view.kind(state,0,1)=="enemy" and view.kind(state,0,2)=="ally","enemy and alliance categories")
	check(view.kind(state,0,3)=="vassal" and view.kind(state,0,4)=="vassal","direct and indirect peaceful subjects")
	check(view.kind(state,0,5)=="neutral" and view.color(state,0,5)==Color.BLACK,"neutral preserves the legacy palette")
	state.suzerainty[3].civil_war=true
	check(view.kind(state,0,4)!="vassal","civil war breaks the peaceful subject path")
	state.diplomatic_relations[state._diplomacy_key(0,3)]=GameState.DiplomaticRelation.WAR
	check(view.kind(state,0,3)=="enemy","hostility overrides subject status")
	state.nations[0].alive=false
	check(view.kind(state,0,2)=="" and view.color(state,0,2)==state.nations[2].color,"extinct observer restores ordinary country colors")
	check(view.kind(state,-1,2)=="" and view.kind(state,2,999)=="","invalid selections are harmless")
	var live: Array=view.rows(state,2,"国"); check(live.size()==5 and live[0].id==1,"list excludes extinct nations and preserves ID order")
	check(view.rows(state,2,"国4").size()==1,"name search filters stable entries")
	var texture: Dictionary=preload("res://scripts/atlas/wash.gd").id_data(PackedInt32Array([-2,0,4]),3,1)
	check(texture.bytes.to_float32_array()==PackedFloat32Array([-2.,0.,4.]),"owner texture retains transparent sea and stable IDs")
	print("ATLAS_DIPLOMACY_VIEW failures=",failures); quit(1 if failures else 0)
