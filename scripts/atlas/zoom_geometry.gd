extends RefCounted
## Original zoomGrid.ts segIndex/nearestSide, native CPU query + GPU-packed same index.
## AGPL-3.0-only. Fill and clicks consult the same smoothed boundary segments.
const KEEP := -32768

static func build(lines: Array,band: float = 4.,w: float = 2048.,h: float = 1024.) -> Dictionary:
	var index := {"ox":-band,"oy":-band,"cs":maxf(band,sqrt((w+2*band)*(h+2*band)/1048576)),"band":band}
	index.nx = maxi(1,ceili((w+2*band)/index.cs)); index.ny = maxi(1,ceili((h+2*band)/index.cs))
	for key in ["ax","ay","dx","dy","inv","n0x","n0y","n1x","n1y","ends"]: index[key] = PackedFloat64Array()
	for key in ["left","right","copy"]: index[key] = PackedInt32Array()
	var copies := 0
	for line in lines:
		var p: Variant = line.pts; var count: int = p.size()/2; var segs := count-1
		if segs<1: continue
		var lo := INF; var hi := -INF; var ylo := INF; var yhi := -INF
		for i in range(count): lo = minf(lo,p[i*2]); hi = maxf(hi,p[i*2]); ylo = minf(ylo,p[i*2+1]); yhi = maxf(yhi,p[i*2+1])
		if yhi< -band or ylo>h+band: continue
		var nx := PackedFloat64Array(); nx.resize(segs); var ny := nx.duplicate()
		for i in range(segs):
			var dx: float = p[i*2+2]-p[i*2]; var dy: float = p[i*2+3]-p[i*2+1]; var length := sqrt(dx*dx+dy*dy)
			if length==0: length = 1
			nx[i] = -dy/length; ny[i] = dx/length
		for k in range(ceili((-band-hi)/w),floori((w+band-lo)/w)+1):
			var shift := k*w
			for i in range(segs):
				var prev := i-1 if i>0 else segs-1 if line.get("closed",false) else i
				var next := i+1 if i+1<segs else 0 if line.get("closed",false) else i
				var dx: float = p[i*2+2]-p[i*2]; var dy: float = p[i*2+3]-p[i*2+1]; var length2 := dx*dx+dy*dy
				index.ax.append(p[i*2]+shift); index.ay.append(p[i*2+1]); index.dx.append(dx); index.dy.append(dy); index.inv.append(1/length2 if length2>0 else 0.)
				index.n0x.append(nx[prev]+nx[i]); index.n0y.append(ny[prev]+ny[i]); index.n1x.append(nx[i]+nx[next]); index.n1y.append(ny[i]+ny[next])
				index.left.append(int(line.left)); index.right.append(int(line.right)); index.copy.append(copies)
			var back := mini(segs,4)
			for end in [0,1]:
				if not line.get("end0" if end==0 else "end1",false): index.ends.append_array(PackedFloat64Array([NAN,NAN,NAN,NAN])); continue
				var at := 0 if end==0 else segs; var to := back if end==0 else segs-back
				index.ends.append_array(PackedFloat64Array([p[at*2]+shift,p[at*2+1],p[at*2]-p[to*2],p[at*2+1]-p[to*2+1]]))
			copies += 1
	var counts := PackedInt32Array(); counts.resize(index.nx*index.ny+1)
	for i in range(index.ax.size()):
		var b := span(index,i)
		for y in range(b[1],b[3]+1):
			for x in range(b[0],b[2]+1): counts[y*int(index.nx)+x+1] += 1
	for i in range(1,counts.size()): counts[i] += counts[i-1]
	var list := PackedInt32Array(); list.resize(counts[-1]); var fill := counts.duplicate()
	for i in range(index.ax.size()):
		var b := span(index,i)
		for y in range(b[1],b[3]+1):
			for x in range(b[0],b[2]+1):
				var cell: int = y*index.nx+x; list[fill[cell]] = i; fill[cell] += 1
	index.start = counts; index.list = list
	return index

static func span(index: Dictionary,i: int) -> Array:
	return [maxi(0,floori((minf(index.ax[i],index.ax[i]+index.dx[i])-index.band-index.ox)/index.cs)),maxi(0,floori((minf(index.ay[i],index.ay[i]+index.dy[i])-index.band-index.oy)/index.cs)),mini(index.nx-1,floori((maxf(index.ax[i],index.ax[i]+index.dx[i])+index.band-index.ox)/index.cs)),mini(index.ny-1,floori((maxf(index.ay[i],index.ay[i]+index.dy[i])+index.band-index.oy)/index.cs))]

static func nearest(index: Dictionary,px: float,py: float) -> Dictionary:
	var cx := floori((px-index.ox)/index.cs); var cy := floori((py-index.oy)/index.cs)
	if cx<0 or cy<0 or cx>=index.nx or cy>=index.ny: return {"distance":INF,"side":KEEP}
	var cell: int = cy*index.nx+cx; var best: float = index.band*index.band; var hit := -1; var side := 0.0
	for q in range(index.start[cell],index.start[cell+1]):
		var i: int = index.list[q]; var rx: float = px-index.ax[i]; var ry: float = py-index.ay[i]
		var t: float = (rx*index.dx[i]+ry*index.dy[i])*index.inv[i]; var qx: float; var qy: float; var sd: float
		if t<=0: qx = rx; qy = ry; sd = rx*index.n0x[i]+ry*index.n0y[i]
		elif t>=1: qx = rx-index.dx[i]; qy = ry-index.dy[i]; sd = qx*index.n1x[i]+qy*index.n1y[i]
		else: qx = rx-index.dx[i]*t; qy = ry-index.dy[i]*t; sd = index.dx[i]*ry-index.dy[i]*rx
		var d2 := qx*qx+qy*qy
		if d2>best: continue
		best = d2; hit = i; side = sd
	if hit<0: return {"distance":INF,"side":KEEP}
	var owner: int = index.left[hit] if side>0 else index.right[hit]
	var o: int = index.copy[hit]*8
	for k in [0,4]:
		var ex: float = index.ends[o+k]
		if is_nan(ex): continue
		var vx := px-ex; var vy: float = py-index.ends[o+k+1]
		if vx*index.ends[o+k+2]+vy*index.ends[o+k+3]>0 and vx*vx+vy*vy<=index.band*index.band: owner = KEEP; break
	return {"distance":sqrt(best),"side":owner}

static func float_image(values: PackedFloat32Array,channels: int,w: int = 1024) -> ImageTexture:
	var h := maxi(1,ceili(values.size()/float(channels*w))); values.resize(w*h*channels)
	return ImageTexture.create_from_image(Image.create_from_data(w,h,false,Image.FORMAT_RF if channels==1 else Image.FORMAT_RGBAF,values.to_byte_array()))

static func textures(index: Dictionary) -> Dictionary:
	var grid := PackedFloat32Array(); grid.resize(index.nx*index.ny*4)
	for i in range(index.nx*index.ny): grid[i*4] = index.start[i]; grid[i*4+1] = index.start[i+1]
	var segments0 := PackedFloat32Array(); var segments1 := PackedFloat32Array(); var segments2 := PackedFloat32Array()
	for i in range(index.ax.size()):
		segments0.append_array(PackedFloat32Array([index.ax[i],index.ay[i],index.dx[i],index.dy[i]]))
		segments1.append_array(PackedFloat32Array([index.n0x[i],index.n0y[i],index.n1x[i],index.n1y[i]]))
		segments2.append_array(PackedFloat32Array([index.left[i],index.right[i],index.copy[i],index.inv[i]]))
	var ends := PackedFloat32Array(Array(index.ends))
	for i in range(ends.size()):
		if is_nan(ends[i]): ends[i] = -1e20
	return {"segment_grid":float_image(grid,4,index.nx),"segment_list":float_image(PackedFloat32Array(Array(index.list)),1),"segments0":float_image(segments0,4),"segments1":float_image(segments1,4),"segments2":float_image(segments2,4),"segment_ends":float_image(ends,4)}
