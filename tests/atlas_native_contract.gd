extends SceneTree

var failures := 0

func _initialize() -> void:
	var path := "res://scripts/atlas/native_map.gd"
	if not ResourceLoader.exists(path):
		print("ATLAS_NATIVE_CONTRACT FAIL: native map module missing")
		quit(1)
		return
	var maps = load(path)
	var example := {"format": "atlas-native-map", "version": 1, "seed": 1,
		"mesh": {"xyz": [1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0],
			"x": [0.0,1.0,2.0], "y": [0.0,1.0,2.0], "triangles": [0,1,2],
			"adj_start": [0,2,4,6], "adj": [1,2,0,2,0,1]},
		"environment": {"elevation": [10.0,20.0,-10.0], "water": [0,0,1],
			"suitability": [5.0,0.5,0.0]},
		"regions": {"of": [0,1,-1], "seat": [0,1], "area": [1.0,1.0],
			"capacity": [5.0,0.5]},
		"cities": [{"cell":0,"region":0,"major":true}], "roads": [],
		"ownership": [0,1], "nations": [{"name":"甲"},{"name":"乙"}]}
	check(maps.validate(example).is_empty(), "valid native map")
	var encoded: String = maps.encode(example)
	var copy: Dictionary = maps.decode(encoded)
	check(copy == example, "snapshot round trip preserves all data")
	copy.seed = 7
	check(example.seed == 1, "snapshot has independent storage")
	var broken: Dictionary = example.duplicate(true)
	broken.regions.of[0] = 4
	check(not maps.validate(broken).is_empty(), "out of range province rejected")
	broken = example.duplicate(true)
	broken.mesh.adj[0] = 100
	check(not maps.validate(broken).is_empty(), "out of range mesh adjacency rejected")
	broken = example.duplicate(true)
	broken.cities[0].cell = 2
	check(not maps.validate(broken).is_empty(), "sea city rejected")
	check(maps.decode("{bad").is_empty(), "invalid JSON rejected")
	print("ATLAS_NATIVE_CONTRACT failures=", failures)
	quit(1 if failures else 0)

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", description)
