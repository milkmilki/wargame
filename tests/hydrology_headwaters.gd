extends SceneTree
## Visibility may extend a river toward its main headwater without inventing flow.
const Model = preload("res://scripts/core/vector_hydrology.gd")
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("HYDROLOGY_HEADWATERS_FAIL: ", message)

func _reach(downstream: int, area: float) -> Dictionary:
	return {"downstream_id": downstream, "catchment_area": area}

func _visibility(model: RefCounted, reaches: Array, flow: PackedFloat64Array, expected: PackedByteArray, label: String) -> void:
	var original_flow := flow.duplicate()
	var original_reaches := reaches.duplicate(true)
	var actual: PackedByteArray = model.call("visible_reaches", reaches, flow)
	_check(actual == expected, "%s visible flags actual=%s expected=%s" % [label, actual, expected])
	_check(flow == original_flow, label + " does not add or reclassify discharge")
	_check(reaches == original_reaches, label + " does not rewrite catchments or downstream topology")
	print("HEADWATER_DIAGNOSTIC fixture=%s visible=%s" % [label, actual])

func _build_classes() -> void:
	# Exercise actual feature construction: a newly visible low-flow reach must
	# remain minor, while the genuinely high-discharge reach remains major.
	var reaches: Array = []
	var x := [0.10, 0.30, 0.60, 0.90]
	for i in range(3):
		reaches.append({"downstream_id": i + 1 if i < 2 else -1, "catchment_area": 100.0 * (i + 1), "climate_cells": [i], "climate_areas": [1.0], "points": [[x[i], 0.43], [x[i + 1], 0.43]], "terminal_kind": "junction" if i < 2 else "sea"})
	var path := "headwaters-test-network"
	Model._networks[path] = {"network_id": path, "reaches": reaches, "basin_count": 0, "dem_size": [64, 64]}
	var environment := {"size": Vector2i(3, 2), "environment_id": path, "local_runoff": PackedFloat32Array([1.0, 39.0, 100.0, 0.0, 0.0, 0.0])}
	var source := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	source.fill(Color(1.0, 1.0, 1.0, 0.60))
	var result := Model.build(environment, 1.5, path, false, source)
	Model._networks.erase(path)
	var features: Array = result.features
	_check(features.size() == 3, "build includes the connected low-flow headwater")
	if features.size() == 3:
		_check(features[0].river_class == "minor", "visible one-unit headwater is not promoted to major")
		_check(features[1].river_class == "minor", "40-unit reach remains minor")
		_check(features[2].river_class == "major", "140-unit reach remains major")
		_check(features[0].downstream_id == 1 and features[1].downstream_id == 2, "visible extension keeps a complete downstream chain")
		for i in range(2):
			_check(features[i].points[-1].is_equal_approx(features[i + 1].points[0]), "headwater extension shares exact junction geometry with its downstream reach")
			_check(features[i + 1].upstream_ids.has(i), "headwater extension keeps reciprocal upstream links")
	print("HEADWATER_BUILD_DIAGNOSTIC features=", features.size())

func _run() -> void:
	var model := Model.new()
	if not model.has_method("visible_reaches"):
		_check(false, "visible_reaches(reaches, flow) is missing; low-flow main headwaters are currently discarded")
		quit(1)
		return
	# Two already-visible branches meet at a major downstream reach. Only the
	# larger low-flow catchment continues upstream from each visible branch.
	var reaches: Array = [_reach(1, 96), _reach(4, 160), _reach(4, 80), _reach(0, 70), _reach(5, 400), _reach(-1, 600), _reach(1, 40), _reach(-1, 100), _reach(5, 200), _reach(8, 80)]
	_visibility(model, reaches, PackedFloat64Array([2, 3, 1, 0, 40, 140, 1, 2, 35, 1]), PackedByteArray([1, 1, 0, 0, 1, 1, 0, 0, 1, 1]), "main_headwater_not_every_tributary")
	_visibility(model, [_reach(1, 100), _reach(2, 200), _reach(-1, 400)], PackedFloat64Array([0, 2, 40]), PackedByteArray([0, 1, 1]), "dry_source_stops_extension")
	_visibility(model, [_reach(1, 40), _reach(-1, 200)], PackedFloat64Array([1, 40]), PackedByteArray([0, 1]), "small_catchment_stops_extension")
	_visibility(model, [_reach(1, 100), _reach(-1, 200)], PackedFloat64Array([0.25, 40]), PackedByteArray([0, 1]), "insufficient_discharge_stops_extension")
	_visibility(model, [_reach(-1, 100)], PackedFloat64Array([2]), PackedByteArray([0]), "isolated_low_flow_does_not_become_river")
	_build_classes()
	if not _failures.is_empty():
		quit(1)
		return
	print("HYDROLOGY_HEADWATERS_OK")
	quit()
