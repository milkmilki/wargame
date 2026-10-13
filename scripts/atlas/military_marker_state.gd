extends RefCounted
## Presentation cache. Never stores derived values on simulation Army/Edge objects.
const WORLD := Vector2(2048,1024)
var world_key: Array = []
var routes := {}
var build_count := 0

func position(state: GameState,army: Army) -> Vector2:
	var key := [state.get_instance_id(),state.road_network_revision]
	if key != world_key:
		world_key = key; routes.clear()
	if army.on_edge and army.move_from>=0 and army.move_to>=0:
		var edge := state.edge_of(army.move_from,army.move_to)
		if edge != null:
			var a := state.cities[edge.city_a].map_position
			var b := state.cities[edge.city_b].map_position
			var signature := [hash(edge.map_path),edge.spherical_path,a,b]
			var id := edge.get_instance_id()
			if not routes.has(id) or routes[id].signature != signature:
				var points := edge.map_points(a,b)
				var lengths := PackedFloat64Array(); lengths.append(0.)
				for i in range(points.size()-1):
					lengths.append(lengths[-1]+edge._path_segment_length(points[i],points[i+1],2.))
				routes[id] = {"signature":signature,"points":points,"lengths":lengths}; build_count += 1
			var route: Dictionary = routes[id]
			var lengths: PackedFloat64Array = route.lengths
			var points: PackedVector2Array = route.points
			var progress := army.move_progress if army.move_from==edge.city_a else 1.-army.move_progress
			var target := clampf(progress,0.,1.)*lengths[-1]
			var lo := 0; var hi := lengths.size()-1
			while lo+1 < hi:
				var mid: int = (lo+hi)/2
				if lengths[mid]>=target: hi = mid
				else: lo = mid
			return points[lo].lerp(points[hi],(target-lengths[lo])/maxf(lengths[hi]-lengths[lo],.000001))*WORLD
	return state.cities[maxi(0,army.location_city)].map_position*WORLD if not state.cities.is_empty() else Vector2.ZERO

static func visible_copies(point: Vector2,rect: Rect2,padding: float = 0.) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var area := rect.grow(maxf(0.,padding))
	if not area.has_area() or point.y<area.position.y or point.y>=area.end.y: return result
	var x := fposmod(point.x,WORLD.x)
	for copy in range(ceili((area.position.x-x)/WORLD.x),floori((area.end.x-x)/WORLD.x)+1):
		var candidate := Vector2(x+copy*WORLD.x,point.y)
		if area.has_point(candidate): result.append(candidate)
	return result
