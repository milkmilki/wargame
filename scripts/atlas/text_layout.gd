extends RefCounted
## Original Polyline, polity alongPath and settlement aroundMark geometry.
## Port of render/labels/{layout,polity,settlements}.ts. AGPL-3.0-only.
static func polyline(flat: Array) -> Dictionary:
	var points: Array = []; var cum: Array = [0.0]
	for i in range(0,flat.size(),2):
		if not points.is_empty() and absf(flat[i]-points[-1][0])<1e-6 and absf(flat[i+1]-points[-1][1])<1e-6: continue
		points.append([float(flat[i]),float(flat[i+1])])
	for i in range(1,points.size()):
		var dx: float = points[i][0]-points[i-1][0]; var dy: float = points[i][1]-points[i-1][1]; cum.append(cum[-1]+sqrt(dx*dx+dy*dy))
	return {"points":points,"cum":cum,"length":cum[-1]}

static func at(path: Dictionary,s: float) -> Vector2:
	var points: Array = path.points; var i := 0; var m := points.size()
	if m==1: return Vector2(points[0][0],points[0][1])
	if s>=path.length: i = m-2
	elif s>0:
		var lo := 0; var hi := m-1
		while hi-lo>1:
			var mid := (lo+hi)>>1
			if path.cum[mid]<=s: lo = mid
			else: hi = mid
		i = lo
	var seg: float = path.cum[i+1]-path.cum[i]; var t: float = (s-path.cum[i])/(seg if seg!=0 else 1)
	return Vector2(points[i][0]+(points[i+1][0]-points[i][0])*t,points[i][1]+(points[i+1][1]-points[i][1])*t)

static func direction(path: Dictionary,s: float,w: float) -> Vector2:
	var length: float = path.length; var a := clampf(s-w,0,length); var b := clampf(s+w,0,length)
	if b-a<minf(length,2*w)*.5:
		if s>=length/2: a = maxf(0,length-maxf(w,1e-6)*2)
		else: b = minf(length,maxf(w,1e-6)*2)
	var d := at(path,b)-at(path,a)
	return d.normalized() if d.length()>1e-9 else Vector2.RIGHT

static func along_path(text: String,flat: Array,px: float,vertical: bool,tracking: Vector2 = Vector2(.5,2.4)) -> Array:
	var path := polyline(flat); var points: Array = path.points; var n := text.length(); var m := points.size()
	if m<2 or n==0: return []
	var gx: float = points[-1][0]-points[0][0]; var gy: float = points[-1][1]-points[0][1]
	if gy<0 if vertical else gx<0:
		var reverse: Array = []
		for i in range(m-1,-1,-1): reverse.append(points[i][0]); reverse.append(points[i][1])
		path = polyline(reverse)
	var length: float = path.length; var pitch := clampf(length*.92/n,px*(1+tracking.x),px*(1+tracking.y)) if n>1 else px
	var span := pitch*(n-1); var normal := Vector2(-gy,gx).normalized()
	if normal.x<0 if vertical else normal.y>0: normal = -normal
	var shifts: Array = []
	for along in [0.,.5,-.5,1.,-1.,1.5,-1.5,2.2,-2.2,3.,-3.]:
		for across in [0.,-.95,.95,-1.8,1.8,-2.6,2.6]: shifts.append([along,across])
	shifts.sort_custom(func(a,b): return absf(a[0])*.8+absf(a[1])<absf(b[0])*.8+absf(b[1]))
	var out: Array = []
	for shift in shifts:
		var center: float = length/2+shift[0]*pitch
		if center-span/2< -px*.3 or center+span/2>length+px*.3: continue
		var offset: Vector2 = normal*shift[1]*px; var glyphs: Array = []
		for i in range(n):
			var s := center-span/2+i*pitch; var p := at(path,s)+offset; var a := 0.0
			if not vertical:
				a = clampf(direction(path,s,pitch*.6).angle(),-deg_to_rad(40),deg_to_rad(40))
				if i>0: a = clampf(a,glyphs[-1].a-deg_to_rad(22),glyphs[-1].a+deg_to_rad(22))
			glyphs.append({"ch":text[i],"pos":p,"a":a})
		out.append(glyphs)
	return out

static func around_mark(text: String,box: Rect2,px: float,rings: int = 1) -> Array:
	var pitch := px*1.04; var w := pitch*(text.length()-1)+px; var g := maxf(2,px*.22); var c := box.get_center(); var out: Array = []
	for ring in range(rings):
		var e := ring*px*.7; var t := 0.0 if ring else g*.9; var x0 := box.position.x; var y0 := box.position.y; var x1 := box.end.x; var y1 := box.end.y
		var positions: Array = [Vector2(x1+g+e+w/2,c.y),Vector2(x0-g-e-w/2,c.y),Vector2(c.x,y0-g-e-px/2),Vector2(c.x,y1+g+e+px/2),Vector2(x1+g+e+w/2-t,y0-g-e-px/2+t),Vector2(x1+g+e+w/2-t,y1+g+e+px/2-t),Vector2(x0-g-e-w/2+t,y0-g-e-px/2+t),Vector2(x0-g-e-w/2+t,y1+g+e+px/2-t)]
		if ring:
			for dx in [-1.,1.]:
				for dy in [-1.,1.]: positions.append(Vector2(x1+g+w/2 if dx>0 else x0-g-w/2,c.y+px*.6*dy))
		for center in positions:
			var glyphs: Array = []
			for i in range(text.length()): glyphs.append({"ch":text[i],"pos":center+Vector2(-w/2+px/2+i*pitch,0),"a":0.0})
			out.append(glyphs)
	return out

static func glyph_boxes(glyphs: Array,px: float,padding: float) -> Array:
	var out: Array = []
	for glyph in glyphs:
		var reach := px*.5*(absf(cos(glyph.a))+absf(sin(glyph.a)))+padding
		out.append(Rect2(glyph.pos-Vector2.ONE*reach,Vector2.ONE*reach*2))
	return out

static func personal_space(glyphs: Array,px: float) -> float:
	if glyphs.size()<2: return px*.6
	var gaps: Array = []
	for i in range(1,glyphs.size()): gaps.append(glyphs[i].pos.distance_to(glyphs[i-1].pos)-px)
	gaps.sort()
	return minf(px*3,maxf(px*.6,maxf(0,gaps[gaps.size()>>1])*1.1+px*.5))

static func line(text: String,flat: Array,px: float,tracking: Vector2) -> Array:
	var path := polyline(flat); var points: Array = path.points
	if text.is_empty() or points.is_empty(): return []
	var center := at(path,path.length/2); var delta := Vector2(points[-1][0]-points[0][0],points[-1][1]-points[0][1]); var length := delta.length(); var unit := delta/length if length>1e-6 else Vector2.RIGHT
	var vertical := absf(unit.y)>absf(unit.x)*1.4
	if (vertical and unit.y<0) or (not vertical and unit.x<0): unit = -unit
	var angle := 0. if vertical else unit.angle()
	if vertical: unit = Vector2.DOWN
	elif absf(angle)<deg_to_rad(6): angle = 0; unit = Vector2.RIGHT
	var pitch := clampf(length/text.length(),px*(1+tracking.x),px*(1+tracking.y)) if text.length()>1 else px
	var normal := Vector2(-unit.y,unit.x); var out: Array = []
	for shift in [[0.,0.],[0.,-.8],[0.,.8],[-1.3,0.],[1.3,0.],[-1.3,-.9],[1.3,.9],[-1.3,.9],[1.3,-.9],[0.,-1.6],[0.,1.6]]:
		var glyphs: Array = []
		for i in range(text.length()): glyphs.append({"ch":text[i],"pos":center+unit*((i-(text.length()-1)/2.)*pitch+shift[0]*px)+normal*shift[1]*px,"a":angle})
		out.append(glyphs)
	return out
static func curve(text: String,flat: Array,px: float,tracking: Vector2) -> Array:
	var path := polyline(flat); var points: Array = path.points
	if text.is_empty() or points.size()<2: return line(text,flat,px,tracking)
	var gx: float = points[-1][0]-points[0][0]; var gy: float = points[-1][1]-points[0][1]; var vertical := absf(gy)>absf(gx)*1.4
	if gy<0 if vertical else gx<0:
		var reversed: Array = []
		for i in range(points.size()-1,-1,-1): reversed.append(points[i][0]); reversed.append(points[i][1])
		path = polyline(reversed)
	var length: float = path.length; var pitch := clampf(length*.92/text.length(),px*(1+tracking.x),px*(1+tracking.y)) if text.length()>1 else px; var span := pitch*(text.length()-1); var out: Array = []
	for f in [.5,.3,.7]:
		var center := length/2 if span>=length else clampf(length*f,span/2,length-span/2)
		if f!=.5 and absf(center-length/2)<pitch*.5: continue
		var glyphs: Array = []
		for i in range(text.length()):
			var s := center-span/2+i*pitch; var angle := 0. if vertical else clampf(direction(path,s,pitch*.6).angle(),-deg_to_rad(40),deg_to_rad(40))
			if i and not vertical: angle = clampf(angle,glyphs[-1].a-deg_to_rad(22),glyphs[-1].a+deg_to_rad(22))
			glyphs.append({"ch":text[i],"pos":at(path,s),"a":angle})
		if vertical and glyphs.size()>1:
			var before: float = (glyphs[0].pos.y+glyphs[-1].pos.y)/2
			for i in range(1,glyphs.size()): glyphs[i].pos.y = maxf(glyphs[i].pos.y,glyphs[i-1].pos.y+px*(1+tracking.x))
			var change: float = before-(glyphs[0].pos.y+glyphs[-1].pos.y)/2
			for glyph in glyphs: glyph.pos.y += change
		out.append(glyphs)
	return out
static func point(text: String,center: Vector2,radius: float,px: float,tracking: float,inside: int,around: int) -> Array:
	var pitch := px*(1+tracking); var width := pitch*(text.length()-1)+px; var g := maxf(2,px*.3)+radius; var dx := g+width/2; var dy := g+px/2; var out: Array = []
	var positions: Array = []
	if inside: positions.append([Vector2.ZERO,inside])
	for p in [Vector2(dx,0),Vector2(-dx,0),Vector2(0,-dy),Vector2(0,dy),Vector2(g*.72+width/2,-g*.72-px/2),Vector2(g*.72+width/2,g*.72+px/2),Vector2(-g*.72-width/2,-g*.72-px/2),Vector2(-g*.72-width/2,g*.72+px/2)]: positions.append([p,around])
	for p in positions:
		var glyphs: Array = []
		for i in range(text.length()): glyphs.append({"ch":text[i],"pos":center+p[0]+Vector2(-width/2+px/2+i*pitch,0),"a":0.})
		out.append({"glyphs":glyphs,"on":p[1]})
	return out
