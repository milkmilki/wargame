extends GameState
## Original conflict-aware alliance query, 2026-10-11 equivalence oracle.

func alliance_bloc(
	nation_id: int,
	alive_only: bool = true
) -> Array[int]:
	var result: Array[int] = []
	if (
		nation_id < 0
		or nation_id >= nations.size()
		or (alive_only and not nations[nation_id].alive)
	):
		return result
	var parent := PackedInt32Array()
	parent.resize(nations.size())
	parent.fill(-1)
	var components: Dictionary = {}
	for candidate_id in range(nations.size()):
		if alive_only and not nations[candidate_id].alive:
			continue
		parent[candidate_id] = candidate_id
		components[candidate_id] = [candidate_id] as Array[int]
	# (a,b) 以字典序遍历，所以在矛盾联盟图上选择保留哪条盟约也不依赖调用者。
	for nation_a in range(nations.size()):
		if parent[nation_a] < 0:
			continue
		for nation_b in range(nation_a + 1, nations.size()):
			if (
				parent[nation_b] < 0
				or relation_between(nation_a, nation_b)
					!= DiplomaticRelation.ALLIED
			):
				continue
			var root_a := nation_a
			while parent[root_a] != root_a:
				root_a = parent[root_a]
			var root_b := nation_b
			while parent[root_b] != root_b:
				root_b = parent[root_b]
			if root_a == root_b:
				continue
			var blocked := false
			for member_a in components[root_a]:
				for member_b in components[root_b]:
					if is_enemy(int(member_a), int(member_b)):
						blocked = true
						break
				if blocked:
					break
			if blocked:
				continue
			var kept_root := mini(root_a, root_b)
			var merged_root := maxi(root_a, root_b)
			var merged: Array[int] = []
			for member in components[kept_root]:
				merged.append(int(member))
			for member in components[merged_root]:
				merged.append(int(member))
			merged.sort()
			parent[merged_root] = kept_root
			components[kept_root] = merged
			components.erase(merged_root)
	var nation_root := nation_id
	while parent[nation_root] != nation_root:
		nation_root = parent[nation_root]
	for member in components[nation_root]:
		result.append(int(member))
	return result


# ------------------------------------------------------------------ 宗藩关系
# 宗藩平时仍是对外联盟共同体；当宗主直辖法理陆城占比过低时，藩王可发动
# 严格双边的私人战争。战争作用域由 war_objectives 标记，联盟同步不得传播私人战争边。

## 藩王的宗主 id；不是藩王返回 -1。
func overlord_of(nation_id: int) -> int:
	var record: Dictionary = suzerainty.get(nation_id, {})
	return int(record.get("overlord_id", -1)) if not record.is_empty() else -1


## 直接藩王 id 列表（不含更下级），按 id 升序，确定性。
func subjects_of(overlord_id: int) -> Array[int]:
	var result: Array[int] = []
	for subject_id in suzerainty:
		if int(suzerainty[subject_id].get("overlord_id", -1)) == overlord_id:
			result.append(int(subject_id))
	result.sort()
	return result


## 藩王关系记录副本；不是藩王返回空字典。
func suzerainty_record(subject_id: int) -> Dictionary:
	return (suzerainty.get(subject_id, {}) as Dictionary).duplicate()
