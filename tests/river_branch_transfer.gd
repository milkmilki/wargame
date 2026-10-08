extends SceneTree
## A main-river frontier needs a corridor through a donor province. The donor's
## unseeded branch must move with that corridor, never become a painted island.
const Banks = preload("res://scripts/core/river_province_constraints.gd")
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")
const SIZE := Vector2i(5, 5)
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_BRANCH_TRANSFER_FAIL: ", message)

func index(point: Vector2i) -> int: return point.y * SIZE.x + point.x

func barrier(f: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var first := index(a)
	var second := index(b)
	f.blocked[Hydro.edge_key(first, second, SIZE.x * SIZE.y)] = true
	if not f.constraints.opposites.has(first): f.constraints.opposites[first] = PackedInt32Array()
	if not f.constraints.opposites.has(second): f.constraints.opposites[second] = PackedInt32Array()
	f.constraints.opposites[first].append(second)
	f.constraints.opposites[second].append(first)

func fixture(forbid_branch: bool = false) -> Dictionary:
	# . . 0 A .      A: donor city, B: recipient city, ?: unassigned land.
	# . 1 0 ? .      Corridor ? -> (2,1) -> (1,1) cuts the donor's lower
	# . B 0 0 .      three-cell branch off its city. Both initial provinces
	# . . . 0 .      are connected. The river blocks A -> ? throughout.
	# . . . . .
	var ids := PackedInt32Array()
	ids.resize(SIZE.x * SIZE.y)
	ids.fill(-1)
	var land := PackedByteArray()
	land.resize(ids.size())
	for point in [Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)]:
		ids[index(point)] = 0
		land[index(point)] = 1
	for point in [Vector2i(1, 1), Vector2i(1, 2)]:
		ids[index(point)] = 1
		land[index(point)] = 1
	land[index(Vector2i(3, 1))] = 1
	var seeds: Array[Vector2i] = [Vector2i(3, 0), Vector2i(1, 2)]
	var f := {"ids": ids, "land": land, "seeds": seeds, "blocked": {}, "constraints": {"opposites": {}}}
	barrier(f, Vector2i(3, 0), Vector2i(3, 1))
	# Negative control: the branch touches the recipient's fixed city across
	# a second main river. Transferring it would give that city both banks.
	if forbid_branch: barrier(f, Vector2i(1, 2), Vector2i(2, 2))
	return f

func verify(ids: PackedInt32Array, f: Dictionary, label: String) -> void:
	check(Banks.validate(ids, f.constraints).is_empty(), label + " keeps different owners across main rivers")
	for owner in range(f.seeds.size()):
		check(ids[index(f.seeds[owner])] == owner, label + " preserves every city seed")
		check(Banks._connected(ids, SIZE, f.seeds[owner], owner, f.blocked), label + " keeps every assigned cell connected to its city")
	for i in range(ids.size()):
		if f.land[i] == 0: check(ids[i] == -1, label + " leaves non-land unassigned")

func run() -> void:
	var f := fixture()
	verify(f.ids, f, "initial positive fixture")
	var initial: PackedInt32Array = f.ids.duplicate()
	var result := Banks.complete_conflicts(f.ids, f.land, SIZE, f.seeds, f.blocked, f.constraints)
	check(result[index(Vector2i(3, 1))] == 1, "recipient reaches the previously trapped frontier")
	for point in [Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)]:
		check(result[index(point)] == 1, "corridor and all detached donor branch cells transfer together: %s" % point)
	for i in range(f.land.size()):
		if f.land[i] != 0: check(result[i] >= 0, "all seeded fixture land is fully assigned")
	verify(result, f, "legal joint transfer")
	check(f.ids == initial, "repair does not mutate the caller's original assignment")
	var illegal := fixture(true)
	verify(illegal.ids, illegal, "initial negative fixture")
	var rejected := Banks.complete_conflicts(illegal.ids, illegal.land, SIZE, illegal.seeds, illegal.blocked, illegal.constraints)
	check(rejected == illegal.ids, "a branch that conflicts with the recipient's fixed opposite-bank city is rejected transactionally")
	check(rejected[index(Vector2i(3, 1))] == -1, "impossible joint transfer remains a visible unresolved gap, not an illegal repair")
	verify(rejected, illegal, "rejected joint transfer")
	print("RIVER_BRANCH_TRANSFER: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
