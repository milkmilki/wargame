extends SceneTree
## 州域划分门禁。
##
## 保证：每个州至少两个城市（州治 + 至少一个属府），且每个州治都有一跳属府。
## 没有陆路连接的政治城市沿抢滩/水路/海路并入邻州，而不是自成一州。
##
## 唯一例外：只与码头相连的城市。码头在初始国家分配里是独立节点，穿过码头
## 的归属会让该城变成只能经过外国港口的飞地，因此这类城市保留自己的州。


func _init() -> void:
	var valid := _check_merged_fringe()
	valid = _check_linkless_city_keeps_own_state() and valid
	valid = _check_attachment_beats_distance() and valid
	valid = _check_inactive_city_stays_unassigned() and valid
	valid = _check_generated_world() and valid
	if valid:
		print("ADMINISTRATIVE_REGION_ANALYSIS_OK")
		quit(0)
		return
	push_error("ADMINISTRATIVE_REGION_ANALYSIS_FAILED")
	quit(1)


## 孤城有抢滩连接时并入邻州，并且结果与连边顺序无关。
func _check_merged_fringe() -> bool:
	var active := PackedInt32Array([0, 1, 2, 3, 4, 5, 6])
	var links: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3),
		Vector2i(3, 4), Vector2i(4, 5),
	]
	var positions := _line_positions(7)
	var attachment: Array[Vector2i] = [Vector2i(5, 6)]
	var result := AdministrativeRegionAnalysis.analyze(
		7, active, links, positions, attachment
	)
	var reversed_links := links.duplicate()
	reversed_links.reverse()
	var repeated := AdministrativeRegionAnalysis.analyze(
		7, active, reversed_links, positions, attachment
	)
	var region_ids: PackedInt32Array = result["region_ids"]
	var centers: PackedInt32Array = result["center_city_ids"]
	var hops: PackedInt32Array = result["hop_distances"]
	var valid: bool = (
		region_ids == repeated["region_ids"]
		and centers == repeated["center_city_ids"]
		and result["center_by_city"] == repeated["center_by_city"]
		and hops == repeated["hop_distances"]
		and not centers.has(6)
		and region_ids[6] == region_ids[5]
		and hops[6] == 1
		and hops[0] == 2
		and _states_have_fu(active, region_ids, centers, hops)
	)
	for link in links:
		valid = valid and not (
			centers.has(link.x) and centers.has(link.y)
		)
	return _report("merged_fringe", valid, str(result))


## 没有任何连接的城市保留自己的州：并入会让该州内部不可达。
func _check_linkless_city_keeps_own_state() -> bool:
	var active := PackedInt32Array([0, 1, 2, 3, 4, 5, 6])
	var links: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3),
		Vector2i(3, 4), Vector2i(4, 5),
	]
	var result := AdministrativeRegionAnalysis.analyze(
		7, active, links, _line_positions(7)
	)
	var region_ids: PackedInt32Array = result["region_ids"]
	var centers: PackedInt32Array = result["center_city_ids"]
	var hops: PackedInt32Array = result["hop_distances"]
	var valid: bool = (
		centers.has(6)
		and region_ids[6] != region_ids[5]
		and hops[6] == 0
		and hops[0] == 2
	)
	return _report("linkless_keeps_own_state", valid, str(result))


## 归属按连接关系决定，而不是按直线距离：4 号城地理上靠近 0 号城，
## 但只与 3 号城有抢滩连接。
func _check_attachment_beats_distance() -> bool:
	var active := PackedInt32Array([0, 1, 2, 3, 4])
	var links: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(2, 3),
	]
	var positions := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0),
		Vector2(10.0, 0.0), Vector2(11.0, 0.0),
		Vector2(0.2, 0.0),
	])
	var result := AdministrativeRegionAnalysis.analyze(
		5, active, links, positions, [Vector2i(3, 4)] as Array[Vector2i]
	)
	var region_ids: PackedInt32Array = result["region_ids"]
	var hops: PackedInt32Array = result["hop_distances"]
	var valid: bool = (
		region_ids[4] == region_ids[3]
		and region_ids[4] != region_ids[0]
		and hops[4] == 1
		and _states_have_fu(
			active, region_ids, result["center_city_ids"], hops
		)
	)
	return _report("attachment_beats_distance", valid, str(result))


## 非政治激活城市不获得州域归属。
func _check_inactive_city_stays_unassigned() -> bool:
	var boundary := AdministrativeRegionAnalysis.analyze(
		5,
		PackedInt32Array([0, 1, 3, 4]),
		[Vector2i(0, 1), Vector2i(3, 4)] as Array[Vector2i],
		_line_positions(5)
	)
	var ids: PackedInt32Array = boundary["region_ids"]
	var valid: bool = (
		ids[2] == -1
		and ids[0] == ids[1]
		and ids[3] == ids[4]
		and ids[1] != ids[3]
	)
	return _report("inactive_unassigned", valid, str(boundary))


## 真实地图：每个州都有属府，唯一例外是只与码头相连的城市。
func _check_generated_world() -> bool:
	var state := GameState.new()
	state.generate_world(94001)
	var active := PackedInt32Array()
	var max_hops := 0
	for city in state.cities:
		if not city.politically_active or city.is_dock:
			continue
		active.append(city.id)
		max_hops = maxi(
			max_hops, state.administrative_hop_distances[city.id]
		)
	var region_ids := state.administrative_region_ids
	var centers := state.administrative_center_city_ids
	var hops := state.administrative_hop_distances
	var sizes := {}
	var one_hop := {}
	var valid := max_hops <= 2
	for city_id in active:
		var region_id := region_ids[city_id]
		if region_id < 0:
			valid = false
			continue
		sizes[region_id] = int(sizes.get(region_id, 0)) + 1
		if hops[city_id] == 1:
			one_hop[region_id] = true
	var dock_fringe := 0
	for region_id in centers.size():
		if int(sizes.get(region_id, 0)) >= 2:
			valid = valid and one_hop.has(region_id)
			continue
		# 单城州只允许出现在"除码头外没有可管理邻居"的城市上。
		var allowed := _has_no_administrable_neighbor(
			state, int(centers[region_id])
		)
		dock_fringe += 1 if allowed else 0
		valid = valid and allowed
	return _report(
		"generated_world",
		valid,
		"regions=%d centers=%d dock_fringe=%d max_hops=%d"
		% [
			state.administrative_region_count,
			centers.size(), dock_fringe, max_hops,
		]
	)


## 每个州至少两个城市，且州治有一跳属府。只有活跃集合不足两城时才允许单城州。
func _states_have_fu(
	active: PackedInt32Array,
	region_ids: PackedInt32Array,
	centers: PackedInt32Array,
	hops: PackedInt32Array
) -> bool:
	if active.size() < 2:
		return true
	var sizes := {}
	var one_hop := {}
	for city_id in active:
		var region_id := region_ids[city_id]
		if region_id < 0:
			return false
		sizes[region_id] = int(sizes.get(region_id, 0)) + 1
		if hops[city_id] == 1:
			one_hop[region_id] = true
	for region_id in centers.size():
		if int(sizes.get(region_id, 0)) < 2:
			return false
		if not one_hop.has(region_id):
			return false
	return true


## 除码头外没有任何可管理的政治邻居，因此无法安全并入任何州。
func _has_no_administrable_neighbor(state: GameState, city_id: int) -> bool:
	for neighbor_id in state.neighbors(city_id):
		var neighbor := state.cities[neighbor_id]
		var edge := state.edge_of(city_id, neighbor_id)
		if (
			edge != null
			and edge.max_manpower > 0
			and neighbor.politically_active
			and not neighbor.is_dock
		):
			return false
	return true


func _line_positions(count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(count)
	for index in range(count):
		result[index] = Vector2(float(index), 0.0)
	return result


func _report(label: String, valid: bool, detail: String) -> bool:
	print("[%s] %s" % ["OK" if valid else "FAIL", label])
	if not valid:
		print("        ", detail)
	return valid
