extends Control
## Native visible-only tree drawing, based on PeopleLineage.tsx / overview.css.
signal selected(id: int)
const Layout = preload("res://scripts/atlas/family_layout.gd")
const Style = preload("res://scripts/atlas/information_theme.gd")
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
			var key:=Vector2i(floori(point.x/256.),floori(point.y/256.))
			if not spatial.has(key): spatial[key]=[]
			spatial[key].append(id)
			var parent: int=layout.parents[id]
			if parent>=0:
				var a: Vector2=layout.positions[parent]+Vector2(Layout.BOX.x*.5,Layout.BOX.y)
				var b: Vector2=point+Vector2(Layout.BOX.x*.5,0)
				var mid: float=(a.y+b.y)*.5
				links.append({"path":PackedVector2Array([a,Vector2(a.x,mid),Vector2(b.x,mid),b]),"bounds":Rect2(a,Vector2.ZERO).expand(b).grow(2)})
	queue_redraw()
func fit_all() -> void:
	if layout.is_empty(): return
	var bounds: Rect2=layout.bounds.grow(30)
	scale_value=clampf(minf(size.x/maxf(bounds.size.x,1.),size.y/maxf(bounds.size.y,1.)),.0001,2.)
	offset=(size-bounds.size*scale_value)*.5-bounds.position*scale_value; queue_redraw()
func locate(id: int) -> void:
	if not layout.get("positions",{}).has(id): return
	focus_id=id; scale_value=maxf(scale_value,.75); offset=size*.5-(layout.positions[id]+Layout.BOX*.5)*scale_value; queue_redraw(); selected.emit(id)
func visible_ids() -> Array:
	var result: Array=[]
	var rect := Rect2(-offset/scale_value,size/scale_value).grow(180)
	if (rect.size.x/256.+2)*(rect.size.y/256.+2)>spatial.size()*2:
		for key in spatial:
			if Rect2(Vector2(key)*256.,Vector2.ONE*256.).intersects(rect): result.append_array(spatial[key])
		return result
	for y in range(floori(rect.position.y/256.),floori(rect.end.y/256.)+1):
		for x in range(floori(rect.position.x/256.),floori(rect.end.x/256.)+1): result.append_array(spatial.get(Vector2i(x,y),[]))
	return result
func _draw() -> void:
	draw_count+=1
	draw_rect(Rect2(Vector2.ZERO,size),Color("f8f8fa"))
	if model.is_empty(): return
	var font := get_theme_default_font()
	var ids := visible_ids()
	# A connector can cross the viewport while both endpoint boxes are outside.
	var visible_world:=Rect2(-offset/scale_value,size/scale_value)
	for link in links:
		if not link.bounds.intersects(visible_world): continue
		var path:=PackedVector2Array()
		for point in link.path: path.append(point*scale_value+offset)
		draw_polyline(path,Color("b8b8c0"),1.2,true)
	for id in ids:
		var member: Dictionary=model.members[id]
		var rect := Rect2(layout.positions[id]*scale_value+offset,Layout.BOX*scale_value)
		var ink := Style.ACCENT if id==focus_id else Color("9d9da8")
		draw_rect(rect,Color.WHITE if member.was_ruler else Color("f8f8fa"))
		if member.was_ruler: draw_rect(rect,ink,false,1.5)
		else:
			var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
			for i in range(4): draw_dashed_line(corners[i],corners[(i+1)%4],ink,1.,4.,true)
		if scale_value<.32: continue
		var font_size:=maxi(8,roundi(14*scale_value))
		var name_text:=str(member.get("name","未记录"))
		draw_string(font,rect.position+Vector2(9,25)*scale_value,name_text,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-12,font_size,Style.INK)
		draw_string(font,rect.position+Vector2(9,48)*scale_value,str(member.display_title),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-12,maxi(8,roundi(11*scale_value)),Style.MUTED)
		var marker := "当前" if id==model.current else ("太子" if member.get("crown",false) else ("已故" if not member.get("alive",true) else ("曾任君主" if member.was_ruler else ("远支" if layout.distant[id] else "宗室"))))
		if member.get("taizu",false): marker+=" · 太祖"
		elif member.was_emperor and id!=model.current: marker+=" · 曾为帝"
		draw_string(font,rect.position+Vector2(9,67)*scale_value,marker,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-12,maxi(8,roundi(10*scale_value)),Style.ACCENT if id==model.current else Style.MUTED)
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
						if Rect2(layout.positions[id],Layout.BOX).has_point(point): focus_id=id; selected.emit(id); queue_redraw(); break
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_origin)>4: dragged=true
		offset+=event.relative; queue_redraw()
	accept_event()
