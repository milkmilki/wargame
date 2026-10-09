extends RefCounted
## Native port of Delaunator 5.1.0, Copyright (c) 2026 Mapbox, ISC license.
## Advancing hull, halfedges, edge legalization and original quicksort.
var coords := PackedFloat64Array()
var triangles := PackedInt32Array()
var halfedges := PackedInt32Array()
var hull := PackedInt32Array()
var hp := PackedInt32Array()
var hn := PackedInt32Array()
var ht := PackedInt32Array()
var hh := PackedInt32Array()
var ids := PackedInt32Array()
var distances := PackedFloat64Array()
var hash_size := 0
var triangle_length := 0
var hull_start := 0
var cx := 0.0
var cy := 0.0

func build(points: PackedFloat64Array) -> void:
	coords = points
	var n := coords.size() >> 1
	triangles.resize(maxi(2*n-5,0)*3); halfedges.resize(triangles.size())
	hp.resize(n); hn.resize(n); ht.resize(n); ids.resize(n); distances.resize(n)
	hash_size = maxi(1,ceili(sqrt(float(n)))); hh.resize(hash_size); hh.fill(-1)
	var min_x := INF; var min_y := INF; var max_x := -INF; var max_y := -INF
	for i in range(n):
		min_x = minf(min_x,coords[2*i]); min_y = minf(min_y,coords[2*i+1])
		max_x = maxf(max_x,coords[2*i]); max_y = maxf(max_y,coords[2*i+1]); ids[i] = i
	var i0 := 0; var i1 := 0; var i2 := 0; var best := INF
	for i in range(n):
		var d := dist((min_x+max_x)/2.0,(min_y+max_y)/2.0,coords[2*i],coords[2*i+1])
		if d < best: best = d; i0 = i
	best = INF
	for i in range(n):
		if i == i0: continue
		var d := dist(coords[2*i0],coords[2*i0+1],coords[2*i],coords[2*i+1])
		if d > 0.0 and d < best: best = d; i1 = i
	best = INF
	for i in range(n):
		if i == i0 or i == i1: continue
		var r := circumradius(coords[2*i0],coords[2*i0+1],coords[2*i1],coords[2*i1+1],coords[2*i],coords[2*i+1])
		if r < best: best = r; i2 = i
	if best == INF:
		for i in range(n):
			distances[i] = coords[2*i]-coords[0]
			if distances[i] == 0.0: distances[i] = coords[2*i+1]-coords[1]
		quicksort(0,n-1)
		var before := -INF
		for i in ids:
			if distances[i] > before: hull.append(i); before = distances[i]
		triangles.clear(); halfedges.clear(); return
	if orient(coords[2*i0],coords[2*i0+1],coords[2*i1],coords[2*i1+1],coords[2*i2],coords[2*i2+1]) < 0.0:
		var swap_id := i1; i1 = i2; i2 = swap_id
	var center := circumcenter(coords[2*i0],coords[2*i0+1],coords[2*i1],coords[2*i1+1],coords[2*i2],coords[2*i2+1])
	cx = center[0]; cy = center[1]
	for i in range(n): distances[i] = dist(coords[2*i],coords[2*i+1],cx,cy)
	quicksort(0,n-1)
	hull_start = i0
	hn[i0] = i1; hp[i2] = i1; hn[i1] = i2; hp[i0] = i2; hn[i2] = i0; hp[i1] = i0
	ht[i0] = 0; ht[i1] = 1; ht[i2] = 2
	for i in [i0,i1,i2]: hh[hash_key(coords[2*i],coords[2*i+1])] = i
	add_triangle(i0,i1,i2,-1,-1,-1)
	var previous_x := 0.0; var previous_y := 0.0; var hull_size := 3
	for k in range(n):
		var i := ids[k]; var x := coords[2*i]; var y := coords[2*i+1]
		if k > 0 and absf(x-previous_x) <= 2.220446049250313e-16 and absf(y-previous_y) <= 2.220446049250313e-16: continue
		previous_x = x; previous_y = y
		if i == i0 or i == i1 or i == i2: continue
		var start := 0; var key := hash_key(x,y)
		for j in range(hash_size):
			start = hh[(key+j)%hash_size]
			if start != -1 and start != hn[start]: break
		start = hp[start]
		var e := start
		while true:
			var q := hn[e]
			if orient(x,y,coords[2*e],coords[2*e+1],coords[2*q],coords[2*q+1]) < 0.0: break
			e = q
			if e == start: e = -1; break
		if e == -1: continue
		var t := add_triangle(e,i,hn[e],-1,-1,ht[e])
		ht[i] = legalize(t+2); ht[e] = t; hull_size += 1
		var next := hn[e]
		while true:
			var q := hn[next]
			if orient(x,y,coords[2*next],coords[2*next+1],coords[2*q],coords[2*q+1]) >= 0.0: break
			t = add_triangle(next,i,q,ht[i],-1,ht[next]); ht[i] = legalize(t+2)
			hn[next] = next; hull_size -= 1; next = q
		if e == start:
			while true:
				var q := hp[e]
				if orient(x,y,coords[2*q],coords[2*q+1],coords[2*e],coords[2*e+1]) >= 0.0: break
				t = add_triangle(q,i,e,-1,ht[e],ht[q]); legalize(t+2); ht[q] = t
				hn[e] = e; hull_size -= 1; e = q
		hull_start = e; hp[i] = e; hn[e] = i; hp[next] = i; hn[i] = next
		hh[hash_key(x,y)] = i; hh[hash_key(coords[2*e],coords[2*e+1])] = e
	hull.resize(hull_size)
	var e := hull_start
	for i in range(hull_size): hull[i] = e; e = hn[e]
	triangles.resize(triangle_length); halfedges.resize(triangle_length)

func hash_key(x: float,y: float) -> int:
	var dx := x-cx; var dy := y-cy; var denom := absf(dx)+absf(dy)
	var p := dx/denom if denom > 0.0 else 0.0
	return floori(((3.0-p) if dy > 0.0 else (1.0+p))/4.0*hash_size)%hash_size

func add_triangle(a: int,b: int,c: int,ab: int,bc: int,ca: int) -> int:
	var t := triangle_length
	triangles[t] = a; triangles[t+1] = b; triangles[t+2] = c
	link(t,ab); link(t+1,bc); link(t+2,ca); triangle_length += 3
	return t

func link(a: int,b: int) -> void:
	halfedges[a] = b
	if b != -1: halfedges[b] = a

func legalize(initial: int) -> int:
	var a := initial; var ar := 0; var stack := PackedInt32Array()
	while true:
		var b := halfedges[a]; var a0 := a-a%3; ar = a0+(a+2)%3
		if b == -1:
			if stack.is_empty(): break
			a = stack[-1]; stack.resize(stack.size()-1); continue
		var b0 := b-b%3; var al := a0+(a+1)%3; var bl := b0+(b+2)%3
		var p0 := triangles[ar]; var pr := triangles[a]; var pl := triangles[al]; var p1 := triangles[bl]
		if in_circle(coords[2*p0],coords[2*p0+1],coords[2*pr],coords[2*pr+1],coords[2*pl],coords[2*pl+1],coords[2*p1],coords[2*p1+1]):
			triangles[a] = p1; triangles[b] = p0
			var hbl := halfedges[bl]
			if hbl == -1:
				var e := hull_start
				while true:
					if ht[e] == bl: ht[e] = a; break
					e = hp[e]
					if e == hull_start: break
			link(a,hbl); link(b,halfedges[ar]); link(ar,bl)
			if stack.size() < 512: stack.append(b0+(b+1)%3)
		else:
			if stack.is_empty(): break
			a = stack[-1]; stack.resize(stack.size()-1)
	return ar

func quicksort(left: int,right: int) -> void:
	if right-left <= 20:
		for i in range(left+1,right+1):
			var temp := ids[i]; var d := distances[temp]; var j := i-1
			while j >= left and distances[ids[j]] > d: ids[j+1] = ids[j]; j -= 1
			ids[j+1] = temp
	else:
		var i := left+1; var j := right
		swap((left+right)>>1,i)
		if distances[ids[left]] > distances[ids[right]]: swap(left,right)
		if distances[ids[i]] > distances[ids[right]]: swap(i,right)
		if distances[ids[left]] > distances[ids[i]]: swap(left,i)
		var temp := ids[i]; var d := distances[temp]
		while true:
			i += 1
			while distances[ids[i]] < d: i += 1
			j -= 1
			while distances[ids[j]] > d: j -= 1
			if j < i: break
			swap(i,j)
		ids[left+1] = ids[j]; ids[j] = temp
		if right-i+1 >= j-left: quicksort(i,right); quicksort(left,j-1)
		else: quicksort(left,j-1); quicksort(i,right)

func swap(i: int,j: int) -> void:
	var temp := ids[i]; ids[i] = ids[j]; ids[j] = temp

static func dist(ax: float,ay: float,bx: float,by: float) -> float:
	return (ax-bx)*(ax-bx)+(ay-by)*(ay-by)

static func circumradius(ax: float,ay: float,bx: float,by: float,cx_: float,cy_: float) -> float:
	var dx := bx-ax; var dy := by-ay; var ex := cx_-ax; var ey := cy_-ay
	var denom := dx*ey-dy*ex
	if denom == 0.0: return INF
	var d := 0.5/denom; var bl := dx*dx+dy*dy; var cl := ex*ex+ey*ey
	var x := (ey*bl-dy*cl)*d; var y := (dx*cl-ex*bl)*d
	return x*x+y*y

static func circumcenter(ax: float,ay: float,bx: float,by: float,cx_: float,cy_: float) -> PackedFloat64Array:
	var dx := bx-ax; var dy := by-ay; var ex := cx_-ax; var ey := cy_-ay
	var d := 0.5/(dx*ey-dy*ex); var bl := dx*dx+dy*dy; var cl := ex*ex+ey*ey
	return PackedFloat64Array([ax+(ey*bl-dy*cl)*d,ay+(dx*cl-ex*bl)*d])

static func in_circle(ax: float,ay: float,bx: float,by: float,cx_: float,cy_: float,px: float,py: float) -> bool:
	var dx := ax-px; var dy := ay-py; var ex := bx-px; var ey := by-py; var fx := cx_-px; var fy := cy_-py
	var ap := dx*dx+dy*dy; var bp := ex*ex+ey*ey; var cp := fx*fx+fy*fy
	return dx*(ey*cp-bp*fy)-dy*(ex*cp-bp*fx)+ap*(ex*fy-ey*fx) < 0.0

static func orient(ax: float,ay: float,bx: float,by: float,cx_: float,cy_: float) -> float:
	var l := (ay-cy_)*(bx-cx_); var r := (ax-cx_)*(by-cy_); var determinant := l-r
	if absf(determinant) >= 3.3306690738754716e-16*absf(l+r): return determinant
	# Exact expansion arithmetic for cancellation and near-collinear inputs.
	var expansion := PackedFloat64Array()
	var ady := difference(ay,cy_); var bdx := difference(bx,cx_)
	var adx := difference(ax,cx_); var bdy := difference(by,cy_)
	for a in ady:
		for b in bdx:
			for term in product(a,b): expansion = grow(expansion,term)
	for a in adx:
		for b in bdy:
			for term in product(a,b): expansion = grow(expansion,-term)
	return expansion[-1] if not expansion.is_empty() else 0.0

static func difference(a: float,b: float) -> PackedFloat64Array:
	var x := a-b; var bv := a-x; var av := x+bv
	return PackedFloat64Array([(a-av)+(bv-b),x])

static func product(a: float,b: float) -> PackedFloat64Array:
	var x := a*b; var ca := 134217729.0*a; var cb := 134217729.0*b
	var ah := ca-(ca-a); var al := a-ah; var bh := cb-(cb-b); var bl := b-bh
	return PackedFloat64Array([al*bl-(((x-ah*bh)-al*bh)-ah*bl),x])

static func grow(e: PackedFloat64Array,b: float) -> PackedFloat64Array:
	var result := PackedFloat64Array(); var q := b
	for a in e:
		var sum_ := q+a; var bv := sum_-q; var av := sum_-bv
		var error := (q-av)+(a-bv)
		if error != 0.0: result.append(error)
		q = sum_
	if q != 0.0 or result.is_empty(): result.append(q)
	return result
