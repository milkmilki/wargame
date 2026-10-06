class_name MilitaryReachability
extends RefCounted
## Read-only deployment reachability. Planned factions never alter live diplomacy.

static func prewar_entries(state: GameState, nation: int, objective: int, cache: Dictionary = {}) -> Array[int]:
	return DiplomacyAI.war_preparation_staging_cities(state, nation, objective, cache)

static func contact(state: GameState, actors: Array, opponents: Array, participants: Array) -> bool:
	for actor in actors:
		var reachable := planned_reachable(state, int(actor), actors, participants)
		for city in state.cities:
			if city.is_dock or not city.politically_active or not opponents.has(city.owner_nation):
				continue
			if not planned_entries(state, city.id, int(actor), actors, participants, reachable).is_empty():
				return true
	return false

static func _access(state: GameState, actor: int, owner: int, friends: Array, participants: Array) -> bool:
	return friends.has(owner) if participants.has(owner) else state.has_military_access(actor, owner)

static func planned_reachable(state: GameState, actor: int, friends: Array, participants: Array) -> Dictionary:
	var reached := {}
	var queue: Array[int] = []
	for city in state.cities:
		if city.owner_nation == actor and city.politically_active and not city.is_dock:
			reached[city.id] = true
			queue.append(city.id)
	for army in state.armies:
		var node := army.move_to if army.on_edge else army.location_city
		if army.owner_nation == actor and army.size > 0 and node >= 0 and node < state.cities.size() and _access(state, actor, state.cities[node].owner_nation, friends, participants) and not reached.has(node):
			reached[node] = true
			queue.append(node)
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor in state.neighbors(current):
			var edge := state.edge_of(current, neighbor)
			if edge != null and edge.max_manpower > 0 and not reached.has(neighbor) and _access(state, actor, state.cities[neighbor].owner_nation, friends, participants):
				reached[neighbor] = true
				queue.append(neighbor)
		# Local crossings can pass an enemy-owned dock, but never a river chain.
		for neighbor in state.territorial_border_neighbors(current):
			if reached.has(neighbor) or not _access(state, actor, state.cities[neighbor].owner_nation, friends, participants): continue
			var edges := state.territorial_border_support_edges(current, neighbor)
			if edges.size() == 2 and edges[0].kind == Edge.Kind.LANDING and edges[1].kind == Edge.Kind.LANDING and edges[0].max_manpower > 0 and edges[1].max_manpower > 0:
				reached[neighbor] = true
				queue.append(neighbor)
	return reached

static func planned_entries(state: GameState, objective: int, actor: int, friends: Array, participants: Array, reached: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for neighbor in state.neighbors(objective):
		var edge := state.edge_of(neighbor, objective)
		if edge != null and edge.max_manpower > 0 and reached.has(neighbor) and _access(state, actor, state.cities[neighbor].owner_nation, friends, participants): result.append(neighbor)
	for neighbor in state.territorial_border_neighbors(objective):
		var edges := state.territorial_border_support_edges(neighbor, objective)
		if reached.has(neighbor) and not result.has(neighbor) and edges.size() == 2 and edges[0].kind == Edge.Kind.LANDING and edges[1].kind == Edge.Kind.LANDING and edges[0].max_manpower > 0 and edges[1].max_manpower > 0:
			result.append(neighbor)
	if not result.is_empty(): return result
	# Reverse water traversal, limited to the opponent's docks and lawful transit.
	var target := state.cities[objective].owner_nation
	var docks := {}
	var queue: Array[int] = []
	for neighbor in state.neighbors(objective):
		var edge := state.edge_of(objective, neighbor)
		if edge != null and edge.kind == Edge.Kind.LANDING and edge.max_manpower > 0 and state.cities[neighbor].is_dock and state.cities[neighbor].owner_nation == target:
			docks[neighbor] = true
			queue.append(neighbor)
	var cursor := 0
	while cursor < queue.size():
		var dock := queue[cursor]
		cursor += 1
		if reached.has(dock) and _access(state, actor, state.cities[dock].owner_nation, friends, participants): result.append(dock)
		for neighbor in state.neighbors(dock):
			var edge := state.edge_of(dock, neighbor)
			if docks.has(neighbor) or not state.cities[neighbor].is_dock or edge == null or edge.max_manpower <= 0 or edge.kind not in [Edge.Kind.RIVER, Edge.Kind.SEA]: continue
			if state.cities[neighbor].owner_nation != target and not _access(state, actor, state.cities[neighbor].owner_nation, friends, participants): continue
			docks[neighbor] = true
			queue.append(neighbor)
	return result
