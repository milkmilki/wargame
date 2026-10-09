extends Node2D
## Native screen-space label/settlement layer. Layout comes from original atlas paths.
## Port of render/labels/{draw,polity,settlements}.ts / civ/settlements.ts.
## Static preview: all eligible seats are cities; capitals/majors use castle/large-city marks.
## AGPL-3.0-only.
const Layout = preload("res://scripts/atlas/text_layout.gd")
const CitySymbols = preload("res://scripts/atlas/city_symbols.gd")
var data: Dictionary = {}
var raster: Dictionary = {}
var labels: Array = []
var owners := PackedInt32Array()
var origin := Vector2.ZERO
var zoom := 1.0
var canvas_size := Vector2(2048,1024)
var show_names := true
var show_cities := true
var show_polities := true
var marks: Array = []
var text_rows: Array = []
var buckets := {}
var font: Font = preload("res://assets/atlas/lxgw-wenkai-gb-500.ttf")
var bold_font := FontVariation.new()
const PLACE_STYLE = {
	"ocean":[[19.,16.5,14.5],Vector2(1.4,3.2),.5,100.,Color8(44,76,92,184),Color8(176,198,197,140),2.],
	"sea":[[14.5,12.5,11.5],Vector2(.8,1.9),.5,88.,Color8(44,76,92,199),Color8(176,198,197,140),2.],
	"bay":[[11.5,11.,10.5],Vector2(.3,.9),.5,60.,Color8(44,76,92,217),Color8(176,198,197,153),2.],
	"mountains":[[13.,11.5,10.5],Vector2(.4,1.4),.45,92.,Color8(78,52,32),Color8(241,230,201,230),2.6],
	"desert":[[13.,11.5,10.5],Vector2(.5,1.4),.45,84.,Color8(122,84,40),Color8(241,230,201,230),2.4],
	"island":[[12.,11.,10.5],Vector2(.1,.6),.4,80.,Color8(58,45,34),Color8(241,230,201,230),2.4],
	"lake":[[11.5,11.,10.5],Vector2(.05,.05),.35,72.,Color8(38,78,116),Color8(241,230,201,230),2.2]}

func _init() -> void:
	bold_font.base_font = font; bold_font.variation_embolden = .65

func add_box(box: Rect2,tag: int) -> void:
	for y in range(floori(box.position.y/48),floori(box.end.y/48)+1):
		for x in range(floori(box.position.x/48),floori(box.end.x/48)+1):
			var key := Vector2i(x,y)
			if not buckets.has(key): buckets[key] = []
			buckets[key].append({"box":box,"tag":tag})

func hits(box: Rect2,ignore: int = -1) -> bool:
	for y in range(floori(box.position.y/48),floori(box.end.y/48)+1):
		for x in range(floori(box.position.x/48),floori(box.end.x/48)+1):
			for other in buckets.get(Vector2i(x,y),[]):
				if other.tag!=ignore and box.intersects(other.box): return true
	return false

func country_at(screen: Vector2) -> int:
	var p := (screen-origin)/zoom; var x := floori(fposmod(p.x,2048)); var y := floori(p.y)
	return owners[y*2048+x] if y>=0 and y<1024 else -1

func place(candidates: Array,px: float,color: Color,halo: Color,halo_width: float,owner: int = -1,ignore: int = -1,on: int = 0,tolerance: float = 0.,bold: bool = false,keep_mark: Dictionary = {},space: float = -1.) -> bool:
	var best := {}; var best_misses := INF
	for glyphs in candidates:
		var pad := halo_width+1.5
		var boxes := Layout.glyph_boxes(glyphs,px,pad); var valid := true
		for box in boxes:
			if box.position.x<0 or box.position.y<0 or box.end.x>canvas_size.x or box.end.y>canvas_size.y: valid = false; break
		boxes = Layout.glyph_boxes(glyphs,px,pad+(space*px if space>=0 else Layout.personal_space(glyphs,px))*.5)
		for box in boxes:
			if hits(box,ignore): valid = false; break
		if not valid: continue
		if not keep_mark.is_empty() and not room_for_capital(keep_mark,boxes): continue
		var misses := 0.
		if on or owner>=0:
			var bad := 0; var samples := 0
			for glyph in glyphs:
				for a in range(-1,2):
					for b in range(-1,2):
						var screen: Vector2 = glyph.pos+(Vector2(a,b)*px*.46).rotated(glyph.a)
						var point := (screen-origin)/zoom; var y := floori(point.y); var x := floori(fposmod(point.x,2048)); var surface := -1 if y<0 or y>=1024 else int(raster.water[y*2048+x]); samples += 1
						if on and (surface<0 or (on&(1<<surface))==0): bad += 1; continue
						if owner>=0 and country_at(screen)!=owner:
							if a==0 and b==0: bad = 1000000
							bad += 1
			misses = float(bad)/samples
			if misses>tolerance: continue
		if misses<best_misses:
			best = {"glyphs":glyphs,"px":px,"color":color,"halo":halo,"halo_width":halo_width,"bold":bold,"boxes":boxes}; best_misses = misses
		if misses==0: break
	if best.is_empty(): return false
	for box in best.boxes: add_box(box,-2)
	best.erase("boxes"); text_rows.append(best)
	return true

func room_for_capital(mark: Dictionary,new_boxes: Array) -> bool:
	var px := 13.5*sqrt(2048./1300)*pow(maxf(1,zoom),.3)
	for candidate in Layout.around_mark(mark.name,mark.box,px,2):
		var valid := true
		for box in Layout.glyph_boxes(candidate,px,2.3+1.5+px*.15):
			if box.position.x<0 or box.position.y<0 or box.end.x>canvas_size.x or box.end.y>canvas_size.y or hits(box,mark.index): valid = false; break
			for proposed in new_boxes:
				if box.intersects(proposed): valid = false; break
			if not valid: break
		if valid: return true
	return false

func rebuild() -> void:
	marks.clear(); text_rows.clear(); buckets.clear()
	if data.is_empty(): return
	var city_marks: Array = []; var symbol_scale := sqrt(2048./1300)*pow(maxf(1,zoom),.5)
	for index in range(data.cities.size()):
		var city: Dictionary = data.cities[index]; var owner := int(data.ownership[city.region]); var kind := 3 if city.major else 2
		if owner>=0 and data.nations[owner].seat==city.region: kind = 4
		var color := Color8(150,60,50)
		if owner>=0:
			var rgb: Array = data.nations[owner].color; color = Color8(rgb[0],rgb[1],rgb[2])
		for shift in [-2048.,0.,2048.]:
			var center := Vector2(data.mesh.x[city.cell]+shift,data.mesh.y[city.cell])*zoom+origin
			if not Rect2(Vector2.ZERO,canvas_size).grow(15*symbol_scale).has_point(center): continue
			var reach := Vector4(5,9,5,3.1) if kind==4 else Vector4(4.4,4.1,4.4,3) if kind==3 else Vector4(3.7,2.7,3.7,2.5)
			var box := Rect2(center-Vector2(reach.x,reach.y)*symbol_scale,Vector2(reach.x+reach.z,reach.y+reach.w)*symbol_scale)
			city_marks.append({"pos":center,"kind":kind,"owner":owner,"color":color,"scale":symbol_scale,"box":box,"name":city.get("name",""),"index":index})
	city_marks.sort_custom(func(a,b): return a.index<b.index if a.kind==b.kind else a.kind>b.kind)
	if show_cities:
		for mark in city_marks:
			if mark.kind==4: marks.append(mark); add_box(mark.box,mark.index)
	var jobs: Array = []
	if show_names:
		for p in data.get("places",[]):
			if zoom<[1.,1.8,3.][clampi(p.rank-1,0,2)]: continue
			var kind: String = "ocean" if p.kind=="sea" and p.name.ends_with("洋") else "bay" if p.kind=="sea" and p.name.ends_with("湾") else p.kind
			jobs.append({"type":"place","item":p,"priority":PLACE_STYLE[kind][3]-(p.rank-1)*30+minf(9,log(1+p.size)/log(2)*.8)})
	if show_cities:
		for mark in city_marks:
			if mark.kind!=4: jobs.append({"type":"mark","item":mark,"priority":100.})
			if show_names and zoom>=[1.,1.,2.,1.3,1.][mark.kind]: jobs.append({"type":"city","item":mark,"priority":[20.,45.,70.,89.,100.5][mark.kind]})
	if show_names and show_polities:
		for label in labels: jobs.append({"type":"nation","item":label,"priority":101+minf(4.9,log(1+label.regions)/log(2)*.7)})
	for i in range(jobs.size()): jobs[i].order = i
	jobs.sort_custom(func(a,b): return a.order<b.order if a.priority==b.priority else a.priority>b.priority)
	for job in jobs:
		if job.type=="mark":
			var mark: Dictionary = job.item
			if not hits(mark.box): marks.append(mark); add_box(mark.box,mark.index)
		elif job.type=="city":
			var mark: Dictionary = job.item
			if not marks.has(mark): continue
			var px: float = [10.5,10.5,11.5,12.,13.5][mark.kind]*sqrt(2048./1300)*pow(maxf(1,zoom),.3)
			place(Layout.around_mark(mark.name,mark.box,px,2 if mark.kind==4 else 1),px,Color8(48,30,18) if mark.kind>=3 else Color8(62,42,28),Color8(241,230,201,230),2.3,-1,mark.index,0,0,false,{},.3)
		elif job.type=="place": place_geography(job.item)
		else:
			var label: Dictionary = job.item
			var capital := {}
			for mark in marks:
				if mark.kind==4 and mark.owner==label.polity: capital = mark; break
			var color_rgb: Array = data.nations[label.polity].color; var small := clampf((18-label.size*1300/2048)/7,0,1)
			var color := Color8(color_rgb[0],color_rgb[1],color_rgb[2]).lerp(Color8(56,30,18),.62+.2*small); color.a = .9+.08*small
			var px: float = maxf(10.5,label.size*pow(maxf(1,zoom),.45)*minf(1,zoom)); var found := false
			for source in [label,label.get("alt",{})]:
				if source.is_empty() or found: continue
				var source_size: float = px*minf(1,source.size/label.size)
				for factor in [1.,.86,.74]:
					if found: break
					var s := maxf(10.5,source_size*factor)
					for shift in [-2048.,0.,2048.]:
						var path: Array = []
						for i in range(0,source.path.size(),2): path.append((source.path[i]+shift)*zoom+origin.x); path.append(source.path[i+1]*zoom+origin.y)
						var halo := Color8(241,230,201); halo.a = .7+.22*small
						if place(Layout.along_path(label.text,path,s,source.vertical),s,color,halo,2.2+.4*small,label.polity,-1,0,.1,false,capital,.35): found = true; break
	queue_redraw()

func place_geography(p: Dictionary) -> void:
	var kind: String = "ocean" if p.kind=="sea" and p.name.ends_with("洋") else "bay" if p.kind=="sea" and p.name.ends_with("湾") else p.kind
	var style: Array = PLACE_STYLE[kind]; var px: float = style[0][clampi(p.rank-1,0,2)]*sqrt(2048./1300)*pow(maxf(1,zoom),style[2]); var on := 2 if p.kind=="sea" else 5; var tolerance := .06 if p.kind=="sea" else .08 if p.kind in ["mountains","desert"] else 0.
	var color: Color = style[4]; var halo: Color = style[5]; var min_zoom: float = [1.,1.8,3.][clampi(p.rank-1,0,2)]
	var fade := clampf((zoom-min_zoom*.92)/(min_zoom*.1),0,1) if min_zoom>1 else 1.; color.a *= fade; halo.a *= fade
	for shift in [-2048.,0.,2048.]:
		var path: Array = []
		for i in range(0,p.path.size(),2): path.append((p.path[i]+shift)*zoom+origin.x); path.append(p.path[i+1]*zoom+origin.y)
		if p.kind=="lake":
			for row in Layout.point(p.name,Vector2(path[0],path[1]),p.size*.9*zoom,px,style[1].x,4,1):
				if place([row.glyphs],px,color,halo,style[6],-1,-1,row.on,.04): return
		else:
			var candidates := Layout.curve(p.name,path,px,style[1]) if p.kind=="mountains" else Layout.line(p.name,path,px,style[1])
			if place(candidates,px,color,halo,style[6],-1,-1,on,tolerance): return
			if p.kind=="island":
				for row in Layout.point(p.name,Layout.at(Layout.polyline(path),Layout.polyline(path).length/2),p.size*zoom,px,style[1].x,0,2):
					if place([row.glyphs],px,color,halo,style[6],-1,-1,row.on): return

func _draw() -> void:
	for mark in marks: CitySymbols.draw(self,mark.pos,mark.scale,mark.kind,mark.color)
	for row in text_rows:
		var row_font: Font = bold_font if row.bold else font
		# Rasterize near the displayed size: downscaling a 128 px hinted glyph loses
		# its thin halo and produces jagged strokes. Source strokeText uses a full
		# halo radius (lineWidth = halo.width * 2), rather than half that radius.
		var font_px := maxi(1,ceili(row.px)); var scale_value: float = row.px/font_px
		var baseline := (row_font.get_ascent(font_px)-row_font.get_descent(font_px))*.5+font_px*.04
		for glyph in row.glyphs:
			draw_set_transform(glyph.pos,glyph.a,Vector2.ONE*scale_value)
			var width := row_font.get_string_size(glyph.ch,HORIZONTAL_ALIGNMENT_LEFT,-1,font_px).x
			# Godot's raster outline cache uses oversampled pixels for its radius.
			draw_string_outline(row_font,Vector2(-width*.5,baseline),glyph.ch,HORIZONTAL_ALIGNMENT_LEFT,-1,font_px,maxi(1,roundi(row.halo_width*2./scale_value)),row.halo,3,TextServer.DIRECTION_AUTO,TextServer.ORIENTATION_HORIZONTAL,2.)
			draw_string(row_font,Vector2(-width*.5,baseline),glyph.ch,HORIZONTAL_ALIGNMENT_LEFT,-1,font_px,row.color,3,TextServer.DIRECTION_AUTO,TextServer.ORIENTATION_HORIZONTAL,2.)
	draw_set_transform(Vector2.ZERO)
