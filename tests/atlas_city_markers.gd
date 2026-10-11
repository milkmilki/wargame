extends SceneTree
func _initialize(): call_deferred("run")
func run():
	if not administrative_icons(): quit(1); return
	var marks := preload("res://scripts/atlas/city_markers.gd").new(); root.add_child(marks)
	var data := {"cities":[{"region":0,"cell":0,"major":false},{"region":1,"cell":1,"major":false}],"ownership":[0,0],"nations":[{"seat":0,"color":[100,80,60]}],"mesh":{"x":[100.,500.],"y":[100.,100.]}}
	marks.setup(data); marks.set_view(Rect2(50,50,100,100),2.)
	if marks.visible_count!=1: printerr("ATLAS_CITY_FAIL visible city independent of labels"); quit(1); return
	var templates: int = marks.template_builds; var mesh: ArrayMesh = marks.layers[4].mesh.mesh
	marks.set_view(Rect2(50,50,100,100),4.)
	if marks.template_builds!=templates or marks.layers[4].mesh.mesh!=mesh: printerr("ATLAS_CITY_FAIL zoom rebuilt the icon template"); quit(1); return
	if not marks.has_method("set_hover_city"):
		printerr("ATLAS_CITY_FAIL missing animated marker hover"); quit(1); return
	var buffer: PackedFloat32Array=marks.layers[4].mesh.buffer.duplicate()
	var box: Rect2=marks.hit_boxes[0].box
	var anchor:=Vector2(400,400)
	var fringe:=Vector2(box.end.x+1.,anchor.y)
	if marks.hit_city(fringe,8192.)!=-1: printerr("ATLAS_CITY_FAIL territory outside marker is selectable as a city"); quit(1); return
	marks.set_hover_city(0); marks._process(.06)
	var weight: float=marks.hover_weight(0)
	if weight<=0 or weight>=1: printerr("ATLAS_CITY_FAIL hover must ease into its larger size"); quit(1); return
	marks._process(.12)
	if marks.hover_weight(0)!=1. or marks.hit_city(fringe,8192.)!=0: printerr("ATLAS_CITY_FAIL expanded visible icon and click area disagree"); quit(1); return
	if marks.hit_city(anchor+Vector2(8192,0),8192.)!=0: printerr("ATLAS_CITY_FAIL wrapped marker hover"); quit(1); return
	marks.set_hover_city(-1); marks._process(.12)
	if marks.hover_weight(0)!=0. or marks.hit_city(fringe,8192.)!=-1: printerr("ATLAS_CITY_FAIL marker does not shrink on leave"); quit(1); return
	if marks.layers[4].mesh.buffer!=buffer or marks.template_builds!=templates: printerr("ATLAS_CITY_FAIL hover rebuilt static geometry"); quit(1); return
	root.remove_child(marks); marks.free(); print("ATLAS_CITY_MARKERS passed"); quit()

func administrative_icons() -> bool:
	var data := {"cities":[{"region":0,"cell":0,"major":false,"role":"zhou"},{"region":1,"cell":1,"major":true,"role":"fu"},{"region":2,"cell":2,"major":false,"role":"zhou"}],"ownership":[0,0,0],"nations":[{"seat":2,"color":[100,80,60]}],"mesh":{"x":[100.,500.,900.],"y":[100.,100.,100.]}}
	var markers := preload("res://scripts/atlas/city_markers.gd").new()
	root.add_child(markers); markers.setup(data); markers.set_view(Rect2(0,0,1024,256),1.)
	var valid: bool=markers.layers[3].mesh.visible_instance_count==1 and markers.layers[2].mesh.visible_instance_count==1 and markers.layers[4].mesh.visible_instance_count==1
	valid=valid and is_equal_approx(markers.layers[3].mesh.buffer[3],100.) and is_equal_approx(markers.layers[2].mesh.buffer[3],500.)
	data.nations[0].seat=0; markers.setup(data); markers.set_view(Rect2(0,0,1024,256),1.)
	valid=valid and is_equal_approx(markers.layers[3].mesh.buffer[3],900.) and is_equal_approx(markers.layers[4].mesh.buffer[3],100.) and is_equal_approx(markers.layers[2].mesh.buffer[3],500.)
	data.nations[0].seat=2
	markers.free()
	if not valid: printerr("ATLAS_CITY_FAIL ordinary zhou needs a tower; fu uses houses regardless of major; capital retains castle"); return false
	var state := preload("res://scripts/atlas/text_state.gd").new()
	state.data=data; state.show_names=false; state.canvas_size=Vector2(1024,256); state.prepare()
	var kinds := {}
	for mark in state.marks: kinds[mark.index]=mark.kind
	for job in state.all_jobs:
		if job.type=="mark": kinds[job.item.index]=job.item.kind
	if kinds!={0:3,1:2,2:4}: printerr("ATLAS_CITY_FAIL label layout must use administrative glyphs too"); return false
	var legacy := preload("res://scripts/atlas/map_text.gd").new()
	legacy.data=data; legacy.show_names=false; legacy.canvas_size=Vector2(1024,256); legacy.rebuild()
	kinds.clear()
	for mark in legacy.marks: kinds[mark.index]=mark.kind
	legacy.free()
	if kinds!={0:3,1:2,2:4}: printerr("ATLAS_CITY_FAIL reference renderer must agree on administrative glyphs"); return false
	return true
