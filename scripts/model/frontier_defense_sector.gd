class_name FrontierDefenseSector
extends RefCounted
## 持久边境防区。槽 0 固定为城市本体，后续槽按稳定顺序对应敌向边。

enum State {
	NORMAL,
	RECALLING,
	DEFENDING,
	RESTORING,
	RETREATING,
}

var city_id: int = -1
var owner_nation: int = -1
var topology_revision: int = -1
var state: int = State.NORMAL
var edge_neighbors: Array[int] = []
var assigned_army_ids: Array[int] = []


func configure(
	new_edge_neighbors: Array[int],
	revision: int
) -> void:
	var previous_by_edge := {}
	for edge_index in range(edge_neighbors.size()):
		var slot_index := edge_index + 1
		if slot_index < assigned_army_ids.size():
			previous_by_edge[edge_neighbors[edge_index]] = (
				assigned_army_ids[slot_index]
			)
	var city_army_id := assigned_army_at(0)
	edge_neighbors = new_edge_neighbors.duplicate()
	assigned_army_ids.resize(edge_neighbors.size() + 1)
	assigned_army_ids.fill(-1)
	assigned_army_ids[0] = city_army_id
	for edge_index in range(edge_neighbors.size()):
		assigned_army_ids[edge_index + 1] = int(
			previous_by_edge.get(edge_neighbors[edge_index], -1)
		)
	topology_revision = revision


func slot_count() -> int:
	return edge_neighbors.size() + 1


func edge_for_slot(slot_index: int) -> int:
	if slot_index <= 0 or slot_index > edge_neighbors.size():
		return -1
	return edge_neighbors[slot_index - 1]


func assigned_army_at(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= assigned_army_ids.size():
		return -1
	return assigned_army_ids[slot_index]


func assign(slot_index: int, army_id: int) -> void:
	if slot_index < 0 or slot_index >= assigned_army_ids.size():
		return
	assigned_army_ids[slot_index] = army_id


func clear_slot(slot_index: int) -> void:
	assign(slot_index, -1)


func clear_army(army_id: int) -> void:
	for slot_index in range(assigned_army_ids.size()):
		if assigned_army_ids[slot_index] == army_id:
			assigned_army_ids[slot_index] = -1
