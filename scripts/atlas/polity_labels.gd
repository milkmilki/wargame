extends RefCounted
## Native port of render/labels/polity.ts, equirectangular static preview.
## Original chamfer field, 72 rays, size ladder, curved/vertical fit and capital holes.
## AGPL-3.0-only; historical titles and non-cylindrical projections are excluded.
const RAYS := 72
const STEP := 2.0
const G := 4

static func field(regions: PackedInt32Array,ownership: PackedInt32Array,gw: int,gh: int) -> Dictionary:
	var owner := PackedInt32Array(); owner.resize(gw*gh)
	var d := PackedFloat32Array(); d.resize(gw*gh)
	for i in range(owner.size()): owner[i] = ownership[regions[i]] if regions[i]>=0 else -1
	for y in range(gh):
		for x in range(gw):
			var i := y*gw+x; var o := owner[i]; var v := 1e9
			if o<0: d[i] = 0; continue
			if y==0 or y==gh-1: v = .5
			else:
				var l := y*gw+posmod(x-1,gw); var r := y*gw+posmod(x+1,gw)
				if owner[l]!=o or owner[r]!=o or owner[i-gw]!=o or owner[i+gw]!=o: v = .5
				elif owner[l-gw]!=o or owner[r-gw]!=o or owner[l+gw]!=o or owner[r+gw]!=o: v = .71
			d[i] = v
	for _pass in range(2):
		for reverse in [false,true]:
			for y in range(gh-2,0,-1) if reverse else range(1,gh):
				for x in range(gw-1,-1,-1) if reverse else range(gw):
					var i: int = y*gw+x; var o := owner[i]
					if o<0 or d[i]<=.5: continue
					var l: int = y*gw+posmod(x-1,gw); var r: int = y*gw+posmod(x+1,gw); var row := gw if reverse else -gw
					var v := float(d[i]); var side: int = r if reverse else l
					for pair in [[side,1.0],[i+row,1.0],[r+row if reverse else l+row,sqrt(2.)],[l+row if reverse else r+row,sqrt(2.)]]:
						if owner[pair[0]]==o and d[pair[0]]+pair[1]<v: v = d[pair[0]]+pair[1]
					d[i] = v
	for i in range(d.size()): d[i] = 0 if owner[i]<0 else maxf(0,(d[i]-.35)*G)
	return {"owner":owner,"dist":d,"gw":gw,"gh":gh}

static func depth_at(f: Dictionary,i: int,hole: Array) -> float:
	var d := float(f.dist[i])
	if hole.is_empty(): return d
	var x := (i%int(f.gw)+.5)*G; var y := (i/int(f.gw)+.5)*G
	var dx: float = x-hole[0]; dx -= f.gw*G*floor(dx/(f.gw*G)+.5)
	var dy: float = y-hole[1]
	return minf(d,maxf(0,sqrt(dx*dx+dy*dy)-hole[2]))

static func cast_rays(f: Dictionary,p: int,cell: int,max_length: float,hole: Array = []) -> Dictionary:
	var cx := cell%int(f.gw)+.5; var cy := cell/int(f.gw)+.5
	if not hole.is_empty():
		hole = hole.duplicate(); var dx: float = hole[0]-cx*G; dx -= f.gw*G*floor(dx/(f.gw*G)+.5); hole[0] = cx*G+dx
	var count := maxi(2,ceili(max_length/STEP)+1)
	var profile := PackedFloat32Array(); profile.resize(RAYS*count)
	var lengths := PackedInt32Array(); lengths.resize(RAYS)
	var depth := depth_at(f,cell,hole)
	for r in range(RAYS):
		var a := r*5*PI/180; var co := cos(a); var si := sin(a); var m := depth; var j := 1
		profile[r*count] = m
		while j<count:
			var x := cx+co*j*.5; var y := cy+si*j*.5
			var gx := posmod(floori(x),int(f.gw)); var gy := floori(y); var v := 0.0
			if gy>=0 and gy<f.gh:
				var i: int = gy*f.gw+gx
				if f.owner[i]==p:
					v = f.dist[i]
					if not hole.is_empty():
						var dx: float = x*G-hole[0]; var dy: float = y*G-hole[1]; v = minf(v,maxf(0,sqrt(dx*dx+dy*dy)-hole[2]))
			m = minf(m,v); profile[r*count+j] = m
			if m<=0: break
			j += 1
		lengths[r] = mini(j+1,count)
	return {"px":cx*G,"py":cy*G,"depth":depth,"prof":profile,"len":lengths,"max_steps":count}

static func reach(rays: Dictionary,r: int,height: float) -> float:
	var base: int = r*rays.max_steps; var lo := 0; var hi: int = rays.len[r]-1
	if rays.prof[base]<height: return -1
	while lo<hi:
		var mid := (lo+hi+1)>>1
		if rays.prof[base+mid]>=height: lo = mid
		else: hi = mid-1
	return lo*STEP

static func fit_text(rays: Dictionary,n: int,sizes: Array,table: Array,vertical: bool) -> Dictionary:
	for index in range(sizes.size()):
		var s: float = sizes[index]; var height := s*.55+2
		if rays.depth<height: continue
		var need := s*(1.8*(n-1)+1); var best := {}; var best_score := -INF
		var min_d := 36-int(floor((12. if vertical else 35.)/5))
		for i in range(RAYS):
			var li: float = table[index][i]
			if li<0: continue
			for delta in range(min_d,37):
				var j := (i+delta)%RAYS; var lj: float = table[index][j]
				if lj<0 or li+lj<need: continue
				var ia := i*5*PI/180; var ja := j*5*PI/180
				var ax := cos(ia)*li; var ay := sin(ia)*li; var bx := cos(ja)*lj; var by := sin(ja)*lj
				var tilt := atan2(absf(by-ay),absf(bx-ax))*180/PI; var turn := absf(180-delta*5)
				var w: float
				if vertical:
					if tilt<72: continue
					w = 1-.3*pow((90-tilt)/18,2)
				else:
					if tilt>25: continue
					w = 1-.5*pow(tilt/25,2)
				w *= 1-.3*pow(turn/35,2)
				var score := (li+lj)*w*(1+.1*minf(li,lj)/maxf(maxf(li,lj),1e-6))
				if score>best_score:
					best_score = score; best = {"size":s,"i":i,"j":j,"li":li,"lj":lj,"vertical":vertical}
		if not best.is_empty(): return best
	return {}

static func fit_both(rays: Dictionary,sizes: Array,text: String) -> Dictionary:
	var table: Array = []
	for s in sizes:
		var row := PackedFloat32Array(); row.resize(RAYS)
		for r in range(RAYS): row[r] = reach(rays,r,s*.55+2)
		table.append(row)
	var h := fit_text(rays,text.length(),sizes,table,false)
	var v := fit_text(rays,text.length(),sizes,table,true) if text.length()>=2 else {}
	if not v.is_empty() and (h.is_empty() or v.size>=h.size*1.25): return v
	return h if not h.is_empty() else v

static func longest(rays: Dictionary,s: float) -> Dictionary:
	var height := minf(s*.55+2,rays.depth*.5); var bi := 0; var best := -1.0
	for i in range(36):
		var length := maxf(0,reach(rays,i,height))+maxf(0,reach(rays,i+36,height)); var tilt := mini(i,36-i)*5
		var score := length*(1-.5*minf(1,tilt/90.0))
		if score>best: best = score; bi = i
	return {"size":s,"i":bi,"j":bi+36,"li":maxf(0,reach(rays,bi,height)),"lj":maxf(0,reach(rays,bi+36,height)),"vertical":false}

static func path_of(rays: Dictionary,f: Dictionary) -> Array:
	var px: float = rays.px; var py: float = rays.py
	var ia: float = f.i*5*PI/180; var ja: float = f.j*5*PI/180
	var ax: float = px+cos(ia)*f.li; var ay: float = py+sin(ia)*f.li; var cx: float = px+cos(ja)*f.lj; var cy: float = py+sin(ja)*f.lj
	var turn := absf(180-posmod(int(f.j-f.i+RAYS),RAYS)*5)
	if turn<3 or f.vertical: return [ax,ay,cx,cy]
	var rc := minf(f.li,f.lj)*.6; var x0 := px+cos(ia)*rc; var y0 := py+sin(ia)*rc; var x1 := px+cos(ja)*rc; var y1 := py+sin(ja)*rc
	var out: Array = [ax,ay]
	for t in range(9):
		var u := t/8.0; out.append((1-u)*(1-u)*x0+2*u*(1-u)*px+u*u*x1); out.append((1-u)*(1-u)*y0+2*u*(1-u)*py+u*u*y1)
	out.append(cx); out.append(cy); return out

static func fit_all(data: Dictionary,f: Dictionary) -> Array:
	var n: int = data.nations.size(); var count := PackedInt32Array(); count.resize(n)
	for owner in data.ownership:
		if owner>=0: count[owner] += 1
	var best := PackedInt32Array(); best.resize(n); best.fill(-1)
	var best_d := PackedFloat32Array(); best_d.resize(n)
	var boxes: Array = []
	for _p in range(n): boxes.append([f.gw,f.gh,-1,-1])
	for i in range(f.owner.size()):
		var o: int = f.owner[i]
		if o<0: continue
		if f.dist[i]>best_d[o]: best_d[o] = f.dist[i]; best[o] = i
		var x := i%int(f.gw); var y := i/int(f.gw)
		boxes[o][0] = mini(boxes[o][0],x); boxes[o][1] = mini(boxes[o][1],y); boxes[o][2] = maxi(boxes[o][2],x); boxes[o][3] = maxi(boxes[o][3],y)
	var out: Array = []
	for p in range(n):
		if count[p]<=0 or best[p]<0: continue
		var text: String = data.nations[p].name; var max_css := clampf(9+1.75*sqrt(count[p]),12,26); var world_per_css := 2048.0/1300; var sizes: Array = []
		var c := max_css
		while c>=5: sizes.append(c*world_per_css); c *= .92
		var rays := cast_rays(f,p,best[p],max_css*world_per_css*14)
		var fit := fit_both(rays,sizes,text)
		if fit.is_empty(): fit = longest(rays,sizes[-1])
		var label := {"polity":p,"text":text,"full":text,"path":path_of(rays,fit),"size":fit.size,"vertical":fit.vertical,"anchor":[rays.px,rays.py],"regions":count[p]}
		var seat: int = data.regions.seat[data.nations[p].seat]; var hole: Array = [data.mesh.x[seat],data.mesh.y[seat]-4,12]
		var start := -1; var bd := 0.0; var b: Array = boxes[p]
		for y in range(b[1],b[3]+1):
			for x in range(b[0],b[2]+1):
				var i: int = y*f.gw+x
				if f.owner[i]!=p or f.dist[i]<=bd: continue
				var d := depth_at(f,i,hole)
				if d>bd: bd = d; start = i
		if start>=0:
			var rays2 := cast_rays(f,p,start,max_css*world_per_css*14,hole); var fit2 := fit_both(rays2,sizes,text)
			if fit2.is_empty(): fit2 = longest(rays2,sizes[-1])
			var path := path_of(rays2,fit2); var dx: float = rays2.px-rays.px; var shift: float = -f.gw*G*floor(dx/(f.gw*G)+.5)
			for i in range(0,path.size(),2): path[i] += shift
			label.alt = {"path":path,"size":fit2.size,"vertical":fit2.vertical}
		out.append(label)
	return out
