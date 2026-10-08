extends RefCounted
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")
const Banks = preload("res://scripts/core/river_province_constraints.gd")
const VERSION := "shore_seed_transfer_v2"
const LIMIT := 25

static func gaps(ids: PackedInt32Array, land: PackedByteArray, components: PackedInt32Array, pixels: Array[Vector2i], size: Vector2i) -> Array[int]:
	var seeded := {}
	for p in pixels: seeded[components[p.y * size.x + p.x]] = true
	var result: Array[int] = []
	for i in range(ids.size()):
		if land[i] != 0 and ids[i] < 0 and seeded.has(components[i]): result.append(i)
	return result

static func repair(samples: Dictionary, provinces: Dictionary, image: Image, source: Image, mask: PackedByteArray, blocked: Dictionary, constraints: Dictionary, pixel_aspect: float) -> Dictionary:
	var size := image.get_size()
	var pool: Dictionary = samples.candidate_pool
	var components := Hydro.components(mask, size, blocked)
	var missing := gaps(provinces.ids, mask, components, samples.pixels, size)
	var moves := []
	var attempted := {}
	var resolved := {}
	var trial_results := []
	while not missing.is_empty() and moves.size() < LIMIT:
		var target_cell := missing[0]
		var target := (Vector2(target_cell % size.x, target_cell / size.x) + Vector2.ONE * 0.5) / Vector2(size)
		var distances := PackedInt32Array()
		distances.resize(mask.size())
		distances.fill(-1)
		distances[target_cell] = 0
		var queue: Array[int] = [target_cell]
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			var p := Vector2i(current % size.x, current / size.x)
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q: Vector2i = p + offset
				if not Rect2i(Vector2i.ZERO, size).has_point(q): continue
				var next := q.y * size.x + q.x
				if mask[next] == 0 or distances[next] >= 0 or blocked.has(Hydro.edge_key(current, next, mask.size())): continue
				distances[next] = distances[current] + 1
				queue.append(next)
		var candidates: Array[int] = []
		for i in pool.order:
			if components[i] == components[target_cell] and not attempted.has(i): candidates.append(i)
		candidates.sort_custom(func(a: int, b: int) -> bool:
			if distances[a] != distances[b]: return distances[a] < distances[b]
			var da: float = ((pool.positions[a] - target) * Vector2(pool.aspect, 1)).length_squared()
			var db: float = ((pool.positions[b] - target) * Vector2(pool.aspect, 1)).length_squared()
			if not is_equal_approx(da, db): return da < db
			return pool.weights[a] > pool.weights[b] if pool.weights[a] != pool.weights[b] else a < b
		)
		var counts := {}
		var used := {}
		var bank_owners := {}
		var areas := {}
		for owner in provinces.ids:
			if owner >= 0: areas[owner] = int(areas.get(owner, 0)) + 1
		for i in constraints.opposites:
			if provinces.ids[i] >= 0: bank_owners[provinces.ids[i]] = true
		for p in samples.pixels:
			var i: int = p.y * size.x + p.x
			used[i] = true
			counts[components[i]] = int(counts.get(components[i], 0)) + 1
		var accepted := false
		var trials := 0
		var donor_trials := {}
		for cell in candidates:
			if used.has(cell): continue
			var donor := -1
			var conflict := false
			for city in range(samples.positions.size()):
				var old_cell: int = samples.pixels[city].y * size.x + samples.pixels[city].x
				var minimum: float = (pool.spacing[cell] + pool.spacing[old_cell]) * 0.5 * 0.8
				if ((pool.positions[cell] - samples.positions[city]) * Vector2(pool.aspect, 1)).length_squared() < minimum * minimum:
					if donor >= 0: conflict = true; break
					donor = city
			if conflict: continue
			if donor < 0:
				for city in range(samples.pixels.size()):
					var i: int = samples.pixels[city].y * size.x + samples.pixels[city].x
					if counts[components[i]] <= 1 or bank_owners.has(city): continue
					if donor < 0 or areas.get(city, 0) < areas.get(donor, 0): donor = city
			if donor < 0: continue
			var old_index: int = samples.pixels[donor].y * size.x + samples.pixels[donor].x
			if counts[components[old_index]] <= 1: continue
			# Adjacent candidates usually move the same nearby city and reopen
			# the same former shore. Spend the bounded search on other donors
			# as well, instead of exhausting it on eight equivalent positions.
			if int(donor_trials.get(donor, 0)) >= 2: continue
			donor_trials[donor] = int(donor_trials.get(donor, 0)) + 1
			attempted[cell] = true
			trials += 1
			var pixels: Array[Vector2i] = samples.pixels.duplicate()
			pixels[donor] = Vector2i(cell % size.x, cell / size.x)
			var no_paths: Array[Array] = []
			var trial_started := Time.get_ticks_usec()
			var trial := TerrainMapGenerator._build_province_raster(image, mask, Rect2i(Vector2i.ZERO, size), pixels, no_paths, pixel_aspect, true, blocked, constraints)
			var growth_usec := Time.get_ticks_usec() - trial_started
			if not trial.get("ok", true): continue
			var next_missing := gaps(trial.ids, mask, components, pixels, size)
			if not next_missing.has(target_cell):
				trial.ids = Banks.complete_conflicts(trial.ids, mask, size, pixels, blocked, constraints)
				next_missing = gaps(trial.ids, mask, components, pixels, size)
			trial_results.append({"cell": cell, "donor": donor, "target": target_cell, "gaps": next_missing, "growth_usec": growth_usec, "repair_usec": Time.get_ticks_usec() - trial_started - growth_usec})
			if OS.get_environment("HYDROLOGY_DIAGNOSE") == "1": print("SHORE_SEED_TRIAL target=", target_cell, " cell=", cell, " donor=", donor, " remaining=", next_missing.size())
			var reopens_repaired_bank := false
			for gap in next_missing:
				if resolved.has(gap): reopens_repaired_bank = true; break
			if next_missing.size() <= missing.size() and not next_missing.has(target_cell) and not reopens_repaired_bank:
				resolved[target_cell] = true
				moves.append({"city": donor, "from": samples.positions[donor], "to": pool.positions[cell], "reason": "unassigned_river_bank", "gap": target_cell})
				samples.positions[donor] = pool.positions[cell]
				samples.pixels = pixels
				var p := Vector2i(pool.positions[cell] * Vector2(source.get_size()))
				samples.heights[donor] = TerrainMapGenerator.packed_altitude(source.get_pixelv(p))
				samples.reliefs[donor] = pool.relief[cell]
				provinces = trial
				missing = next_missing
				accepted = true
				break
			if trials >= 8: break
		if not accepted: break
	return {"provinces": provinces, "moves": moves, "remaining_gaps": missing, "version": VERSION, "trials": trial_results}
