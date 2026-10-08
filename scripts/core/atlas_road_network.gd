extends RefCounted
## Independent adaptation of civ-atlas 103afd3's cost routing / Urquhart / reuse
## ideas. Simulation remains a city graph: no edge can skip a third province.
const VERSION := "atlas_city_graph_v1.2"
const OFFSETS := [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]
const PixelRoute = preload("res://scripts/core/province_pixel_route.gd")

static func supercover(from: Vector2,to: Vector2,size: Vector2i,corner_contacts: bool=true) -> Array[Vector2i]:
	var a:=from*Vector2(size);var b:=to*Vector2(size);var direction:=b-a
	var initial:=Vector2i(a.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var terminal:=Vector2i(b.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var result: Array[Vector2i]=[initial]
	# Endpoints belong to their floor-selected cells. Trace the open interior
	# symmetrically, so a corner endpoint cannot acquire an outward sea cell.
	if direction.length_squared()>1e-18:
		var epsilon:=minf(direction.length()*0.01,maxi(size.x,size.y)*0.0000005)
		var inward:=direction.normalized()*epsilon;a+=inward;b-=inward
	var p:=Vector2i(a.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var end:=Vector2i(b.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	if p!=initial: result.append(p)
	var d:=b-a;var step:=Vector2i(int(signf(d.x)),int(signf(d.y)))
	var tx:=((p.x+(1 if step.x>0 else 0))-a.x)/d.x if step.x!=0 else INF
	var ty:=((p.y+(1 if step.y>0 else 0))-a.y)/d.y if step.y!=0 else INF
	var dx:=absf(1.0/d.x) if step.x!=0 else INF;var dy:=absf(1.0/d.y) if step.y!=0 else INF
	var limit:=size.x+size.y+2
	while p!=end and limit>0:
		limit-=1
		if minf(tx,ty)>1.000000001: break
		if absf(tx-ty)<0.0000001:
			if corner_contacts:
				for q in [p+Vector2i(step.x,0),p+Vector2i(0,step.y)]:
					if Rect2i(Vector2i.ZERO,size).has_point(q): result.append(q)
			p+=step;tx+=dx;ty+=dy
		elif tx<ty: p.x+=step.x;tx+=dx
		else: p.y+=step.y;ty+=dy
		if not Rect2i(Vector2i.ZERO,size).has_point(p): break
		result.append(p)
	if result[-1]!=terminal: result.append(terminal)
	return result

static func _register_reuse(path: PackedVector2Array,grid: Vector2i,reused: Dictionary) -> void:
	# Only the centreline's real grid steps receive a discount. Corner-touch
	# cells used by the safety supercover are not themselves road segments.
	for i in range(path.size()-1):
		var cells:=supercover(path[i],path[i+1],grid,false)
		for j in range(cells.size()-1):
			var a:=cells[j].y*grid.x+cells[j].x;var b:=cells[j+1].y*grid.x+cells[j+1].x
			if a!=b: reused[mini(a,b)*grid.x*grid.y+maxi(a,b)]=true

static func _safe_segment(from: Vector2,to: Vector2,options: Dictionary) -> bool:
	var source: Image=options.image
	if not options.has("source_data"):
		var image:=source
		if image.get_format()!=Image.FORMAT_RGBA8: image=image.duplicate();image.convert(Image.FORMAT_RGBA8)
		options["source_data"]=image.get_data()
	var data: PackedByteArray=options.source_data
	var size:=source.get_size();var low:=1.0;var high:=0.0
	var maximum:=float(options.get("maximum_height",1.0))
	for p in supercover(from,to,size):
		var alpha:=data[(p.y*size.x+p.x)*4+3]
		if alpha<=128: return false
		if maximum<1.0:
			var h:=(alpha-128)/127.0;low=minf(low,h);high=maxf(high,h)
			if high-low>maximum+0.000001: return false
	return true

static func _pair_segment(ids: PackedInt32Array,size: Vector2i,from: Vector2,to: Vector2,a: int,b: int) -> bool:
	for p in supercover(from,to,size):
		if ids[p.y*size.x+p.x] not in [a,b]: return false
	return true

static func path_cost(path: PackedVector2Array,source: Image,context: Dictionary,reused: Dictionary) -> float:
	var cost:=0.0
	var grid: Vector2i=context.grid
	for i in range(path.size()-1):
		var p:=Vector2i(path[i]*Vector2(source.get_size())).clamp(Vector2i.ZERO,source.get_size()-Vector2i.ONE)
		var q:=Vector2i(path[i+1]*Vector2(source.get_size())).clamp(Vector2i.ZERO,source.get_size()-Vector2i.ONE)
		var delta:=path[i+1]-path[i];delta.x*=context.aspect
		var cell:=Vector2i(path[i+1]*Vector2(grid)).clamp(Vector2i.ZERO,grid-Vector2i.ONE)
		cost+=step_cost(TerrainMapGenerator.packed_altitude(source.get_pixelv(p)),TerrainMapGenerator.packed_altitude(source.get_pixelv(q)),delta.length(),delta.length()*context.km_per_height,false,context.city_cells.has(cell.y*grid.x+cell.x))
	return cost

static func _drop_parallel(roads: Array[Dictionary],count: int,provinces: Dictionary) -> void:
	# Preserve the forest and only prune local edges with a nearby alternative.
	for i in range(roads.size()-1,-1,-1):
		var e:=roads[i]
		if e.backbone or int(e.road_tier)==Edge.RoadTier.MAIN: continue
		var route:=_city_shortest(e.a,e.b,roads,count,i)
		if route.is_empty(): continue
		var length:=0.0;var near: Dictionary={}
		for j in route:
			length+=float(roads[j].length)
			var path: PackedVector2Array=roads[j].map_path
			for k in range(path.size()-1):
				for cell in supercover(path[k],path[k+1],provinces.size):
					near[cell]=true
					for offset in OFFSETS: near[cell+offset]=true
		if length>1.6*float(e.length): continue
		var redundant:=true;var path: PackedVector2Array=e.map_path
		for k in range(path.size()-1):
			for cell in supercover(path[k],path[k+1],provinces.size):
				if not near.has(cell): redundant=false;break
		if redundant: roads.remove_at(i)

static func point_key(p: Vector2) -> String:
	return "%.9f,%.9f" % [p.x,p.y]

static func segment_key(a: Vector2,b: Vector2) -> String:
	var x:=point_key(a);var y:=point_key(b)
	return x+"/"+y if x<y else y+"/"+x

static func _smooth_network(roads: Array[Dictionary],provinces: Dictionary,options: Dictionary,source: Image,aspect: float) -> void:
	var segments: Dictionary={};var neighbors: Dictionary={};var points: Dictionary={};var stops: Dictionary={}
	for i in range(roads.size()):
		var path: PackedVector2Array=roads[i].map_path
		stops[point_key(path[0])]=true;stops[point_key(path[-1])]=true
		for j in range(path.size()-1):
			var a:=point_key(path[j]);var b:=point_key(path[j+1]);var key:=segment_key(path[j],path[j+1])
			if a==b: continue
			points[a]=path[j];points[b]=path[j+1]
			if not segments.has(key):
				segments[key]={"a":a,"b":b,"users":[]}
				if not neighbors.has(a): neighbors[a]=[]
				if not neighbors.has(b): neighbors[b]=[]
				neighbors[a].append(key);neighbors[b].append(key)
			segments[key].users.append(i)
	for key in neighbors:
		if neighbors[key].size()!=2: stops[key]=true
	var visited: Dictionary={};var replacement: Dictionary={}
	var keys:=segments.keys();keys.sort()
	for key in keys:
		if visited.has(key): continue
		var e: Dictionary=segments[key]
		# Walk backwards to an endpoint, then forwards through a shared chain.
		var start: String=e.a;var previous: String=key;var back_seen: Dictionary={}
		while not stops.has(start) and not back_seen.has(start):
			back_seen[start]=true
			var other: String=neighbors[start][0] if neighbors[start][0]!=previous else neighbors[start][1]
			var other_edge: Dictionary=segments[other];start=other_edge.b if other_edge.a==start else other_edge.a;previous=other
		var chain_keys: Array[String]=[];var raw:=PackedVector2Array([points[start]])
		var cursor:=start;var current: String=previous if back_seen.size()>0 else key
		while not visited.has(current):
			visited[current]=true;chain_keys.append(current)
			var item: Dictionary=segments[current];cursor=item.b if item.a==cursor else item.a;raw.append(points[cursor])
			if stops.has(cursor): break
			current=neighbors[cursor][0] if neighbors[cursor][0]!=current else neighbors[cursor][1]
		var users: Array=segments[chain_keys[0]].users
		var final:=simplify_collinear(raw)
		for rounds in [3,2,1]:
			var curved:=chaikin(final,rounds);var valid:=true
			for i in users:
				if not path_valid(curved,provinces,roads[i].a,roads[i].b,options): valid=false;break
			if valid: final=curved;break
		var record: Dictionary={"start":start,"path":final,"id":key}
		for part in chain_keys: replacement[part]=record
	for road in roads:
		var raw: PackedVector2Array=road.map_path;var final:=PackedVector2Array([raw[0]]);var last_id: String=""
		for j in range(raw.size()-1):
			var key:=segment_key(raw[j],raw[j+1])
			if not replacement.has(key): continue
			var record: Dictionary=replacement[key]
			if record.id==last_id: continue
			last_id=record.id
			var part: PackedVector2Array=record.path.duplicate()
			if point_key(raw[j])!=record.start: part.reverse()
			for k in range(1,part.size()): final.append(part[k])
		if path_valid(final,provinces,road.a,road.b,options): road.map_path=final
		road.length=TerrainMapGenerator.metric_polyline_length(road.map_path,aspect)
		road.distance=TerrainMapGenerator.distance_units_for_metric_length(road.length)
		road.height_difference=terrain_profile(road.map_path,source).height_difference
		road.danger=clampf(float(road.height_difference)*2.0,0.0,1.0)
		road.cost=road.length*(1.0+road.height_difference*7.0)
		road.terrain_connector=road.height_difference>TerrainMapGenerator.ROAD_MAXIMUM_HEIGHT_DIFFERENCE
		road.base_max_manpower=Edge.TERRAIN_LOW_MANPOWER if road.terrain_connector else Edge.TERRAIN_STANDARD_MANPOWER
		road.max_manpower=road.base_max_manpower

static func step_cost(h0: float, h1: float, length: float, km: float, reused: bool, city: bool) -> float:
	var slope := absf(h1-h0)*6200.0/maxf(km,0.001)/2.5
	var factor := minf(40.0,1.0+slope*slope)*(1.0+(h0+h1)*3100.0/3000.0)
	return length*factor*(0.5 if reused else 1.0)*(1.0 if city else 2.0)

static func pair_key(a: int, b: int) -> int:
	return mini(a,b)*10000+maxi(a,b)

static func prune_links(candidates: Array[Dictionary], count: int) -> Array[Dictionary]:
	var ordered := candidates.duplicate(true)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return float(a.cost)<float(b.cost) if float(a.cost)!=float(b.cost) else pair_key(a.a,a.b)<pair_key(b.a,b.b))
	var forest := {}
	var parent: Array[int] = []
	for i in range(count): parent.append(i)
	var neighbors := {}
	for e in ordered:
		var key := pair_key(e.a,e.b)
		var a := TerrainMapGenerator._root(parent,e.a)
		var b := TerrainMapGenerator._root(parent,e.b)
		if a!=b: parent[b]=a;forest[key]=true
		if not neighbors.has(e.a): neighbors[e.a]={}
		if not neighbors.has(e.b): neighbors[e.b]={}
		neighbors[e.a][e.b]=e;neighbors[e.b][e.a]=e
	var dropped := {}
	for a in range(count):
		var nb: Dictionary = neighbors.get(a,{})
		var ids := nb.keys();ids.sort()
		for b in ids:
			if b<=a: continue
			for c in ids:
				if c<=b or not neighbors[b].has(c): continue
				var triangle: Array = [nb[b],nb[c],neighbors[b][c]]
				triangle.sort_custom(func(x: Dictionary,y: Dictionary)->bool:
					return float(x.cost)<float(y.cost) if float(x.cost)!=float(y.cost) else pair_key(x.a,x.b)<pair_key(y.a,y.b))
				var last: Dictionary = triangle[-1]
				var key := pair_key(last.a,last.b)
				if not forest.has(key): dropped[key]=true
	var out: Array[Dictionary] = []
	for e in ordered:
		if not dropped.has(pair_key(e.a,e.b)):
			e["backbone"]=forest.has(pair_key(e.a,e.b));out.append(e)
	return out

static func path_valid(path: PackedVector2Array, provinces: Dictionary, a: int, b: int, options: Dictionary) -> bool:
	if path.size()<2: return false
	for i in range(path.size()-1):
		if not _pair_segment(provinces.ids,provinces.size,path[i],path[i+1],a,b): return false
		if not _safe_segment(path[i],path[i+1],options): return false
	return true

static func chaikin(path: PackedVector2Array, rounds: int) -> PackedVector2Array:
	var out := path.duplicate()
	for _pass in range(rounds):
		if out.size()<3: break
		var next := PackedVector2Array([out[0]])
		for i in range(out.size()-1):
			next.append(out[i].lerp(out[i+1],0.25));next.append(out[i].lerp(out[i+1],0.75))
		next.append(out[-1]);out=next
	return out

static func terrain_profile(path: PackedVector2Array, source: Image) -> Dictionary:
	var low := 1.0
	var high := 0.0
	for i in range(path.size()-1):
		for p in TerrainMapGenerator._segment_grid_cells(path[i],path[i+1],source.get_size()):
			var h := TerrainMapGenerator.packed_altitude(source.get_pixelv(p))
			low=minf(low,h);high=maxf(high,h)
	return {"height_difference":high-low,"land_ratio":1.0}

static func simplify_collinear(path: PackedVector2Array) -> PackedVector2Array:
	if path.size()<3: return path
	var result := PackedVector2Array([path[0]])
	for i in range(1,path.size()-1):
		var a := path[i]-result[-1]
		var b := path[i+1]-path[i]
		if absf(a.cross(b))>0.000000001 or a.dot(b)<0.0: result.append(path[i])
	result.append(path[-1])
	return result

static func _representatives(source: Image, analysis: Image, provinces: Dictionary) -> PackedVector2Array:
	var grid: Vector2i = provinces.size
	var size := source.get_size()
	var points := PackedVector2Array();points.resize(grid.x*grid.y)
	for y in range(grid.y):
		for x in range(grid.x):
			var cell := Vector2i(x,y)
			var center := Vector2i((Vector2(cell)+Vector2.ONE*0.5)/Vector2(grid)*Vector2(size)).clamp(Vector2i.ZERO,size-Vector2i.ONE)
			var pick := center
			if provinces.ids[y*grid.x+x]>=0 and not TerrainMapGenerator.packed_is_land(source.get_pixelv(center)):
				var low := Vector2i(Vector2(cell)/Vector2(grid)*Vector2(size))
				var high := Vector2i(Vector2(cell+Vector2i.ONE)/Vector2(grid)*Vector2(size))
				var best := INF
				for py in range(low.y,high.y):
					for px in range(low.x,high.x):
						var p := Vector2i(px,py)
						var d := Vector2(p).distance_squared_to(Vector2(center))
						if d<best and TerrainMapGenerator.packed_is_land(source.get_pixelv(p)): best=d;pick=p
			points[y*grid.x+x]=(Vector2(pick)+Vector2.ONE*0.5)/Vector2(size)
	return points

static func _route(a: int,b: int,positions: Array[Vector2],provinces: Dictionary,context: Dictionary,reused: Dictionary) -> PackedVector2Array:
	var grid: Vector2i=provinces.size;var ids: PackedInt32Array=provinces.ids
	var points: PackedVector2Array=context.points.duplicate()
	var first_cell:=Vector2i(positions[a]*Vector2(grid)).clamp(Vector2i.ZERO,grid-Vector2i.ONE)
	var last_cell:=Vector2i(positions[b]*Vector2(grid)).clamp(Vector2i.ZERO,grid-Vector2i.ONE)
	var first:=first_cell.y*grid.x+first_cell.x;var last:=last_cell.y*grid.x+last_cell.x
	points[first]=positions[a];points[last]=positions[b]
	if not context.has("bounds"):
		var bounds: Dictionary={}
		for y in range(grid.y):
			for x in range(grid.x):
				var id:=ids[y*grid.x+x];var cell:=Rect2i(x,y,1,1)
				bounds[id]=bounds[id].merge(cell) if bounds.has(id) else cell
		context.bounds=bounds;context.step_base={}
	if not context.bounds.has(a) or not context.bounds.has(b): return PackedVector2Array()
	var graph:=preload("res://scripts/core/atlas_coarse_astar.gd").new()
	graph.region=context.bounds[a].merge(context.bounds[b]);graph.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	graph.module=load("res://scripts/core/atlas_road_network.gd");graph.context=context;graph.positions=points;graph.first=first;graph.last=last;graph.reuse=reused;graph.grid=grid;graph.update()
	for y in range(graph.region.position.y,graph.region.end.y):
		var blocked:=-1
		for x in range(graph.region.position.x,graph.region.end.x+1):
			var solid: bool=x<graph.region.end.x and ids[y*grid.x+x] not in [a,b]
			if solid and blocked<0: blocked=x
			if not solid and blocked>=0: graph.fill_solid_region(Rect2i(blocked,y,x-blocked,1),true);blocked=-1
	var nodes:=graph.get_id_path(first_cell,last_cell)
	var path:=PackedVector2Array();var cost:=0.0
	for k in range(nodes.size()):
		var p: Vector2i=nodes[k];path.append(points[p.y*grid.x+p.x])
		if k>0: cost+=graph._compute_cost(nodes[k-1],p)
	if not is_finite(cost): return PackedVector2Array()
	context.last_route_cost=cost
	return path

static func _major_cities(positions: Array[Vector2],scores: PackedFloat32Array,aspect: float) -> Array[int]:
	var target := maxi(1,int(ceil(positions.size()/40.0)))
	var order: Array[int]=[]
	for i in range(positions.size()): order.append(i)
	order.sort_custom(func(a: int,b: int)->bool:
		return scores[a]>scores[b] if scores[a]!=scores[b] else a<b)
	var picked: Array[int]=[]
	var spacing := sqrt(aspect/float(target))*0.6
	for _pass in range(12):
		for i in order:
			if picked.has(i): continue
			var allowed:=true
			for j in picked:
				var d:=positions[i]-positions[j];d.x*=aspect
				if d.length()<spacing: allowed=false;break
			if allowed: picked.append(i)
			if picked.size()>=target: return picked
		spacing*=0.8
	return picked

static func _city_shortest(start: int,goal: int,links: Array[Dictionary],count: int,excluded: int=-1) -> Array[int]:
	var neighbors: Array=[]
	for i in range(count): neighbors.append([])
	for i in range(links.size()):
		if i==excluded: continue
		neighbors[links[i].a].append(i);neighbors[links[i].b].append(i)
	var dist:=PackedFloat64Array();dist.resize(count);dist.fill(INF)
	var prev:=PackedInt32Array();prev.resize(count);prev.fill(-1)
	var heap: Array=[];dist[start]=0.0;TerrainMapGenerator._province_heap_push(heap,[0.0,start,0])
	while not heap.is_empty():
		var entry: Array=TerrainMapGenerator._province_heap_pop(heap);var a: int=entry[1]
		if entry[0]>dist[a]: continue
		if a==goal: break
		for i in neighbors[a]:
			var e: Dictionary=links[i];var b: int=e.b if e.a==a else e.a
			var ng:=dist[a]+float(e.cost)
			if ng>=dist[b]: continue
			dist[b]=ng;prev[b]=i;TerrainMapGenerator._province_heap_push(heap,[ng,b,0])
	var out: Array[int]=[]
	var cursor:=goal
	while cursor!=start:
		var i:=prev[cursor]
		if i<0: return []
		out.push_front(i);cursor=links[i].b if links[i].a==cursor else links[i].a
	return out

static func build(source: Image,analysis: Image,samples: Dictionary,provinces: Dictionary,aspect: float,major_scores: PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	var positions: Array[Vector2]=samples.positions
	var grid: Vector2i=provinces.size
	var count:=positions.size()
	var started:=Time.get_ticks_msec();var timings: Dictionary={}
	var checkpoint:=started
	var options: Dictionary={"image":source,"aspect":aspect,"maximum_height":1.0,"river_paths":[],"allow_terrain_connector":true}
	var points:=_representatives(source,analysis,provinces)
	var heights:=PackedFloat32Array();heights.resize(points.size())
	for i in range(points.size()):
		var p:=Vector2i(points[i]*Vector2(source.get_size())).clamp(Vector2i.ZERO,source.get_size()-Vector2i.ONE)
		heights[i]=TerrainMapGenerator.packed_altitude(source.get_pixelv(p))
	var city_cells: Dictionary={}
	for p in positions:
		var cell:=Vector2i(p*Vector2(grid)).clamp(Vector2i.ZERO,grid-Vector2i.ONE);city_cells[cell.y*grid.x+cell.x]=true
	var validator_options: Dictionary=options.duplicate()
	options["segment_validator"] = func(from: Vector2, to: Vector2, a: int, b: int) -> bool: return _safe_segment(from,to,validator_options) and _pair_segment(provinces.ids,grid,from,to,a,b)
	var context: Dictionary={"grid":grid,"points":points,"heights":heights,"aspect":aspect,"km_per_height":4330.0,"options":options,"city_cells":city_cells,"legal":{}}
	timings.representatives=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	var physical:=TerrainMapGenerator.LandComponents.build(source)
	var city_components: Array[int]=[]
	for position in positions: city_components.append(TerrainMapGenerator.LandComponents.at(physical,position))
	var keys:=TerrainMapGenerator.province_shared_boundary_counts(provinces.ids,grid).keys();keys.sort()
	var candidates: Array[Dictionary]=[]
	var fine_fallbacks:=0;var fine_ms:=0;var coarse_ms:=0
	for key in keys:
		var a:=int(key)/10000;var b:=int(key)%10000
		if a>=count or b>=count or city_components[a]!=city_components[b]: continue
		var stamp:=Time.get_ticks_msec()
		var path:=_route(a,b,positions,provinces,context,{})
		coarse_ms+=Time.get_ticks_msec()-stamp
		if path.size()<2:
			stamp=Time.get_ticks_msec()
			path=PixelRoute.find(provinces.ids,grid,positions[a],positions[b],a,b,options);fine_fallbacks+=1;fine_ms+=Time.get_ticks_msec()-stamp
		if path.size()<2: continue
		candidates.append({"a":a,"b":b,"cost":path_cost(path,source,context,{}),"map_path":path})
	timings.fine=fine_ms;timings.coarse=coarse_ms
	timings.candidates=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	var links:=prune_links(candidates,count)
	# Major-to-major routes are promoted as sequences of ordinary city edges.
	var scores:=major_scores.duplicate()
	if scores.size()!=count: scores.resize(count);scores.fill(1.0)
	var major:=_major_cities(positions,scores,aspect)
	var macro: Array[Dictionary]=[]
	for x in range(major.size()):
		for y in range(x+1,major.size()):
			var route:=_city_shortest(major[x],major[y],links,count)
			if route.is_empty(): continue
			var cost:=0.0
			for i in route: cost+=float(links[i].cost)
			macro.append({"a":x,"b":y,"cost":cost,"route":route})
	for e in prune_links(macro,major.size()):
		for i in e.route: links[i]["road_tier"]=Edge.RoadTier.MAIN
	links.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		var ta:=int(a.get("road_tier",Edge.RoadTier.LOCAL));var tb:=int(b.get("road_tier",Edge.RoadTier.LOCAL))
		if ta!=tb: return ta==Edge.RoadTier.MAIN
		return float(a.cost)<float(b.cost) if float(a.cost)!=float(b.cost) else pair_key(a.a,a.b)<pair_key(b.a,b.b))
	timings.skeleton=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	var reused: Dictionary={}
	var roads: Array[Dictionary]=[]
	for e in links:
		var path:=_route(e.a,e.b,positions,provinces,context,reused)
		if path.size()<2: path=e.map_path
		var profile:=terrain_profile(path,source)
		var relief: float=profile.height_difference
		if relief>TerrainMapGenerator.ROAD_MAXIMUM_HEIGHT_DIFFERENCE and not e.backbone: continue
		var length:=TerrainMapGenerator.metric_polyline_length(path,aspect)
		var capacity:=Edge.TERRAIN_LOW_MANPOWER if relief>TerrainMapGenerator.ROAD_MAXIMUM_HEIGHT_DIFFERENCE else Edge.TERRAIN_STANDARD_MANPOWER
		roads.append({"a":e.a,"b":e.b,"kind":Edge.Kind.LAND,"map_path":path,"length":length,"distance":TerrainMapGenerator.distance_units_for_metric_length(length),"cost":length*(1.0+relief*7.0),"height_difference":relief,"land_ratio":1.0,"max_manpower":capacity,"base_max_manpower":capacity,"danger":clampf(relief*2.0,0.0,1.0),"backbone":e.backbone,"terrain_connector":relief>TerrainMapGenerator.ROAD_MAXIMUM_HEIGHT_DIFFERENCE,"road_tier":e.get("road_tier",Edge.RoadTier.LOCAL)})
		# Reuse only roads that really survived terrain validation. Smooth the
		# shared network after all routes are laid, rather than inventing discounts.
		_register_reuse(path,grid,reused)
	timings.routing=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	_drop_parallel(roads,count,provinces)
	timings.parallel=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	_smooth_network(roads,provinces,options,source,aspect)
	_apply_legacy_terrain_rules(roads)
	timings.smoothing=Time.get_ticks_msec()-checkpoint;checkpoint=Time.get_ticks_msec()
	# Keep the established maritime bootstrap, independent of river docks.
	var land:=TerrainMapGenerator._all_land_geometry(analysis).mask as PackedByteArray
	var parent: Array[int]=[]
	for i in range(count): parent.append(i)
	for road in roads: parent[TerrainMapGenerator._root(parent,road.a)]=TerrainMapGenerator._root(parent,road.b)
	var components:=TerrainMapGenerator.Hydrology.components(land,grid,{})
	var first_by_component: Dictionary={}
	for i in range(count):
		var p: Vector2i=samples.pixels[i];var component:=TerrainMapGenerator.LandComponents.at(physical,positions[i])
		if first_by_component.has(component):
			if TerrainMapGenerator._root(parent,i)!=TerrainMapGenerator._root(parent,first_by_component[component]):
				var failure:=FileAccess.open("res://.dbg/atlas-road-failure.json",FileAccess.WRITE)
				if failure!=null:
					var coordinates: Array=[]
					for position in positions: coordinates.append([position.x,position.y])
					failure.store_string(JSON.stringify({"positions":coordinates,"ids":Array(provinces.ids),"roads":roads,"candidates":candidates,"missing_city":i,"reference_city":first_by_component[component],"fine_fallbacks":fine_fallbacks,"grid":[grid.x,grid.y]}))
				return {"ok":false,"error":"同一实际陆地分量的城市 %d 与 %d 未获得合法两省道路。" % [i,first_by_component[component]],"metadata":{"candidate_count":candidates.size(),"fine_fallbacks":fine_fallbacks}}
		else: first_by_component[component]=i
	var empty_paths: Array[Array]=[]
	TerrainMapGenerator._append_sea_component_backbone(roads,parent,analysis,land,samples.pixels,positions,aspect,empty_paths)
	timings.maritime=Time.get_ticks_msec()-checkpoint
	return {"ok":true,"roads":roads,"metadata":{"road_generation_ms":Time.get_ticks_msec()-started,"road_stage_ms":timings,"road_network_version":VERSION,"major_city_ids":major,"candidate_count":candidates.size(),"fine_fallbacks":fine_fallbacks}}

static func _apply_legacy_terrain_rules(roads: Array[Dictionary]) -> void:
	# Preserve the existing relative terrain capacity/danger rules after final
	# canonical paths are measured. Tier is strictly a drawing classification.
	var ordered:=roads.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return float(a.height_difference)<float(b.height_difference) if not is_equal_approx(a.height_difference,b.height_difference) else pair_key(a.a,a.b)<pair_key(b.a,b.b))
	var count:=ordered.size();var standard:=roundi(count*TerrainMapGenerator.ROAD_STANDARD_CAPACITY_SHARE)
	for i in range(count):
		var road: Dictionary=ordered[i]
		var capacity:=Edge.TERRAIN_STANDARD_MANPOWER if i<standard else Edge.TERRAIN_LOW_MANPOWER
		if road.terrain_connector: capacity=Edge.TERRAIN_LOW_MANPOWER
		road.max_manpower=capacity;road.base_max_manpower=capacity
		road.danger=clampf(float(i)/maxi(1,count-1),0,1)
	var target:=maxi(roundi(count*0.10),1);var blocked:=0
	for i in range(count-1,-1,-1):
		if ordered[i].backbone: continue
		ordered[i].max_manpower=0;blocked+=1
		if blocked>=target: break
