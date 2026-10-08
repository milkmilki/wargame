extends RefCounted
## Shared-chain rounding and boundary-band labels, adapted from civ-atlas's
## rendering ideas. This is a derived view; it never regenerates provinces.
const VERSION := "atlas_display_v1.1"
const Masks = preload("res://scripts/view/visual_region_geometry.gd")
const Raw = preload("res://scripts/view/river_province_geometry.gd")
static var _cache: Dictionary={}

static func city_at(ids: Image,uv: Vector2) -> int:
	if ids==null or uv.x<0 or uv.y<0 or uv.x>=1 or uv.y>=1: return -1
	return int(round(ids.get_pixelv(Vector2i(uv*Vector2(ids.get_size()))).r))

static func build(state: GameState,height_image: Image,size: Vector2i) -> Dictionary:
	var seed_positions:=PackedVector2Array()
	for city in state.cities: seed_positions.append(city.map_position)
	var signature:=hash([VERSION,state.province_ids,state.province_map_size,size,state.map_aspect_ratio,seed_positions,hash(height_image.get_data()) if height_image!=null else 0])
	if _cache.has(signature): return _cache[signature]
	var started:=Time.get_ticks_msec();var times: Dictionary={}
	var checkpoint:=started
	var grid:=state.province_map_size
	var coarse:=PackedFloat32Array(Array(state.province_ids))
	var ids:=Image.create_from_data(grid.x,grid.y,false,Image.FORMAT_RF,coarse.to_byte_array())
	ids.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
	var labels:=ids.get_data().to_float32_array()
	var original:=labels.duplicate()
	var land:=Masks._build_land_mask(height_image,size)
	var land_bytes:=land.get_data()
	for i in range(labels.size()):
		if land_bytes[i]==0: labels[i]=-1.0;original[i]=-1.0
	times.input=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	var topology:=Raw.topology_from_labels(coarse,grid)
	# Expand collinear runs into cell-length segments before rounding. Otherwise
	# one long corner can move several cells when Chaikin cuts it.
	var segments:=PackedVector2Array();var aa:=PackedInt32Array();var bb:=PackedInt32Array();var sa:=PackedVector2Array();var sb:=PackedVector2Array()
	for i in range(topology.province_a.size()):
		var a: Vector2=topology.province[i*2];var b: Vector2=topology.province[i*2+1]
		var steps:=maxi(1,roundi(((b-a)*Vector2(grid)).length()))
		for j in range(steps):
			segments.append(a.lerp(b,float(j)/steps));segments.append(a.lerp(b,float(j+1)/steps))
			aa.append(topology.province_a[i]);bb.append(topology.province_b[i]);sa.append(topology.province_side_a[i]);sb.append(topology.province_side_b[i])
	var metadata: Dictionary={"kind":"province","province_a":aa,"province_b":bb,"side_a":sa,"side_b":sb}
	var semantic: Array=MapRenderer._build_boundary_semantic_edges(segments,metadata)
	var chains: Array=MapRenderer._trace_boundary_semantic_chains(semantic)
	var result: Dictionary={"province":PackedVector2Array(),"province_a":PackedInt32Array(),"province_b":PackedInt32Array(),"province_side_a":PackedVector2Array(),"province_side_b":PackedVector2Array(),"coast":topology.coast,"coast_province":topology.coast_province,"coast_side":topology.coast_side,"source_size":grid,"source_hash":hash(state.province_ids),"contract_version":3,"render_only":true}
	var curves: Array[Dictionary]=[]
	times.chains=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	var closest:=PackedFloat32Array();closest.resize(labels.size());closest.fill(INF)
	for chain in chains:
		var raw: PackedVector2Array=chain.points
		var info:=MapRenderer._province_chain_side_info(chain.edges[0])
		var simplified:=MapRenderer._simplify_boundary_path(raw,grid,bool(chain.closed),0.35)
		var curve:=_round(simplified,bool(chain.closed))
		# Remove sub-cell zigzags after rounding, while retaining pinned endpoints.
		curve=MapRenderer._simplify_boundary_path(curve,grid,bool(chain.closed),0.18)
		if not _bounded_curve(curve,raw,grid): curve=_round(raw,bool(chain.closed))
		# A seed near a rounded corner pins this shared chain, rather than
		# painting an isolated pixel back into the neighbouring province.
		for city in state.cities:
			var old:=city_at(ids,city.map_position)
			if old not in [info.left_province,info.right_province]: continue
			if _curve_owner(city.map_position,curve,grid,old,info.left_province,info.right_province)!=old:
				curve=raw;break
		_apply_band(labels,original,closest,size,grid,curve,info.left_province,info.right_province,coarse)
		curves.append({"points":curve,"left":info.left_province,"right":info.right_province})
	times.band=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	ids.set_data(size.x,size.y,false,Image.FORMAT_RF,labels.to_byte_array())
	# Clip ink to the final categorical view, including DEM shorelines that
	# cut through a coarse province cell. Fill, picking and ink use one result.
	for item in curves:
		_emit_visible_chain(result,ids,item.points,item.left,item.right)
	times.ink=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	var shores:=_shore_topology(labels,size)
	result.coast=shores.coast;result.coast_province=shores.coast_province;result.coast_side=shores.coast_side
	times.coast=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	var coverage:=PackedByteArray();coverage.resize(labels.size())
	for i in range(labels.size()): coverage[i]=255 if labels[i]>=0 else 0
	var edge:=Image.create(size.x,size.y,false,Image.FORMAT_RF)
	Masks._fill_region_edges(ids,edge)
	var output: Dictionary={"city_id":ids,"land_mask":land,"region_coverage":Image.create_from_data(size.x,size.y,false,Image.FORMAT_L8,coverage),"region_edge":edge,"region_distance":_distance_channel(land_bytes,edge.get_data().to_float32_array(),size),"regions":[],"topology":result,"revision":signature}
	times.channels=Time.get_ticks_msec()-checkpoint
	if OS.get_environment("ATLAS_DISPLAY_PROFILE")=="1": print("ATLAS_DISPLAY_PROFILE ms=",Time.get_ticks_msec()-started," stages=",times)
	# Small bounded cache retains current/history layouts without growing forever.
	if _cache.size()>=4: _cache.erase(_cache.keys()[0])
	_cache[signature]=output
	return output

static func _round(path: PackedVector2Array,closed: bool) -> PackedVector2Array:
	var out:=path.duplicate()
	if closed and out.size()>1 and out[0].is_equal_approx(out[-1]): out.resize(out.size()-1)
	for _pass in range(2):
		var next:=PackedVector2Array()
		if not closed: next.append(out[0])
		var count:=out.size() if closed else out.size()-1
		for i in range(count):
			var a:=out[i];var b:=out[(i+1)%out.size()]
			next.append(a.lerp(b,0.25));next.append(a.lerp(b,0.75))
		if not closed: next.append(out[-1])
		out=next
	if closed: out.append(out[0])
	return out

static func _apply_band(labels: PackedFloat32Array,original: PackedFloat32Array,best: PackedFloat32Array,size: Vector2i,grid: Vector2i,curve: PackedVector2Array,left: int,right: int,coarse: PackedFloat32Array) -> void:
	var ratio:=Vector2(size)/Vector2(grid)
	for i in range(curve.size()-1):
		var a:=curve[i]*Vector2(grid);var b:=curve[i+1]*Vector2(grid);var d:=b-a
		if d.length_squared()<1e-16: continue
		var low:=Vector2i(((a.min(b)-Vector2.ONE*0.5)*ratio).floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
		var high:=Vector2i(((a.max(b)+Vector2.ONE*0.5)*ratio).ceil()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
		var n:=Vector2(-d.y,d.x).normalized()
		var n0:=n;var n1:=n
		if i>0:
			var before:=(curve[i]-curve[i-1])*Vector2(grid);n0=(n+Vector2(-before.y,before.x).normalized()).normalized()
		if i+2<curve.size():
			var after:=(curve[i+2]-curve[i+1])*Vector2(grid);n1=(n+Vector2(-after.y,after.x).normalized()).normalized()
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var index:=y*size.x+x;var old:=int(original[index])
				if old not in [left,right]: continue
				var p:=(Vector2(x,y)+Vector2.ONE*0.5)/ratio
				var t:=(p-a).dot(d)/d.length_squared()
				# Do not extend open chains beyond their pinned junction/coast.
				if (i==0 and t<0) or (i==curve.size()-2 and t>1): continue
				var q:=a+d*clampf(t,0,1);var distance:=p.distance_squared_to(q)
				if distance>0.25 or distance>=best[index]: continue
				var side:=(p-a).dot(n0) if t<=0 else ((p-b).dot(n1) if t>=1 else d.cross(p-a))
				var id:=left if side>=0 else right
				if id!=old and not _near_label(p,id,coarse,grid): continue
				best[index]=distance;labels[index]=id

static func _near_label(p: Vector2,id: int,coarse: PackedFloat32Array,grid: Vector2i) -> bool:
	var cell:=Vector2i(p.floor())
	for y in range(maxi(0,cell.y-1),mini(grid.y,cell.y+2)):
		for x in range(maxi(0,cell.x-1),mini(grid.x,cell.x+2)):
			if int(coarse[y*grid.x+x])!=id: continue
			var q:=p.clamp(Vector2(x,y),Vector2(x+1,y+1))
			if p.distance_squared_to(q)<=0.2500001: return true
	return false

static func _curve_owner(uv: Vector2,curve: PackedVector2Array,grid: Vector2i,old: int,left: int,right: int) -> int:
	var p:=uv*Vector2(grid);var nearest:=0.25;var owner:=old
	for i in range(curve.size()-1):
		var a:=curve[i]*Vector2(grid);var d:=(curve[i+1]-curve[i])*Vector2(grid)
		if d.length_squared()<1e-16: continue
		var t:=(p-a).dot(d)/d.length_squared()
		if (i==0 and t<0) or (i==curve.size()-2 and t>1): continue
		var q:=a+d*clampf(t,0,1);var distance:=p.distance_squared_to(q)
		if distance<nearest:
			nearest=distance;owner=left if d.cross(p-a)>=0 else right
	return owner

static func _emit_visible_chain(result: Dictionary,ids: Image,curve: PackedVector2Array,left: int,right: int) -> void:
	var epsilon:=1.0/maxi(ids.get_width(),ids.get_height())
	for i in range(curve.size()-1):
		var a:=curve[i];var b:=curve[i+1];var d:=b-a
		if d.length_squared()<1e-16: continue
		var normal:=Vector2(-d.y,d.x).normalized()
		var count:=maxi(1,ceili(d.length()/epsilon));var run:=-1
		for j in range(count+1):
			var valid:=false
			if j<count:
				var mid:=a.lerp(b,(j+0.5)/count)
				valid=city_at(ids,mid+normal*epsilon)==left and city_at(ids,mid-normal*epsilon)==right
			if valid and run<0: run=j
			if not valid and run>=0:
				result.province.append(a.lerp(b,float(run)/count));result.province.append(a.lerp(b,float(j)/count))
				result.province_a.append(left);result.province_b.append(right)
				result.province_side_a.append(normal);result.province_side_b.append(-normal)
				run=-1

static func _shore_topology(labels: PackedFloat32Array,size: Vector2i) -> Dictionary:
	var coast:=PackedVector2Array();var owners:=PackedInt32Array();var sides:=PackedVector2Array()
	for axis in range(2):
		var lines:=size.y if axis==0 else size.x;var length:=size.x if axis==0 else size.y
		for line in range(lines+1):
			var old:=-1;var start:=0
			for column in range(length+1):
				var key:=-1
				if column<length:
					var p:=line*size.x+column if axis==0 else column*size.x+line
					var a:=labels[p-(size.x if axis==0 else 1)] if line>0 else -1.0
					var b:=labels[p] if line<lines else -1.0
					if a>=0 and b<0: key=int(a)*2
					elif b>=0 and a<0: key=int(b)*2+1
				if key==old: continue
				if old>=0:
					var a:=Vector2(start,line) if axis==0 else Vector2(line,start)
					var b:=Vector2(column,line) if axis==0 else Vector2(line,column)
					coast.append(a/Vector2(size));coast.append(b/Vector2(size));owners.append(old/2)
					sides.append((Vector2.UP if axis==0 else Vector2.LEFT) if old%2==0 else (Vector2.DOWN if axis==0 else Vector2.RIGHT))
				old=key;start=column
	return {"coast":coast,"coast_province":owners,"coast_side":sides}

static func _distance_channel(land: PackedByteArray,edge: PackedFloat32Array,size: Vector2i) -> Image:
	var distances:=PackedInt32Array();distances.resize(land.size())
	for i in range(land.size()): distances[i]=-1 if land[i]==0 else (0 if edge[i]>0.5 else 1000000000)
	for y in range(size.y):
		for x in range(size.x):
			var i:=y*size.x+x;var best:=distances[i]
			if best<0: continue
			if x>0 and distances[i-1]>=0: best=mini(best,distances[i-1]+1)
			if y>0 and distances[i-size.x]>=0: best=mini(best,distances[i-size.x]+1)
			distances[i]=best
	for y in range(size.y-1,-1,-1):
		for x in range(size.x-1,-1,-1):
			var i:=y*size.x+x;var best:=distances[i]
			if best<0: continue
			if x+1<size.x and distances[i+1]>=0: best=mini(best,distances[i+1]+1)
			if y+1<size.y and distances[i+size.x]>=0: best=mini(best,distances[i+size.x]+1)
			distances[i]=best
	var values:=PackedFloat32Array();values.resize(land.size())
	for i in range(values.size()): values[i]=-1.0 if distances[i]<0 else clampf(float(distances[i])/Masks.DISTANCE_RADIUS_PX,0,1)
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RF,values.to_byte_array())

static func _bounded_curve(curve: PackedVector2Array,raw: PackedVector2Array,grid: Vector2i) -> bool:
	for i in range(curve.size()-1):
		for uv in [curve[i],curve[i].lerp(curve[i+1],0.5),curve[i+1]]:
			var p: Vector2=uv*Vector2(grid);var best:=INF
			for j in range(raw.size()-1):
				var a:=raw[j]*Vector2(grid);var d:=(raw[j+1]-raw[j])*Vector2(grid)
				if d.length_squared()<1e-16: continue
				best=minf(best,p.distance_squared_to(a+d*clampf((p-a).dot(d)/d.length_squared(),0,1)))
			if best>0.2500001: return false
	return true
