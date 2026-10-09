extends RefCounted
## civ-atlas tectonics.ts pickContinents and mergeFragments. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")

static func fragments(mesh: Dictionary,plate: PackedInt32Array,count: int) -> void:
	for _pass in range(2):
		var comp := PackedInt32Array(); comp.resize(mesh.n); comp.fill(-1)
		var sizes: Array[int] = []; var labels: Array[int] = []; var cells: Array = []
		for i in range(mesh.n):
			if comp[i]>=0: continue
			var id := sizes.size(); var pk := plate[i]; var q: Array[int] = [i]; comp[i] = id; var head := 0
			while head<q.size():
				var c := q[head]; head += 1
				for k in range(mesh.adj_start[c],mesh.adj_start[c+1]):
					var j: int = mesh.adj[k]
					if comp[j]<0 and plate[j]==pk: comp[j] = id; q.append(j)
			sizes.append(q.size()); labels.append(pk); cells.append(q)
		var main := PackedInt32Array(); main.resize(count); main.fill(-1)
		for c in range(sizes.size()):
			var pk := labels[c]
			if main[pk]<0 or sizes[c]>sizes[main[pk]]: main[pk] = c
		var targets := PackedInt32Array(); targets.resize(sizes.size()); targets.fill(-1)
		for c in range(sizes.size()):
			if main[labels[c]]==c: continue
			var votes := {}
			for i in cells[c]:
				for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
					var pj := plate[mesh.adj[k]]
					if pj!=labels[c]: votes[pj] = votes.get(pj,0)+1
			var best := -1; var bv := -1
			for pj in votes:
				var v: int = votes[pj]
				if v>bv or (v==bv and pj<best): bv = v; best = pj
			targets[c] = best
		for i in range(mesh.n):
			if targets[comp[i]]>=0: plate[i] = targets[comp[i]]

static func touches(shared: PackedFloat32Array,owner: PackedInt32Array,k: int,c: int,count: int) -> bool:
	for b in range(count):
		if shared[k*count+b]>0 and owner[b]>=0 and owner[b]!=c: return true
	return false

static func polar(k: int,cy: PackedFloat32Array,height: float) -> bool:
	return absf(90-180*cy[k]/height)>58

static func near_cont(shared: PackedFloat32Array,cont: PackedByteArray,k: int,count: int) -> bool:
	for b in range(count):
		if shared[k*count+b]>0 and cont[b]: return true
	return false

static func pick(mesh: Dictionary,geo,plate: PackedInt32Array,count: int,area: PackedFloat32Array,cen: Dictionary,fraction: float,rng,pole: int) -> Dictionary:
	var n: int = mesh.n; var width: float = mesh.width; var height: float = mesh.height
	var shared := PackedFloat32Array(); shared.resize(count*count)
	for i in range(n):
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var b := plate[mesh.adj[k]]
			if b!=plate[i]: shared[plate[i]*count+b] += 1
	var cx: PackedFloat32Array = cen.x; var cy: PackedFloat32Array = cen.y
	var avg := float(n)/count; var target := n*clampf(fraction*1.3,.08,.92); var random: float = rng.next()
	var continents := 2 if random<.12 else 3 if random<.45 else 4 if random<.82 else 5
	continents = maxi(1,mini(continents,mini(int(floor(count/3.0)),int(floor(target/(avg*.7))))))
	var weight: Array[float] = []; var axis_x: Array[float] = []; var axis_y: Array[float] = []
	for c in range(continents): weight.append([1,.62,.44,.33,.25][c]*(.8+.4*rng.next()))
	for _c in range(continents):
		var angle: float = rng.next()*PI; axis_x.append(Maths.round24(cos(angle))); axis_y.append(Maths.round24(sin(angle)))
	var core: Array[int] = []; var owner := PackedInt32Array(); owner.resize(count); owner.fill(-1)
	var cont_area: Array[float] = []; var polar_c := continents-1 if pole!=0 and continents>=2 else -1; var total := 0.0
	var order: Array[int] = []; for k in range(count): order.append(k)
	for i in range(count-1,0,-1):
		var j := int(rng.next()*(i+1)); var tmp := order[i]; order[i] = order[j]; order[j] = tmp
	for c in range(continents):
		var best := -1; var best_score := -INF
		if c==polar_c:
			var at_pole := plate[geo.nearest(width/2.0,0.0 if pole>0 else height,0)]
			if owner[at_pole]<0: best = at_pole
			else:
				for k in order:
					if owner[k]>=0 or area[k]<avg*.6: continue
					var score: float = pole*(90-180*cy[k]/height)
					if score>best_score: best_score = score; best = k
			if best>=0:
				owner[best] = c; core.append(best); cont_area.append(area[best]); total += area[best]
				var cap := PackedFloat32Array(); cap.resize(count); var cap_all := 0
				for i in range(n):
					if pole*geo.latitude(i)>72: cap[plate[i]] += 1; cap_all += 1
				for k in range(count):
					if owner[k]>=0 or cap[k]<.15*cap_all: continue
					owner[k] = c; cont_area[c] += area[k]; total += area[k]
			continue
		for k in order:
			if owner[k]>=0 or polar(k,cy,height) or area[k]<avg*.6: continue
			if c>0 and touches(shared,owner,k,-2,count): continue
			var dmin := width
			for b in range(count):
				if owner[b]>=0: dmin = minf(dmin,geo.point_distance(cx[b],cy[b],cx[k],cy[k]))
			var score: float = area[k]*(.5+rng.next()) if c==0 else dmin*(.7+.6*rng.next())
			if score>best_score: best_score = score; best = k
		if best<0: break
		owner[best] = c; core.append(best); cont_area.append(area[best]); total += area[best]
	if cont_area.is_empty(): owner[order[0]] = 0; core.append(order[0]); cont_area.append(area[order[0]]); total += area[order[0]]
	var sum_weight := 0.0
	for c in range(cont_area.size()): sum_weight += weight[c]
	var goal: Array[float] = []; var closed: Array[bool] = []
	for c in range(cont_area.size()): goal.append(target*weight[c]/sum_weight); closed.append(false)
	var allow_merge := cont_area.size()==1
	while total<target:
		var c := -1; var cs := INF
		for q in range(cont_area.size()):
			if closed[q]: continue
			var s: float = cont_area[q]/goal[q]*(.85+.3*rng.next())
			if s<cs: cs = s; c = q
		if c<0:
			if allow_merge: break
			allow_merge = true; closed.fill(false); continue
		var best := -1; var best_score := -INF
		for k in order:
			if owner[k]>=0: continue
			var sh := 0.0
			for b in range(count):
				if owner[b]==c: sh += shared[k*count+b]
			if sh<=0 or (not allow_merge and touches(shared,owner,k,c,count)): continue
			var score: float = sqrt(sh)*(.5+rng.next())
			var al: float = geo.point_dot(cx[core[c]],cy[core[c]],cx[k],cy[k],axis_x[c],axis_y[c])
			if c==polar_c: score *= .3+1.7*Maths.smoothstep(35,80,pole*(90-180*cy[k]/height))
			else:
				score *= .3+1.4*al*al
				if polar(k,cy,height): score *= .3
			if cont_area[c]+area[k]>goal[c]*1.5: score *= .4
			if score>best_score: best_score = score; best = k
		if best<0: closed[c] = true; continue
		owner[best] = c; cont_area[c] += area[best]; total += area[best]
	var continental := PackedByteArray(); continental.resize(count); var micro := continental.duplicate(); var arch := continental.duplicate()
	for k in range(count): continental[k] = 1 if owner[k]>=0 else 0
	var n_micro := 2+int(rng.next()*3); var got := 0
	for pass_index in range(2):
		for k in order:
			if got>=n_micro: break
			if continental[k] or micro[k] or polar(k,cy,height) or area[k]>avg*1.1 or area[k]<avg*.12: continue
			if pass_index==0 and near_cont(shared,continental,k,count): continue
			micro[k] = 1; got += 1
	var n_arch := int(rng.next()*2.6); got = 0
	for k in order:
		if got>=n_arch: break
		if continental[k] or micro[k] or polar(k,cy,height) or near_cont(shared,continental,k,count): continue
		arch[k] = 1; got += 1
	return {"continental":continental,"micro":micro,"archipelago":arch}
