extends RefCounted
## Ferry targets use continuous projected river arc, never province/reach count.
const Sampling = preload("res://scripts/core/river_dock_sampling.gd")
const Transport = preload("res://scripts/core/river_transport.gd")
const VERSION := "ferry_interval_v2"

static func select(candidates: Array, features: Array, aspect: float, interval: float, minimum_spacing: float, maximum_per_river: int = 0) -> Dictionary:
	var by_id := {}
	var ending := {}
	for feature in MapFeatureContract.major_rivers(features):
		by_id[int(feature.id)] = feature
		var key := Transport._key(feature.points[-1])
		if not ending.has(key): ending[key] = []
		ending[key].append(int(feature.id))
	var origins := {}
	var river_by_id := river_groups(features)
	var river_extents := {}
	var lengths := {}
	var extents := {}
	var intervals := {}
	var total_length := 0.0
	for id in by_id:
		var cumulative := PackedFloat64Array([0.0])
		var path: PackedVector2Array = by_id[id].points
		for i in range(path.size()-1): cumulative.append(cumulative[-1] + TerrainMapGenerator.metric_length_between(path[i],path[i+1],aspect))
		lengths[id] = cumulative
		var origin := Sampling._origin(id,by_id,ending,origins,aspect,{})
		var end := float(origin.distance)+cumulative[-1]
		var river: String = river_by_id[id]
		river_extents[river] = maxf(float(river_extents.get(river,0.0)),end)
		extents[origin.root] = maxf(float(extents.get(origin.root,0.0)),end)
		total_length += cumulative[-1]
		for slot in range(int(floor(origin.distance/interval)),int(floor((end-1e-9)/interval))+1):
			intervals["%s:%d" % [origin.root,slot]] = true
	if maximum_per_river>0:
		intervals.clear()
		for river in river_extents:
			var slots := mini(maximum_per_river,maxi(1,int(ceil(float(river_extents[river])/interval-1e-6))))
			for slot in range(slots): intervals["%s:%d" % [river,slot]]=true
	var groups := {}
	var ordered: Array[Dictionary] = []
	for value in candidates:
		var id := int(value.river_id)
		if not by_id.has(id): continue
		var origin := Sampling._origin(id,by_id,ending,origins,aspect,{})
		var cumulative: PackedFloat64Array = lengths[id]
		var progress := float(value.river_progress)
		var index := clampi(int(floor(progress)),0,cumulative.size()-2)
		var arc := float(origin.distance) + lerpf(cumulative[index],cumulative[index+1],progress-index)
		var river: String = river_by_id[id]
		var identity: String = river if maximum_per_river>0 else str(origin.root)
		var extent := float(river_extents[river] if maximum_per_river>0 else extents[origin.root])
		var step := maxf(interval,extent/maximum_per_river) if maximum_per_river>0 else interval
		# A sample exactly at a terminal must not create another interval.
		var slot := int(floor(maxf(0,minf(arc,extent-1e-7))/step))
		if maximum_per_river>0: slot=mini(slot,maximum_per_river-1)
		var key := "%s:%d" % [identity,slot]
		var point: Dictionary = value.duplicate(true)
		point.merge({"ferry_arc":arc,"ferry_root":origin.root,"ferry_river":river,"ferry_spacing_id":identity,"ferry_step":step,"ferry_slot":key,"target_error":absf(arc-(slot+.5)*step)},true)
		if not groups.has(key): groups[key] = []
		groups[key].append(point)
		ordered.append(point)
	var keys: Array = groups.keys()
	keys.sort_custom(func(a: String,b: String) -> bool:
		var ap: Dictionary = groups[a][0]; var bp: Dictionary = groups[b][0]
		if ap.ferry_spacing_id!=bp.ferry_spacing_id: return str(ap.ferry_spacing_id)<str(bp.ferry_spacing_id)
		return ap.ferry_arc<bp.ferry_arc
	)
	var selected: Array[Dictionary] = []
	var rejected_spacing := 0
	for key in keys:
		var group: Array = groups[key]
		group.sort_custom(_preferred)
		for point in group:
			var too_close := false
			for previous in selected:
				if TerrainMapGenerator.metric_length_between(point.position,previous.position,aspect) < minimum_spacing:
					too_close = true; break
				if point.ferry_spacing_id == previous.ferry_spacing_id and absf(point.ferry_arc-previous.ferry_arc)<point.ferry_step*.75:
					too_close = true; break
			if too_close: rejected_spacing += 1; continue
			point["ferry_reason"] = "interval"
			selected.append(point)
			break
	ordered.sort_custom(_preferred)
	return {"selected":selected,"candidates":ordered,"river_by_id":river_by_id,"candidate_intervals":groups.size(),"total_intervals":intervals.size(),"intervals_without_legal_candidate":maxi(0,intervals.size()-groups.size()),"main_river_length":total_length,"spacing_rejections":rejected_spacing}

## A connected main-river network shares one quota. Name it by its outlet,
## so artificial reach cuts, feature IDs and source ordering cannot reset it.
static func river_groups(features: Array) -> Dictionary:
	var parent := {}
	var touching := {}
	var starting := {}
	var majors := MapFeatureContract.major_rivers(features)
	for feature in majors:
		var id := int(feature.id)
		parent[id]=id
		var start := Transport._key(feature.points[0])
		starting[start]=true
		for key in [start,Transport._key(feature.points[-1])]:
			if not touching.has(key): touching[key]=[]
			touching[key].append(id)
	for ids in touching.values():
		for id in ids: parent[_group_root(parent,int(id))]=_group_root(parent,int(ids[0]))
	var outlets := {}
	var fallback := {}
	for feature in majors:
		var root := _group_root(parent,int(feature.id))
		var end := Transport._key(feature.points[-1])
		if not fallback.has(root): fallback[root]=[]
		fallback[root].append(end)
		if not starting.has(end):
			if not outlets.has(root): outlets[root]=[]
			outlets[root].append(end)
	var result := {}
	for feature in majors:
		var root := _group_root(parent,int(feature.id))
		var ends: Array = outlets.get(root,fallback[root])
		ends.sort()
		result[int(feature.id)]="outlet:"+str(ends[0])
	return result

static func _group_root(parent: Dictionary,id: int) -> int:
	while int(parent[id])!=id: parent[id]=parent[parent[id]]; id=int(parent[id])
	return id

static func _preferred(a: Dictionary,b: Dictionary) -> bool:
	for field in ["target_error","relief","height"]:
		var av := float(a.get(field,0.0)); var bv := float(b.get(field,0.0))
		if absf(av-bv)>1e-9: return av<bv
	var ap: Vector2 = a.position; var bp: Vector2 = b.position
	if ap.x != bp.x: return ap.x<bp.x
	if ap.y != bp.y: return ap.y<bp.y
	return int(a.river_id)<int(b.river_id)

## Kruskal on existing transport components: every extra ferry removes a cut.
## The caller includes existing navigable river links and can prune further
## after new ferries introduce additional navigation links.
static func connect_components(candidates: Array, count: int, links: Array[Vector2i], regular: Array, required: Array[int], eligible: Callable = Callable(), maximum_per_river: int = 0) -> Array[Dictionary]:
	var parent: Array[int] = []
	for i in range(count): parent.append(i)
	for pair in links: parent[_root(parent,pair.x)] = _root(parent,pair.y)
	for dock in regular: parent[_root(parent,int(dock.bank_a))] = _root(parent,int(dock.bank_b))
	var river_counts := {}
	for dock in regular:
		var river := str(dock.get("ferry_river",""))
		river_counts[river]=int(river_counts.get(river,0))+1
	var result: Array[Dictionary] = []
	for point in candidates:
		var a := _root(parent,int(point.bank_a)); var b := _root(parent,int(point.bank_b))
		if a==b: continue
		var roots := {}
		for id in required: roots[_root(parent,id)] = true
		if roots.size()<=1: break
		if not roots.has(a) and not roots.has(b): continue
		var river := str(point.get("ferry_river",""))
		if maximum_per_river>0 and int(river_counts.get(river,0))>=maximum_per_river: continue
		if eligible.is_valid() and not eligible.call(point,result): continue
		var extra: Dictionary = point.duplicate(true)
		extra["ferry_reason"] = "connectivity"
		result.append(extra)
		river_counts[river]=int(river_counts.get(river,0))+1
		parent[a] = b
	return result

static func _root(parent: Array[int], id: int) -> int:
	while parent[id]!=id: parent[id]=parent[parent[id]]; id=parent[id]
	return id
