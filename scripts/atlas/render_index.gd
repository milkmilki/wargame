extends RefCounted
## Immutable world-space buckets. Copies are a query concern, never new records.
const CELL := 64.
var boxes: Array = []
var buckets := {}
func add(box: Rect2) -> void:
	var id := boxes.size(); boxes.append(box)
	for y in range(floori(box.position.y/CELL),floori(box.end.y/CELL)+1):
		for x in range(floori(box.position.x/CELL),floori(box.end.x/CELL)+1):
			var key := Vector2i(x,y)
			if not buckets.has(key): buckets[key] = []
			buckets[key].append(id)
func query(rect: Rect2) -> PackedInt32Array:
	var found := {}
	for shift in [-2048.,0.,2048.]:
		var q := Rect2(rect.position+Vector2(shift,0),rect.size)
		for y in range(floori(q.position.y/CELL),floori(q.end.y/CELL)+1):
			for x in range(floori(q.position.x/CELL),floori(q.end.x/CELL)+1):
				for id in buckets.get(Vector2i(x,y),[]):
					if boxes[id].intersects(q,true): found[id] = true
	var out := PackedInt32Array(found.keys()); out.sort(); return out
