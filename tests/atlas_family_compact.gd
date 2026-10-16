extends SceneTree
const Canvas = preload("res://scripts/atlas/family_canvas.gd")
const Layout = preload("res://scripts/atlas/family_layout.gd")
class RecordingCanvas extends Canvas:
	var vertical_calls: Array = []
	func vertical_text(value: String, point: Vector2, font_size: int, advance: float, color: Color) -> void:
		vertical_calls.append({"text":value,"point":point,"font_size":font_size,"advance":advance})
		super.vertical_text(value,point,font_size,advance,color)
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAMILY_COMPACT_FAIL ",message)
static func fixture() -> Dictionary:
	var members := {0:{"parent_id":-1,"birth_order":0,"tree_name":"仲直","was_emperor":true,"was_ruler":true,"taizu":true,"alive":false,"history_partial":true,"title_steps":[
		{"title":"齐王","label":"亲王·无封"},{"title":"齐王","label":"亲王·实封"},{"title":"齐王","label":"亲王·收回封地"}]}}
	for id in range(1,7):
		members[id]={"parent_id":0,"birth_order":id,"tree_name":["风","秋彬","玄星","谋辰","仲山","阿木古郎"][id-1],"alive":true,"title_steps":[{"title":"永桂王" if id<6 else "察合台汗","label":"郡王·无封"}]}
	members[2].active_ruler=true; members[3].was_ruler=true; members[4].crown=true
	return {"root":0,"current":1,"members":members}
func settle() -> void:
	for i in range(3): await process_frame
func run() -> void:
	root.size=Vector2i(1280,720)
	var canvas := RecordingCanvas.new(); canvas.size=Vector2(1280,720); canvas.clip_contents=true
	root.add_child(canvas); var model := fixture(); canvas.update_model(model)
	await settle()
	check(Layout.BOX.x<=60 and Layout.STEP.x<=84,"person columns and sibling pitch are horizontally compact")
	check(canvas.layout.bounds.size.x<=480,"six sibling columns fit within a compact tree width")
	for marker in ["先祖","现任","在位","前君","太子","履历未全"]:
		check(canvas.vertical_calls.any(func(call):return call.text==marker),"vertical metadata: "+marker)
	var names: Array=canvas.vertical_calls.filter(func(call):return call.text=="仲直")
	var titles: Array=canvas.vertical_calls.filter(func(call):return call.text=="齐王")
	check(not names.is_empty() and not titles.is_empty() and names[0].point.x==titles[0].point.x and titles[0].point.y>names[0].point.y+48,"title history sits below the name in the same vertical column")
	for id in model.members:
		var rect: Rect2=canvas.layout.rects[id]
		for other in model.members:
			if id<other: check(not rect.intersects(canvas.layout.rects[other]),"person click regions do not overlap")
	for call in canvas.vertical_calls:
		var font_size: int=call.font_size
		var height: float=maxi(str(call.text).length()-1,0)*float(call.advance)+font_size+canvas.genealogy_font.get_descent(font_size)
		var bounds:=Rect2(call.point-Vector2(font_size*.5,0),Vector2(font_size,height))
		check(canvas.layout.rects.values().any(func(rect):return rect.encloses(bounds)),"vertical glyphs remain in their person region: "+str(call.text))
	var count: int=canvas.layout_count
	var original_height: float=canvas.layout.rects[5].size.y
	var updated := model.duplicate(true); updated.members[5].taizu=true; updated.members[5].history_partial=true
	canvas.update_model(updated); await settle()
	check(canvas.layout_count==count+1 and canvas.layout.rects[5].size.y>original_height,"new vertical notes expand and invalidate cached geometry")
	canvas.locate(5); canvas.focus_id=-1
	var point: Vector2=(canvas.layout.rects[5].position+Vector2(36,canvas.layout.rects[5].size.y-10))*canvas.scale_value+canvas.offset
	var press:=InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true; press.position=point
	canvas._gui_input(press); press=press.duplicate(); press.pressed=false; canvas._gui_input(press)
	check(canvas.focus_id==5,"bottom of vertical notes remains clickable")
	# Older presentation sources have only a current designation, no title_steps.
	var legacy := model.duplicate(true); legacy.members[5].erase("title_steps"); legacy.members[5].display_title="秦王"
	canvas.update_model(legacy); await settle()
	count=canvas.layout_count; original_height=canvas.layout.rects[5].size.y
	legacy=legacy.duplicate(true); legacy.members[5].display_title="察合台大汗"
	canvas.vertical_calls.clear(); canvas.update_model(legacy); await settle()
	check(canvas.layout_count==count+1 and canvas.layout.rects[5].size.y>original_height,"fallback designation changes invalidate and expand the same column")
	var fallback: Array=canvas.vertical_calls.filter(func(call):return call.text=="察合台大汗")
	check(not fallback.is_empty() and canvas.layout.rects[5].encloses(Rect2(fallback[0].point-Vector2(8,0),Vector2(16,4*18+16+canvas.genealogy_font.get_descent(16)))),"fallback designation fits below the name without clipping")
	if OS.get_cmdline_user_args().has("--compact-capture") and DisplayServer.get_name()!="headless":
		canvas.update_model(updated); canvas.focus_id=0; canvas.fit_all(); canvas.queue_redraw(); await settle(); RenderingServer.force_draw(true)
		DirAccess.make_dir_recursive_absolute("res://.dbg/family-compact")
		root.get_texture().get_image().save_png("res://.dbg/family-compact/columns.png")
	canvas.queue_free(); await process_frame
	print("FAMILY_COMPACT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
