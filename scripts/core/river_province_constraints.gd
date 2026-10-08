class_name RiverProvinceConstraints
extends RefCounted
## Opposite shores are an ownership constraint in addition to an edge barrier.
const VERSION := "opposite_banks_v1"
const SOURCE_RADIUS := 0.008
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")

static func build(features: Array, size: Vector2i, aspect: float) -> Dictionary:
	var majors := MapFeatureContract.major_rivers(features)
	var ends := {}
	for river in majors:
		ends[_key(river.points[-1])] = true
	var roots := PackedVector2Array()
	for river in majors:
		if not ends.has(_key(river.points[0])): roots.append(river.points[0])
	var opposites := {}
	var blocked := Hydro.barriers(majors, size)
	var total := size.x * size.y
	for key in blocked:
		var a := int(key) / total
		var b := int(key) % total
		var midpoint := (Vector2(a % size.x, a / size.x) + Vector2(b % size.x, b / size.x) + Vector2.ONE) * 0.5 / Vector2(size)
		var exempt := false
		for root in roots:
			var delta := midpoint - root
			delta.x *= aspect
			if delta.length() <= SOURCE_RADIUS:
				exempt = true
				break
		if exempt: continue
		if not opposites.has(a): opposites[a] = PackedInt32Array()
		if not opposites.has(b): opposites[b] = PackedInt32Array()
		opposites[a].append(b)
		opposites[b].append(a)
	return {"opposites": opposites, "source_roots": roots, "version": VERSION}

static func _key(point: Vector2) -> Vector2i:
	return Vector2i((point * 1048576.0).round())

static func permits(index: int, owner: int, ids: PackedInt32Array, constraints: Dictionary) -> bool:
	for opposite in constraints.get("opposites", {}).get(index, []):
		if ids[opposite] == owner: return false
	return true

static func validate(ids: PackedInt32Array, constraints: Dictionary) -> String:
	for cell in constraints.get("opposites", {}):
		if ids[cell] >= 0 and not permits(cell, ids[cell], ids, constraints):
			return "主河两岸出现同一城市的省份：%d" % ids[cell]
	return ""

## A constrained frontier can leave a bank cell behind its own opposite bank.
## Try connected, short boundary transfers, never disconnected label painting.
static func complete(ids: PackedInt32Array, land: PackedByteArray, size: Vector2i, seeds: Array[Vector2i], blocked: Dictionary, constraints: Dictionary) -> PackedInt32Array:
	var seed_cells := {}
	for owner in range(seeds.size()): seed_cells[seeds[owner].y * size.x + seeds[owner].x] = owner
	var total := ids.size()
	var components := Hydro.components(land, size, blocked)
	var seeded := {}
	for cell in seed_cells: seeded[components[cell]] = true
	var offsets := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for start in range(total):
		if land[start] == 0 or ids[start] >= 0 or not seeded.has(components[start]): continue
		var point := Vector2i(start % size.x, start / size.x)
		var owners: Array[int] = []
		for owner in range(seeds.size()):
			if permits(start, owner, ids, constraints): owners.append(owner)
		owners.sort_custom(func(a: int, b: int) -> bool: return point.distance_squared_to(seeds[a]) < point.distance_squared_to(seeds[b]))
		for owner in owners.slice(0, mini(12, owners.size())):
			var previous := {start: -1}
			var queue: Array[int] = [start]
			var head := 0
			var target := -1
			while head < queue.size() and queue.size() <= 2048:
				var current := queue[head]
				head += 1
				if ids[current] == owner:
					target = current
					break
				var p := Vector2i(current % size.x, current / size.x)
				for offset in offsets:
					var q: Vector2i = p + offset
					if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y: continue
					var next: int = q.y * size.x + q.x
					if land[next] == 0 or previous.has(next) or blocked.has(Hydro.edge_key(current, next, total)): continue
					if seed_cells.has(next) and seed_cells[next] != owner: continue
					if not permits(next, owner, ids, constraints): continue
					previous[next] = current
					queue.append(next)
			if target < 0: continue
			var candidate := ids.duplicate()
			var donors := {}
			var cursor := target
			while cursor >= 0:
				if candidate[cursor] >= 0: donors[candidate[cursor]] = true
				candidate[cursor] = owner
				cursor = previous[cursor]
			if not validate(candidate, constraints).is_empty(): continue
			# A corridor can cut an unseeded branch from its former owner. Try
			# transferring that connected branch with the corridor as one unit.
			# Greedy cell-by-cell filling can otherwise give it back and trap
			# the same frontier again. Legacy sources keep their old behavior.
			if constraints.get("whole_branch_transfer", false):
				var joined := candidate.duplicate()
				for donor in donors:
					if donor == owner: continue
					var reachable := _reachable(joined, size, seeds[donor], donor, blocked)
					for i in range(joined.size()):
						if joined[i] == donor and not reachable.has(i): joined[i] = owner
				if validate(joined, constraints).is_empty() and _connected(joined, size, seeds[owner], owner, blocked):
					ids = joined
					break
			var valid := true
			for donor in donors:
				if not _connected(candidate, size, seeds[donor], donor, blocked):
					var reachable := _reachable(candidate, size, seeds[donor], donor, blocked)
					for i in range(candidate.size()):
						if candidate[i] == donor and not reachable.has(i): candidate[i] = -1
			var pending: Array[int] = []
			for i in range(candidate.size()):
				if land[i] != 0 and candidate[i] < 0 and seeded.has(components[i]): pending.append(i)
			var changed := true
			while changed:
				changed = false
				for i in pending:
					if candidate[i] >= 0: continue
					var p := Vector2i(i % size.x, i / size.x)
					for offset in offsets:
						var q: Vector2i = p + offset
						if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y: continue
						var j: int = q.y * size.x + q.x
						if candidate[j] < 0 or blocked.has(Hydro.edge_key(i,j,total)): continue
						if permits(i,candidate[j],candidate,constraints):
							candidate[i] = candidate[j]
							changed = true
							break
			valid = candidate.count(-1) < ids.count(-1)
			if valid:
				ids = candidate
				break
	return ids

static func _connected(ids: PackedInt32Array, size: Vector2i, seed: Vector2i, owner: int, blocked: Dictionary) -> bool:
	return _reachable(ids,size,seed,owner,blocked).size() == ids.count(owner)

## If a frontier is trapped by its own claim across a meander, transfer that
## conflicting claim through a connected corridor before filling the frontier.
## Every trial is transactional and must reduce blanks without splitting cities.
static func complete_conflicts(ids: PackedInt32Array, land: PackedByteArray, size: Vector2i, seeds: Array[Vector2i], blocked: Dictionary, constraints: Dictionary) -> PackedInt32Array:
	constraints = constraints.duplicate(true)
	constraints["whole_branch_transfer"] = true
	ids = complete(ids, land, size, seeds, blocked, constraints)
	var components := Hydro.components(land, size, blocked)
	var seeded := {}
	var seed_cells := {}
	for owner in range(seeds.size()):
		var cell := seeds[owner].y * size.x + seeds[owner].x
		seeded[components[cell]] = true
		seed_cells[cell] = owner
	for start in range(ids.size()):
		if land[start] == 0 or ids[start] >= 0 or not seeded.has(components[start]): continue
		var tested := {}
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = Vector2i(start % size.x, start / size.x) + offset
			if not Rect2i(Vector2i.ZERO, size).has_point(next): continue
			var neighbor := next.y * size.x + next.x
			var owner := ids[neighbor]
			if owner < 0 or tested.has(owner) or blocked.has(Hydro.edge_key(start, neighbor, ids.size())): continue
			tested[owner] = true
			var candidate := ids.duplicate()
			var trial := constraints.duplicate(true)
			for opposite in constraints.opposites.get(start, []):
				if ids[opposite] != owner or seed_cells.has(opposite): continue
				candidate[opposite] = -1
				if not trial.opposites.has(opposite): trial.opposites[opposite] = PackedInt32Array()
				trial.opposites[opposite].append(seeds[owner].y * size.x + seeds[owner].x)
			candidate = complete(candidate, land, size, seeds, blocked, trial)
			candidate = complete(candidate, land, size, seeds, blocked, constraints)
			if candidate.count(-1) >= ids.count(-1) or not validate(candidate, constraints).is_empty(): continue
			var valid := true
			for city in range(seeds.size()):
				if not _connected(candidate, size, seeds[city], city, blocked): valid = false; break
			if valid: ids = candidate; break
	return ids

static func _reachable(ids: PackedInt32Array, size: Vector2i, seed: Vector2i, owner: int, blocked: Dictionary) -> Dictionary:
	var start := seed.y * size.x + seed.x
	if ids[start] != owner: return {}
	var queue: Array[int] = [start]
	var visited := {start: true}
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		var p := Vector2i(current % size.x, current / size.x)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q: Vector2i = p + offset
			if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y: continue
			var next: int = q.y * size.x + q.x
			if ids[next] != owner or visited.has(next) or blocked.has(Hydro.edge_key(current, next, ids.size())): continue
			visited[next] = true
			queue.append(next)
	return visited
