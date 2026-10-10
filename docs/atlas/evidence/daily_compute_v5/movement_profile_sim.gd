extends Simulation
var travel_calls := 0
var edge_unit_calls := 0
var events := 0
var arrivals := 0
var travel_us := 0
var edge_unit_us := 0
var encounter_us := 0
var block_us := 0
var junction_us := 0
func _is_travelling(army: Army) -> bool:
	travel_calls += 1
	var before := Time.get_ticks_usec()
	var result := super._is_travelling(army)
	travel_us += Time.get_ticks_usec()-before
	return result
func _is_edge_unit(army: Army) -> bool:
	edge_unit_calls += 1
	var before := Time.get_ticks_usec()
	var result := super._is_edge_unit(army)
	edge_unit_us += Time.get_ticks_usec()-before
	return result
func _resolve_movement_contacts(holding: Array[Army], groups: Variant = null) -> void:
	events += 1
	super._resolve_movement_contacts(holding,groups)
func _detect_encounters(groups: Variant = null) -> void:
	var before := Time.get_ticks_usec()
	super._detect_encounters(groups)
	encounter_us += Time.get_ticks_usec()-before
func _block_passthrough() -> void:
	var before := Time.get_ticks_usec()
	super._block_passthrough()
	block_us += Time.get_ticks_usec()-before
func _detect_atlas_junction_contacts(candidates: Variant = null) -> void:
	var before := Time.get_ticks_usec()
	super._detect_atlas_junction_contacts(candidates)
	junction_us += Time.get_ticks_usec()-before
func _arrive_at_node(army: Army) -> void:
	arrivals += 1
	super._arrive_at_node(army)
