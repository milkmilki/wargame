extends Control
## Vertical genealogy: names above ordered titles, cinnabar emperors.
signal selected(id: int)
const Layout = preload("res://scripts/atlas/family_layout.gd")
const PAPER := Color("f4efdf")
const INK := Color("302b24")
const MUTED := Color("726959")
const SEAL := Color("a23b30")
const SELECTED := Color("996525")
const NAME_X := Layout.NAME_X
var genealogy_font: Font = preload("res://assets/atlas/lxgw-wenkai-gb-500.ttf")
var model := {}; var layout := {}; var focus_id := -1
var scale_value := 1.; var offset := Vector2(40,40)
var dragging := false; var dragged := false; var drag_origin := Vector2.ZERO
var layout_count := 0; var draw_count := 0
var spatial := {}; var signature := -1
var links: Array=[]
func update_model(value: Dictionary) -> void:
	model=value
	var next := preload("res://scripts/atlas/family_model.gd").structural_key(model)
	if next!=signature:
		signature=next; layout=Layout.build(model); layout_count+=1; spatial.clear(); links.clear()
		for id in layout.positions:
			var point: Vector2=layout.positions[id]
			var rect: Rect2=layout.rects[id]
			# Index the entire tall history, including its bottom outside the name cell.
			for y in range(floori(rect.position.y/256.),floori(rect.end.y/256.)+1):
				for x in range(floori(rect.position.x/256.),floori(rect.end.x/256.)+1):
					var key:=Vector2i(x,y)
					if not spatial.has(key): spatial[key]=[]
					spatial[key].append(id)
			var parent: int=layout.parents[id]
			if parent>=0:
				var a:=Vector2(layout.rects[parent].position.x+NAME_X,layout.rects[parent].end.y)
				var b:=point+Vector2(NAME_X,0)
				# All siblings meet on the same generation bar, even with short parents.
				var mid: float=b.y-Layout.GENERATION_GAP*.5
				links.append({"path":PackedVector2Array([a,Vector2(a.x,mid),Vector2(b.x,mid),b]),"bounds":Rect2(a,Vector2.ZERO).expand(b).grow(2)})
	queue_redraw()
func fit_all() -> void:
	if layout.is_empty(): return
	var bounds: Rect2=layout.bounds.grow(30)
	scale_value=clampf(minf(size.x/maxf(bounds.size.x,1.),size.y/maxf(bounds.size.y,1.)),.0001,2.)
	offset=(size-bounds.size*scale_value)*.5-bounds.position*scale_value; queue_redraw()
func locate(id: int) -> void:
	if not layout.get("positions",{}).has(id): return
	focus_id=id
	var rect: Rect2=layout.rects[id]
	scale_value=clampf(minf(1.,(size.y-48.)/rect.size.y),.32,1.)
	offset=size*.5-rect.get_center()*scale_value; queue_redraw(); selected.emit(id)
func visible_ids() -> Array:
	var candidates := {}
	var rect := Rect2(-offset/scale_value,size/scale_value).grow(4)
	if (rect.size.x/256.+2)*(rect.size.y/256.+2)>spatial.size()*2:
		for key in spatial:
			if Rect2(Vector2(key)*256.,Vector2.ONE*256.).intersects(rect):
				for id in spatial[key]: candidates[id]=true
	else:
		for y in range(floori(rect.position.y/256.),floori(rect.end.y/256.)+1):
			for x in range(floori(rect.position.x/256.),floori(rect.end.x/256.)+1):
				for id in spatial.get(Vector2i(x,y),[]): candidates[id]=true
	var result: Array=[]
	for id in candidates:
		if layout.rects[id].intersects(rect): result.append(id)
	return result
func _draw() -> void:
	draw_count+=1
	draw_rect(Rect2(Vector2.ZERO,size),PAPER)
	if model.is_empty(): return
	draw_set_transform(offset,0,Vector2.ONE*scale_value)
	# A connector can cross the viewport while both endpoint boxes are outside.
	var visible_world:=Rect2(-offset/scale_value,size/scale_value)
	for link in links:
		if not link.bounds.intersects(visible_world): continue
		draw_polyline(link.path,Color("9b917e"),maxf(.8,.8/scale_value),true)
	for id in visible_ids(): draw_person(id)
	draw_set_transform(Vector2.ZERO)

func vertical_text(text_value: String, point: Vector2, font_size: int, advance: float, color: Color) -> void:
	for i in range(text_value.length()):
		var glyph := text_value.substr(i,1)
		var width := genealogy_font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		draw_string(genealogy_font,point+Vector2(-width*.5,i*advance+font_size),glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func draw_person(id: int) -> void:
	var member: Dictionary=model.members[id]
	var rect: Rect2=layout.rects[id]
	var point:=rect.position
	var emperor:=bool(member.get("was_emperor",false))
	if id==focus_id:
		draw_rect(rect,Color("ece1c5"))
		draw_rect(rect,SELECTED,false,maxf(1.,1./scale_value))
	if scale_value<.32:
		draw_rect(Rect2(point+Vector2(NAME_X-12,6),Vector2(24,40)),SEAL if emperor else INK)
		return
	var name_text:=str(member.get("tree_name",member.get("name","？")))
	var name_box:=Layout.name_box(member)
	name_box.position+=point
	if emperor:
		draw_rect(name_box,SEAL,false,1.6)
		draw_rect(name_box.grow(-4),SEAL,false,.8)
		draw_rect(Rect2(point+Vector2(NAME_X-11,4),Vector2(22,22)),SEAL)
		draw_string(genealogy_font,point+Vector2(NAME_X-8,21),"帝",HORIZONTAL_ALIGNMENT_LEFT,-1,16,PAPER)
	elif member.get("was_ruler",false): draw_rect(name_box,Color("a39780"),false,.8)
	vertical_text(name_text,point+Vector2(NAME_X,44),20,24,SEAL if emperor else INK)
	var marker := person_marker(id,member)
	if id==model.get("root",-1): marker="先祖"
	vertical_text(marker,point+Vector2(10,8),11,13,SELECTED if id==model.get("current",-1) else MUTED)
	if member.get("taizu",false): vertical_text("太祖",point+Vector2(10,46),12,15,SEAL)
	var steps:=Layout.title_steps(member)
	var top:=Layout.title_top(member)
	for index in range(steps.size()):
		var step: Dictionary=steps[index]
		var height:=Layout.step_height(step)-28.
		var color:=INK if index==steps.size()-1 else MUTED
		vertical_text(str(step.get("title","")),point+Vector2(NAME_X,top),16,18,color)
		vertical_text(str(step.get("label","")),point+Vector2(10,top+2),11,13,color)
		# Brackets separate each designation from its small vertical identity label.
		draw_polyline(PackedVector2Array([point+Vector2(NAME_X-8,top-3),point+Vector2(NAME_X-11,top-3),point+Vector2(NAME_X-11,top+height+2),point+Vector2(NAME_X-8,top+height+2)]),color,.8,true)
		draw_polyline(PackedVector2Array([point+Vector2(NAME_X+8,top-3),point+Vector2(NAME_X+11,top-3),point+Vector2(NAME_X+11,top+height+2),point+Vector2(NAME_X+8,top+height+2)]),color,.8,true)
		if index<steps.size()-1:
			var a:=point+Vector2(NAME_X,top+height+7); var b:=a+Vector2(0,12)
			draw_line(a,b,MUTED,1.,true)
			draw_polyline(PackedVector2Array([b+Vector2(-3,-4),b,b+Vector2(3,-4)]),MUTED,1.,true)
		top+=Layout.step_height(step)
	if member.get("history_partial",false):
		vertical_text("履历未全",point+Vector2(NAME_X,Layout.note_top(member)),10,12,MUTED)

func person_marker(id: int, member: Dictionary) -> String:
	if id==model.get("current",-1): return "现任"
	if member.get("active_ruler",false): return "在位"
	if not member.get("alive",true): return "已故"
	if member.get("crown",false): return "太子"
	if member.get("was_ruler",false): return "前君"
	return "远支" if layout.distant[id] else "宗室"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var point: Vector2=(event.position-offset)/scale_value
			scale_value=clampf(scale_value*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1./1.15),.0001,3.)
			offset=event.position-point*scale_value; queue_redraw()
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
			if event.pressed: dragging=true; dragged=false; drag_origin=event.position
			else:
				dragging=false
				if not dragged and event.button_index==MOUSE_BUTTON_LEFT:
					var point: Vector2=(event.position-offset)/scale_value
					for id in visible_ids():
						if layout.rects[id].has_point(point): focus_id=id; selected.emit(id); queue_redraw(); break
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_origin)>4: dragged=true
		offset+=event.relative; queue_redraw()
	accept_event()
