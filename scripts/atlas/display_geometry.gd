extends RefCounted
## civ-atlas borders.ts bandLabels and routes.ts display-only curve utilities.
## AGPL-3.0-only. Logical provinces remain immutable.

static func points(flat) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(0,flat.size(),2): result.append(Vector2(flat[i],flat[i+1]))
	return result

static func chaikin(path: PackedVector2Array,closed: bool,rounds: int) -> PackedVector2Array:
	var current := path.duplicate()
	for _round in range(rounds):
		if current.size() < 3: break
		var next := PackedVector2Array()
		if not closed: next.append(current[0])
		for i in range(current.size()-1):
			next.append(Vector2(float(current[i].x)*.75+float(current[i+1].x)*.25,float(current[i].y)*.75+float(current[i+1].y)*.25))
			next.append(Vector2(float(current[i].x)*.25+float(current[i+1].x)*.75,float(current[i].y)*.25+float(current[i+1].y)*.75))
		if not closed: next.append(current[-1])
		else:
			next.append(next[0]+Vector2(current[-1].x-current[0].x,0))
		current = next
	return current

static func band_labels(labels: PackedInt32Array,w: int,h: int,lines: Array,weak: PackedByteArray) -> void:
	var best := PackedFloat32Array(); best.resize(labels.size()); best.fill(INF)
	var changed := PackedInt32Array(); changed.resize(labels.size()); changed.fill(-32768)
	for line in lines:
		var p := PackedFloat32Array(line.pts); var count := p.size()/2; var segs := count-1
		if segs < 1: continue
		var nx := PackedFloat64Array(); nx.resize(segs); var ny := PackedFloat64Array(); ny.resize(segs)
		var near := PackedByteArray(); near.resize(segs)
		for i in range(segs):
			var dx := p[2*i+2]-p[2*i]; var dy := p[2*i+3]-p[2*i+1]; var length := sqrt(dx*dx+dy*dy)
			if length == 0.0: length = 1.0
			nx[i] = -dy/length; ny[i] = dx/length
		var closed: bool = line.get("closed",false)
		var end0: bool = line.get("end0",false); var end1: bool = line.get("end1",false)
		if not closed:
			for ending in [0,1]:
				if (ending == 0 and not end0) or (ending == 1 and not end1): continue
				var d := 0.0
				for j in range(segs):
					var i := j if ending == 0 else segs-1-j
					if d > 24.0: break
					near[i] = 1
					var dx := p[2*i+2]-p[2*i]; var dy := p[2*i+3]-p[2*i+1]; d += sqrt(dx*dx+dy*dy)
		var back := mini(segs,4)
		var d0x := p[0]-p[2*back]; var d0y := p[1]-p[2*back+1]
		var d1x := p[2*segs]-p[2*(segs-back)]; var d1y := p[2*segs+1]-p[2*(segs-back)+1]
		for shift in [0.0,-float(w),float(w)]:
			for i in range(segs):
				var reach := 8.0 if near[i] != 0 else 4.0
				var ax: float = p[2*i]+shift; var ay := p[2*i+1]; var bx: float = p[2*i+2]+shift; var by := p[2*i+3]
				var dx := bx-ax; var dy := by-ay; var length2 := dx*dx+dy*dy
				var inv := 1.0/length2 if length2 > 0.0 else 0.0
				var prev := i-1 if i > 0 else (segs-1 if closed else i)
				var next := i+1 if i+1 < segs else (0 if closed else i)
				var n0x := nx[prev]+nx[i]; var n0y := ny[prev]+ny[i]
				var n1x := nx[i]+nx[next]; var n1y := ny[i]+ny[next]
				var x0 := maxi(0,ceili(minf(ax,bx)-reach-0.5)); var x1 := mini(w-1,floori(maxf(ax,bx)+reach-0.5))
				var y0 := maxi(0,ceili(minf(ay,by)-reach-0.5)); var y1 := mini(h-1,floori(maxf(ay,by)+reach-0.5))
				for y in range(y0,y1+1):
					var py := y+0.5
					for x in range(x0,x1+1):
						var k := y*w+x
						if labels[k] == -2: continue
						var px := x+0.5; var t := ((px-ax)*dx+(py-ay)*dy)*inv
						var qx: float; var qy: float; var side: float
						if t <= 0.0: qx = ax-px; qy = ay-py; side = (px-ax)*n0x+(py-ay)*n0y
						elif t >= 1.0: qx = bx-px; qy = by-py; side = (px-bx)*n1x+(py-by)*n1y
						else: qx = ax+dx*t-px; qy = ay+dy*t-py; side = dx*(py-ay)-dy*(px-ax)
						var d2 := qx*qx+qy*qy
						var lim := 64.0 if near[i] != 0 and weak[k] != 0 else 16.0
						if d2 > lim or d2 >= best[k]: continue
						best[k] = d2
						var ex0: float = px-(p[0]+shift); var ey0 := py-p[1]
						var ex1: float = px-(p[2*segs]+shift); var ey1 := py-p[2*segs+1]
						var beyond := (end0 and ex0*d0x+ey0*d0y > 0.0 and ex0*ex0+ey0*ey0 <= lim) or (end1 and ex1*d1x+ey1*d1y > 0.0 and ex1*ex1+ey1*ey1 <= lim)
						changed[k] = -32768 if beyond else (int(line.left) if side > 0.0 else int(line.right))
	for i in range(labels.size()):
		if changed[i] != -32768: labels[i] = changed[i]

static func dashed_segments(path: PackedVector2Array,dash: float,gap: float) -> PackedVector2Array:
	var result := PackedVector2Array(); var phase := 0.0
	for i in range(path.size()-1):
		var a := path[i]; var b := path[i+1]; var length := a.distance_to(b); var t := 0.0
		while t < length-0.000001:
			var in_dash := phase < dash
			var room := (dash if in_dash else dash+gap)-phase
			var step := minf(room,length-t)
			if step < 0.000001: phase = dash if in_dash else 0.0; continue
			if in_dash: result.append(a.lerp(b,t/length)); result.append(a.lerp(b,(t+step)/length))
			t += step; phase += step
			if phase >= dash+gap-0.000001: phase = 0.0
	return result
