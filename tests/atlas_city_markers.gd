extends SceneTree
func _initialize(): call_deferred("run")
func run():
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
