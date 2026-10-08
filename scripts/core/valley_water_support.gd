extends RefCounted
## Extra access follows connected terrain; it never changes river discharge.
const VERSION := "valley_access_v1"
const BUDGET := 0.12
const MAX_STEP_RISE := 0.04
const UPHILL_COST := 2.0
const RELIEF_COST := 4.0
const LATITUDE_REDUCTION := 0.15
const Support = preload("res://scripts/core/river_settlement_support.gd")
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")

static func cache_identity() -> String:
	return "%s:%s:%s:%s:%s:%s" % [VERSION,BUDGET,MAX_STEP_RISE,UPHILL_COST,RELIEF_COST,LATITUDE_REDUCTION]

static func latitude_factor(latitude: float) -> float:
	return 1.0 - LATITUDE_REDUCTION * exp(-pow((absf(latitude)-27.0)/7.0,2.0))

static func clear_connection(source: Image, a: Vector2, b: Vector2) -> bool:
	return Support.clear_connection(source,a,b)

static func build(source: Image, environment: Dictionary, river_index: Dictionary, aspect: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var size: Vector2i = environment.size
	var land: PackedByteArray = environment.land
	var heights := PackedFloat32Array()
	var distance := PackedFloat32Array()
	var centers := PackedVector2Array()
	heights.resize(land.size())
	distance.resize(land.size())
	distance.fill(INF)
	centers.resize(land.size())
	var latitude_factors := PackedFloat32Array()
	for latitude in environment.latitudes: latitude_factors.append(latitude_factor(latitude))
	for i in range(land.size()):
		centers[i]=(Vector2(i%size.x,i/size.x)+Vector2.ONE*.5)/Vector2(size)
		if land[i]: heights[i]=Support.height_at(source,centers[i])
	var heap: Array = []
	var starts: PackedVector2Array = river_index.starts
	var deltas: PackedVector2Array = river_index.deltas
	for id in range(starts.size()):
		var a := starts[id]/Vector2(aspect,1.0)
		var b := (starts[id]+deltas[id])/Vector2(aspect,1.0)
		var steps := maxi(1,ceili(((b-a)*Vector2(size)).length()*2.0))
		for step in range(steps+1):
			var p := a.lerp(b,float(step)/steps)
			var cell := Vector2i(p*Vector2(size)).clamp(Vector2i.ZERO,size-Vector2i.ONE)
			var i := cell.y*size.x+cell.x
			if land[i]==0: continue
			var rise := maxf(heights[i]-Support.height_at(source,p),0.0)
			if rise >= MAX_STEP_RISE: continue
			var cost := ((centers[i]-p)*Vector2(aspect,1.0)).length()+UPHILL_COST*rise
			if cost>=distance[i] or cost>=BUDGET or not clear_connection(source,p,centers[i]): continue
			distance[i]=cost
			Hydro._push(heap,Vector2(cost,i))
	var checked_edges := {}
	while not heap.is_empty():
		var entry := Hydro._pop(heap)
		var i := int(entry.y)
		if entry.x>distance[i]+0.0000001: continue
		var cell := Vector2i(i%size.x,i/size.x)
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i=cell+offset
			if not Rect2i(Vector2i.ZERO,size).has_point(next): continue
			var j: int=next.y*size.x+next.x
			if land[j]==0 or absf(heights[j]-heights[i])>=MAX_STEP_RISE: continue
			var step_length: float=aspect/size.x if offset.x!=0 else 1.0/size.y
			var relief := maxf(environment.relief[i],environment.relief[j])
			var cost := float(distance[i])+step_length*(1.0+RELIEF_COST*minf(relief/0.1,1.0))+UPHILL_COST*maxf(heights[j]-heights[i],0.0)
			if cost>=BUDGET or cost>=distance[j]-0.0000001: continue
			var key := Hydro.edge_key(i,j,land.size())
			if not checked_edges.has(key): checked_edges[key]=clear_connection(source,centers[i],centers[j])
			if not checked_edges[key]: continue
			distance[j]=cost
			Hydro._push(heap,Vector2(cost,j))
	var support := PackedFloat32Array()
	support.resize(land.size())
	for i in range(land.size()): support[i]=(1.0-smoothstep(0.0,BUDGET,distance[i]))*latitude_factors[i/size.x] if distance[i]<BUDGET else 0.0
	return {"support":support,"heights":heights,"distance":distance,"size":size,"aspect":aspect,"latitude_factors":latitude_factors,"elapsed_usec":Time.get_ticks_usec()-started,"version":VERSION}

static func support_at(field: Dictionary, source: Image, position: Vector2) -> float:
	var size: Vector2i=field.size
	var cell:=Vector2i(position*Vector2(size)).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var i:=cell.y*size.x+cell.x
	if field.support[i]<=0.0: return 0.0
	var center:=(Vector2(cell)+Vector2.ONE*.5)/Vector2(size)
	var rise:=maxf(Support.height_at(source,position)-field.heights[i],0.0)
	if rise>=MAX_STEP_RISE or not clear_connection(source,center,position): return 0.0
	var cost:float=field.distance[i]+((position-center)*Vector2(field.aspect,1.0)).length()+UPHILL_COST*rise
	return (1.0-smoothstep(0.0,BUDGET,cost))*field.latitude_factors[cell.y] if cost<BUDGET else 0.0
