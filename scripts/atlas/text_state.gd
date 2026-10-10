extends RefCounted
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
var show_city_names := false
var static_geography := false
var show_cities := true
var show_polities := true
var marks: Array = []
var text_rows: Array = []
var buckets := {}
const PLACE_STYLE = {
	"ocean":[[19.,16.5,14.5],Vector2(1.4,3.2),.5,100.,Color8(44,76,92,184),Color8(176,198,197,140),2.],
	"sea":[[14.5,12.5,11.5],Vector2(.8,1.9),.5,88.,Color8(44,76,92,199),Color8(176,198,197,140),2.],
	"bay":[[11.5,11.,10.5],Vector2(.3,.9),.5,60.,Color8(44,76,92,217),Color8(176,198,197,153),2.],
	"mountains":[[13.,11.5,10.5],Vector2(.4,1.4),.45,92.,Color8(78,52,32),Color8(241,230,201,230),2.6],
	"desert":[[13.,11.5,10.5],Vector2(.5,1.4),.45,84.,Color8(122,84,40),Color8(241,230,201,230),2.4],
	"island":[[12.,11.,10.5],Vector2(.1,.6),.4,80.,Color8(58,45,34),Color8(241,230,201,230),2.4],
	"lake":[[11.5,11.,10.5],Vector2(.05,.05),.35,72.,Color8(38,78,116),Color8(241,230,201,230),2.2]}

func add_box(box: Rect2,tag: int) -> void:
	# Rendering copies a canonical layout horizontally. Its conflict field must
	# use the same periodic copies, including labels spanning the seam.
	for shift in [-2048.*zoom,0.,2048.*zoom]:
		add_unwrapped_box(Rect2(box.position+Vector2(shift,0),box.size),tag)

func add_unwrapped_box(box: Rect2,tag: int) -> void:
	for y in range(floori(box.position.y/48),floori(box.end.y/48)+1):
		for x in range(floori(box.position.x/48),floori(box.end.x/48)+1):
			var key := Vector2i(x,y)
			if not buckets.has(key): buckets[key] = []
			buckets[key].append({"box":box,"tag":tag,"job":active_job,"priority":active_priority})

func hits(box: Rect2,ignore: int = -1) -> bool:
	for y in range(floori(box.position.y/48),floori(box.end.y/48)+1):
		for x in range(floori(box.position.x/48),floori(box.end.x/48)+1):
			for other in buckets.get(Vector2i(x,y),[]):
				if other.tag!=ignore and box.intersects(other.box):
					if other.priority>=active_priority: return true
					evicted[other.job] = true
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
		if show_city_names and not keep_mark.is_empty() and not room_for_capital(keep_mark,boxes): continue
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
	evict_boxes(best.boxes,ignore)
	for box in best.boxes: add_box(box,-2)
	best.erase("boxes"); best.job = active_job; text_rows.append(best)
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

func prepare() -> void:
	marks.clear(); text_rows.clear(); buckets.clear()
	active_priority = INF
	if data.is_empty(): return
	var city_marks: Array = []; var symbol_scale := sqrt(2048./1300)*pow(maxf(1,zoom),.5)
	for index in range(data.cities.size()):
		var city: Dictionary = data.cities[index]; var owner := int(data.ownership[city.region]); var kind := 3 if city.major else 2
		if owner>=0 and data.nations[owner].seat==city.region: kind = 4
		var color := Color8(150,60,50)
		if owner>=0:
			var rgb: Array = data.nations[owner].color; color = Color8(rgb[0],rgb[1],rgb[2])
		for shift in [0.]:
			var center := Vector2(data.mesh.x[city.cell]+shift,data.mesh.y[city.cell])*zoom+origin
			if not Rect2(Vector2.ZERO,canvas_size).grow(15*symbol_scale).has_point(center): continue
			var reach := Vector4(5,9,5,3.1) if kind==4 else Vector4(4.4,4.1,4.4,3) if kind==3 else Vector4(3.7,2.7,3.7,2.5)
			var box := Rect2(center-Vector2(reach.x,reach.y)*symbol_scale,Vector2(reach.x+reach.z,reach.y+reach.w)*symbol_scale)
			city_marks.append({"pos":center,"kind":kind,"owner":owner,"color":color,"scale":symbol_scale,"box":box,"name":city.get("name",""),"index":index})
	city_marks.sort_custom(func(a,b): return a.index<b.index if a.kind==b.kind else a.kind>b.kind)
	if show_cities:
		for mark in city_marks:
			if mark.kind==4: mark.job = active_job; marks.append(mark); add_box(mark.box,mark.index)
	var jobs: Array = []
	if show_names:
		for p in data.get("places",[]):
			if not static_geography and zoom<[1.,1.8,3.][clampi(p.rank-1,0,2)]: continue
			var kind: String = "ocean" if p.kind=="sea" and p.name.ends_with("洋") else "bay" if p.kind=="sea" and p.name.ends_with("湾") else p.kind
			jobs.append({"type":"place","item":p,"priority":PLACE_STYLE[kind][3]-(p.rank-1)*30+minf(9,log(1+p.size)/log(2)*.8)})
	if show_cities:
		for mark in city_marks:
			if mark.kind!=4: jobs.append({"type":"mark","item":mark,"priority":100.})
			if show_names and show_city_names and zoom>=[1.,1.,2.,1.3,1.][mark.kind]: jobs.append({"type":"city","item":mark,"priority":[20.,45.,70.,89.,100.5][mark.kind]})
	if show_names and show_polities:
		for label in labels: jobs.append({"type":"nation","item":label,"priority":101+minf(4.9,log(1+label.regions)/log(2)*.7)})
	for i in range(jobs.size()): jobs[i].order = i
	jobs.sort_custom(func(a,b): return a.order<b.order if a.priority==b.priority else a.priority>b.priority)
	all_jobs = jobs
	build_index()

func execute(job: Dictionary) -> void:
	if job.type=="mark":
		var mark: Dictionary = job.item
		if not hits(mark.box):
			evict_boxes([mark.box],mark.index); mark.job = active_job; marks.append(mark); add_box(mark.box,mark.index)
	elif job.type=="city":
		var mark: Dictionary = job.item
		if not marks.has(mark): return
		var px: float = [10.5,10.5,11.5,12.,13.5][mark.kind]*sqrt(2048./1300)*pow(maxf(1,zoom),.3)
		if place(Layout.around_mark(mark.name,mark.box,px,2 if mark.kind==4 else 1),px,Color8(48,30,18) if mark.kind>=3 else Color8(62,42,28),Color8(241,230,201,230),2.3,-1,mark.index,0,0,false,{},.3):
			text_rows[-1].city_id=mark.index
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


const Index = preload("res://scripts/atlas/render_index.gd")
var all_jobs: Array = []
var index := Index.new()
var completed := {}
var active_job := -1
var active_priority := 0.
var evicted := {}

func build_index() -> void:
	for id in range(all_jobs.size()):
		var job: Dictionary = all_jobs[id]; job.id = id
		var box := Rect2()
		if job.type in ["mark","city"]: box = Rect2(job.item.box.position/zoom,job.item.box.size/zoom).grow(128./zoom)
		else:
			var path: Array = job.item.path
			box = Rect2(Vector2(path[0],path[1]),Vector2.ZERO)
			for i in range(2,path.size(),2): box = box.expand(Vector2(path[i],path[i+1]))
			box = box.grow(128./zoom)
			var alternate: Dictionary = job.item.get("alt",{})
			if not alternate.is_empty():
				for i in range(0,alternate.path.size(),2):
					box = box.merge(Rect2(Vector2(alternate.path[i],alternate.path[i+1])-Vector2.ONE*128./zoom,Vector2.ONE*256./zoom))
		index.add(box)

func update(rect: Rect2) -> Dictionary:
	for id in index.query(rect):
		if completed.has(id): continue
		var job: Dictionary = all_jobs[id]
		active_job = id; active_priority = job.priority; evicted.clear()
		execute(job); completed[id] = true
	return {"marks":marks.duplicate(true),"rows":text_rows.duplicate(true),"completed":completed.size()}

func evict_boxes(boxes: Array,ignore: int) -> void:
	if evicted.is_empty(): return
	var victims := {}
	for list in buckets.values():
		for other in list:
			if other.job<0 or other.tag==ignore or other.priority>=active_priority: continue
			if boxes.any(func(box): return box.intersects(other.box)): victims[other.job] = true
	if victims.is_empty(): return
	marks = marks.filter(func(mark): return not victims.has(mark.get("job",-1)))
	text_rows = text_rows.filter(func(row): return not victims.has(row.get("job",-1)))
	for key in buckets: buckets[key] = buckets[key].filter(func(row): return not victims.has(row.job))
	for id in victims: completed.erase(id)

class Pool extends RefCounted:
	var states := {}
	var lru: Array = []
	func calculate(key: String,snapshot: Dictionary,rect: Rect2,detail: float) -> Dictionary:
		if not states.has(key):
			var state = load("res://scripts/atlas/text_state.gd").new()
			state.data = snapshot.data; state.raster = snapshot.raster; state.labels = snapshot.labels; state.owners = snapshot.owners
			state.show_names = snapshot.names; state.show_cities = snapshot.cities; state.show_polities = snapshot.polities
			state.show_city_names = snapshot.get("city_names",false)
			state.static_geography = snapshot.get("static_geography",false)
			state.zoom = detail; state.origin = Vector2.ZERO; state.canvas_size = Vector2(2048,1024)*detail
			state.prepare(); states[key] = state
		lru.erase(key); lru.append(key)
		while lru.size()>4: states.erase(lru.pop_front())
		var result: Dictionary = states[key].update(rect); var bytes: int = snapshot.owners.size()*4
		for state in states.values():
			bytes += state.all_jobs.size()*512+state.marks.size()*384
			for row in state.text_rows: bytes += 128+row.glyphs.size()*512
		result.cache_bytes = bytes
		return result
