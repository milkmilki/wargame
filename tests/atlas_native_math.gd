extends SceneTree
var failures := 0
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/atlas/math.gd"):
		print("ATLAS_NATIVE_MATH missing module"); quit(1); return
	var maths = load("res://scripts/atlas/math.gd")
	var references: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/atlas_native_rng.json"))
	for reference in references:
		var stream = maths.Stream.new(int(reference.seed))
		for expected in reference.values_u32:
			if int(stream.next()*4294967296.0) != int(expected): failures += 1
		if maths.sub_seed(int(reference.seed), "mesh") != int(reference.sub): failures += 1
		if int(maths.keyed(int(reference.seed),17,4,2)*4294967296.0) != int(reference.keyed_u32): failures += 1
	var heap = maths.Heap.new()
	heap.push(9,10.0); heap.push(2,1.0); heap.push(7,4.0)
	if heap.pop() != 2 or heap.pop() != 7 or heap.pop() != 9: failures += 1
	print("ATLAS_NATIVE_MATH failures=",failures)
	quit(1 if failures else 0)
