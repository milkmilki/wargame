extends RefCounted
## Continuous main-river arc sampling, independent of artificial reach splits.
const Transport = preload("res://scripts/core/river_transport.gd")
const VERSION := "continuous_docks_v1"
const STEP := 0.006
const COVERAGE := 0.036

static func samples(features: Array,aspect: float) -> Array[Dictionary]:
	var majors := MapFeatureContract.major_rivers(features)
	var ending := {}
	var starting := {}
	var by_id := {}
	for feature in majors:
		by_id[int(feature.id)]=feature
		var key := Transport._key(feature.points[-1])
		if not ending.has(key): ending[key]=[]
		ending[key].append(int(feature.id))
		var start_key := Transport._key(feature.points[0])
		if not starting.has(start_key): starting[start_key]=[]
		starting[start_key].append(int(feature.id))
	var origins := {}
	var result: Array[Dictionary]=[]
	var starts: Array[int]=[]
	for feature in majors:
		var key := Transport._key(feature.points[0])
		if ending.get(key,[]).size()!=1 or starting.get(key,[]).size()!=1: starts.append(int(feature.id))
	var visited := {}
	for first in starts:
		if visited.has(first): continue
		var segments: Array[Dictionary]=[]
		var id := first
		var length := 0.0
		while not visited.has(id):
			visited[id]=true
			var points: PackedVector2Array=by_id[id].points
			for i in range(points.size()-1):
				var span := TerrainMapGenerator.metric_length_between(points[i],points[i+1],aspect)
				segments.append({"a":points[i],"b":points[i+1],"id":id,"index":i,"start":length,"length":span})
				length+=span
			var key := Transport._key(points[-1])
			if ending.get(key,[]).size()!=1 or starting.get(key,[]).size()!=1: break
			id=starting[key][0]
		var origin := _origin(first,by_id,ending,origins,aspect,{})
		var distance: float = (floorf((origin.distance-STEP*0.5)/STEP)+1)*STEP+STEP*0.5-origin.distance
		var targets: Array[float]=[]
		if length<STEP: targets.append(length*0.5)
		else:
			while distance<length-1e-8: targets.append(distance); distance+=STEP
		var index := 0
		for target in targets:
			while index<segments.size()-1 and segments[index].start+segments[index].length<target: index+=1
			var segment: Dictionary=segments[index]
			var ratio := clampf((target-segment.start)/maxf(segment.length,1e-12),0,1)
			result.append({"river_id":segment.id,"river_progress":segment.index+ratio,"position":segment.a.lerp(segment.b,ratio),"direction":segment.b-segment.a,"arc":origin.distance+target,"coverage":"%s:%d"%[origin.root,int(floor((origin.distance+target)/COVERAGE))],"reach_fraction":target/maxf(length,1e-12)})
	return result

static func _origin(id: int,by_id: Dictionary,ending: Dictionary,cache: Dictionary,aspect: float,visiting: Dictionary) -> Dictionary:
	if cache.has(id): return cache[id]
	var path: PackedVector2Array=by_id[id].points
	var key := Transport._key(path[0])
	var result := {"distance":0.0,"root":key}
	if visiting.has(id): return result
	var seen := visiting.duplicate()
	seen[id]=true
	for predecessor in ending.get(key,[]):
		var origin := _origin(predecessor,by_id,ending,cache,aspect,seen)
		var distance: float=origin.distance+TerrainMapGenerator.metric_polyline_length(by_id[predecessor].points,aspect)
		if distance>result.distance or (distance==result.distance and str(origin.root)<str(result.root)): result={"distance":distance,"root":origin.root}
	cache[id]=result
	return result

