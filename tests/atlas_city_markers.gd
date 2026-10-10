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
	root.remove_child(marks); marks.free(); print("ATLAS_CITY_MARKERS passed"); quit()
