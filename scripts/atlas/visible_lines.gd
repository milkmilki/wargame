extends RefCounted
## Select whole unwrapped chains, retaining dash phase and seam continuity.
const WIDTH := 2048.
static func index(paths: Array) -> Array:
	var out: Array = []
	for path in paths:
		if path.size()<2: continue
		var box := Rect2(path[0],Vector2.ZERO)
		for point in path: box = box.expand(point)
		out.append({"path":path,"box":box})
	return out

static func select(records: Array,rect: Rect2) -> Array:
	var out: Array = []
	for record in records:
		for shift in [-WIDTH,0.,WIDTH]:
			if rect.intersects(Rect2(record.box.position+Vector2(shift,0),record.box.size),true):
				out.append(record.path); break
	return out
