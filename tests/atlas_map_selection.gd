extends SceneTree
var failures := 0
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready(): pass
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_PICK_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var view := View.new(); root.add_child(view); view.view_ready=true; view.state=GameState.new()
	for i in range(2):
		var nation := Nation.new(); nation.id=i; nation.name="国%d"%i; view.state.nations.append(nation)
		var city := City.new(); city.id=i; city.name="城%d"%i; city.owner_nation=i; view.state.cities.append(city)
	view.data={"ownership":PackedInt32Array([0,1])}; view.zoom=1.
	view.province_labels.resize(2048*1024); view.province_labels.fill(-2)
	view.political_labels=view.province_labels.duplicate()
	for x in range(95,106):
		view.province_labels[100*2048+x]=0; view.political_labels[100*2048+x]=0
	view.province_labels[100*2048+105]=1; view.political_labels[100*2048+105]=1
	for name_value in ["政治","地形","府辖区","宜居度"]: view.mode_control.add_item(name_value)
	if not view.has_method("pick_map"):
		check(false,"unified map picking is missing"); root.remove_child(view); view.queue_free(); await process_frame; quit(1); return
	view.player_nation.value=1; view.select_at(Vector2(100,100))
	check(view.information_kind=="nation" and view.information_id==0,"political empty territory opens country")
	check(view.player_nation.value==1 and view.command_target==-1,"inspection changes neither player nor military order target")
	view.mode_control.selected=2; view.select_at(Vector2(100,100))
	check(view.information_kind=="city" and view.information_id==0,"district mode opens administrative seat")
	var wrapped: Dictionary=view.pick_map(Vector2(2148,100),false)
	check(wrapped.district_id==0 and wrapped.owner_id==0,"longitude copy uses the same territory")
	view.select_at(Vector2(100,-1)); check(view.information_kind.is_empty() and view.selected_region==-1 and view.command_target==-1,"invalid latitude clears stale selection")
	view.select_at(Vector2(400,100)); check(view.information_kind.is_empty(),"ocean clears inspection")
	view.mode_control.selected=0
	# The displayed curved political edge crosses the district raster. Use its
	# actual visible owner and seek a compatible local district for commands.
	view.political_labels[100*2048+100]=1
	var seam: Dictionary=view.pick_map(Vector2(100,100),false)
	check(seam.owner_id==1 and seam.district_id==1,"visible political owner wins at a smoothed border")
	view.province_labels[100*2048+100]=-2
	check(view.pick_map(Vector2(100,100),false).owner_id==1,"visible political fill remains selectable without a district at the exact pixel")
	view.political_pending=true; view.select_at(Vector2(105,100))
	view.political_pending=false; view.political_display_ready()
	check(view.information_kind=="nation" and view.information_id==1,"click during background political update is replayed")
	view.political_pending=true; view.select_at(Vector2(105,100)); view.show_information("nation",0)
	view.political_pending=false; view.political_display_ready()
	check(view.information_id==0,"a later explicit selection replaces a queued map click")
	view.political_pending=true; view.select_at(Vector2(105,100)); view.mode_control.selected=2
	view.political_pending=false; view.political_display_ready()
	check(view.information_id==0,"queued click cannot overwrite a later mode change")
	view.mode_control.selected=0
	view.text_layer.high_performance=true; view.text_layer.marker_detail=1.
	var markers=preload("res://scripts/atlas/city_markers.gd").new(); view.text_layer.add_child(markers); view.text_layer.city_markers=markers
	markers.setup({"cities":[{"region":0,"cell":0,"major":false}],"ownership":[0],"nations":[{"seat":0,"color":[100,80,60]}],"mesh":{"x":[100.],"y":[100.]}})
	markers.set_view(Rect2(0,0,2048,1024),1.)
	if not view.has_method("update_city_hover"):
		check(false,"city hover input is missing")
	else:
		view.update_city_hover(Vector2(100,100))
		check(view.hovered_city==0 and view.pick_map(Vector2(100,100)).kind=="city","hovered icon uses the city click target")
		view.province_labels[100*2048+125]=1; view.political_labels[100*2048+125]=1
		view.update_city_hover(Vector2(125,100)); view.select_at(Vector2(125,100))
		check(view.hovered_city==-1 and view.information_kind=="nation" and view.information_id==1,"territory outside icons keeps country selection")
		view.update_city_hover(Vector2(100,100),true)
		check(view.hovered_city==-1,"UI suppresses underlying marker hover")
		view.dragging=true; view.update_city_hover(Vector2(100,100))
		check(view.hovered_city==-1,"panning suppresses marker hover")
		view.dragging=false; view.update_city_hover(Vector2(2148,100))
		check(view.hovered_city==0,"wrapped city copy is hoverable")
		view.text_layer.show_cities=false; view.update_city_hover(Vector2(100,100))
		check(view.hovered_city==-1,"hidden cities cannot stay hovered")
	root.remove_child(view); view.queue_free(); await process_frame
	print("ATLAS_MAP_SELECTION failures=",failures); quit(1 if failures else 0)
