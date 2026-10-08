extends SceneTree
## Drainage sampling must preserve source-elevation evidence of narrow outlets.
## An unresolved coarse basin must not justify draining a genuinely deep basin.
const Hydrology = preload("res://scripts/core/terrain_hydrology.gd")
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _height_color(height: float) -> Color:
	return Color(1.0, 1.0, 1.0, (128.0 + round(height * 127.0)) / 255.0)

func _decode(image: Image) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			result.append(maxf((image.get_pixel(x, y).a * 255.0 - 128.0) / 127.0, 0.0))
	return result

func _terminal(result: Dictionary, start: int) -> int:
	var node := start
	for iteration in range(result.downstream.size() + 1):
		var next: int = result.downstream[node]
		if next < 0:
			return node
		node = next
	return -1

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("HYDROLOGY_DRAINAGE_RESOLUTION_FAIL: ", message)

func _deep_basin() -> void:
	var size := Vector2i(9, 9)
	var heights := PackedFloat32Array()
	var sea := PackedByteArray()
	var local := PackedFloat32Array()
	heights.resize(size.x * size.y)
	heights.fill(0.70)
	sea.resize(heights.size())
	local.resize(heights.size())
	for y in range(3, 6):
		for x in range(3, 6):
			heights[y * size.x + x] = 0.10
	for y in range(size.y):
		sea[y * size.x + 8] = 1
	var start := 4 * size.x + 4
	local[start] = 20.0
	var result := Hydrology.solve(heights, sea, local, size, 1.0)
	var terminal := _terminal(result, start)
	_check(terminal >= 0, "deep-basin drainage remains acyclic")
	if terminal >= 0:
		_check(result.terminal_kind[terminal] == "basin", "a genuinely deep closed basin retains an inland terminal")
		_check(is_equal_approx(result.flow[terminal], 20.0), "deep basin retains its supplied water")
		_check(is_equal_approx(result.routing_heights[terminal], 0.10), "deep basin is not raised to a distant spill level")
	print("DEEP_BASIN_DIAGNOSTIC terminal=", terminal, " kind=", result.terminal_kind[terminal] if terminal >= 0 else "cycle")

func _run() -> void:
	_deep_basin()
	var size := Vector2i(16, 9)
	var source := Image.create(size.x * 4, size.y * 4, false, Image.FORMAT_RGBA8)
	source.fill(_height_color(0.65))
	# A broad upstream valley meets a high transverse ridge. Its only outlet is
	# one original pixel wide, inside the analysis cell but off its center sample.
	for y in range(16, 20):
		for x in range(8, 32):
			source.set_pixel(x, y, _height_color(0.20))
		for x in range(36, 60):
			source.set_pixel(x, y, _height_color(0.15 - float(x - 36) * 0.004))
	for x in range(32, 36):
		source.set_pixel(x, 17, _height_color(0.18))
	for y in range(source.get_height()):
		for x in range(60, 64):
			source.set_pixel(x, y, _height_color(0.0))
	var nearest := source.duplicate()
	nearest.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var coarse := _decode(nearest)
	var sea := PackedByteArray()
	var local := PackedFloat32Array()
	sea.resize(size.x * size.y)
	local.resize(sea.size())
	for y in range(size.y):
		sea[y * size.x + size.x - 1] = 1
	var start := 4 * size.x + 5
	var gate := 4 * size.x + 8
	local[start] = 20.0
	var unresolved := Hydrology.solve(coarse, sea, local, size, float(size.x - 1) / (size.y - 1))
	var coarse_terminal := _terminal(unresolved, start)
	_check(coarse[gate] > 0.50, "fixture's nearest-neighbor sample really misses the narrow low outlet")
	_check(coarse_terminal >= 0 and unresolved.terminal_kind[coarse_terminal] == "basin", "fixture reproduces premature inland termination from coarse sampling")
	print("NARROW_OUTLET_BASELINE coarse_gate=%.6f coarse_terminal=%d terminal_kind=%s" % [coarse[gate], coarse_terminal, unresolved.terminal_kind[coarse_terminal] if coarse_terminal >= 0 else "cycle"])
	var model := Hydrology.new()
	if not model.has_method("drainage_heights"):
		_check(false, "drainage_heights(source: Image, size: Vector2i) is needed to retain high-resolution outlet evidence")
		quit(1)
		return
	var drainage: PackedFloat32Array = model.call("drainage_heights", source, size)
	_check(drainage.size() == size.x * size.y, "drainage sampling returns one elevation per target cell")
	if drainage.size() == size.x * size.y:
		_check(drainage[gate] < 0.21, "source-backed narrow outlet survives drainage sampling")
		var resolved := Hydrology.solve(drainage, sea, local, size, float(size.x - 1) / (size.y - 1))
		var terminal := _terminal(resolved, start)
		_check(terminal >= 0, "resolved drainage remains acyclic")
		if terminal >= 0:
			_check(resolved.terminal_kind[terminal] == "sea", "the source-backed valley outlet carries upstream flow to sea")
			_check(is_equal_approx(resolved.flow[terminal], 20.0), "the outlet preserves supplied flow")
		print("NARROW_OUTLET_RESOLVED gate=%.6f terminal=%d terminal_kind=%s" % [drainage[gate], terminal, resolved.terminal_kind[terminal] if terminal >= 0 else "cycle"])
	if not _failures.is_empty():
		quit(1)
		return
	print("HYDROLOGY_DRAINAGE_RESOLUTION_OK")
	quit()
