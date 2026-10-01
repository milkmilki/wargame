extends SceneTree

var checks := 0
var failures := 0


func _init() -> void:
	var state := GameState.new()
	check(state.has_method("record_campaign_offensive_failure"), "offensive failure record must exist")
	check(state.has_method("sync_campaign_pairs"), "cooldowns must belong to enemy component pairs")
	if not state.has_method("record_campaign_offensive_failure") or not state.has_method("sync_campaign_pairs"):
		finish()
		return
	for id in range(4):
		var nation := Nation.new()
		nation.id = id
		state.nations.append(nation)
	for a in range(4):
		for b in range(a + 1, 4):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.WAR)
	var first := state.war_id_between(0, 2)
	var second := state.war_id_between(1, 2)
	var third := state.war_id_between(0, 3)
	state.call("record_campaign_offensive_failure", first, [0] as Array[int], 160, [2] as Array[int])
	state.call("record_campaign_offensive_failure", second, [1] as Array[int], 180, [2] as Array[int])
	check(_deadline(state, first, [0], [2]) == 160, "single-member deadline")
	check(_deadline(state, first, [1], [2]) == -1, "other war is independent")
	state.merge_war_ids(first, second)
	state.merge_war_ids(first, third)
	check(_deadline(state, first, [0, 1], [2]) == 180, "merged component uses latest deadline")
	check(_deadline(state, first, [0], [2]) == 160, "split component inherits only its members")
	check(_deadline(state, second, [1], [2]) == -1, "merged war has no stale key")
	check(_deadline(state, first, [0], [3]) == -1, "same-war different opponent must not inherit another pair's defeat")
	state.call("record_campaign_offensive_failure", first, [0] as Array[int], 200, [3] as Array[int])
	check(_deadline(state, first, [0], [2]) == 160 and _deadline(state, first, [0], [3]) == 200,
		"same member can retain independent opponent-specific deadlines")
	check(_deadline(state, first, [2], [0]) == -1, "victorious opponent is not cooled by the loser's defeat")
	state.release_nation_war_pool(1, first)
	check(_deadline(state, first, [0, 1], [2]) == 160, "exiting member removes its record")
	state.day = 160
	state.call("prune_campaign_offensive_cooldowns")
	check(_deadline(state, first, [0], [2]) == -1 and _deadline(state, first, [0], [3]) == 200,
		"expired cooldown is removed without erasing another pair's active deadline")
	state.call("record_campaign_offensive_failure", first, [0] as Array[int], 220, [2] as Array[int])
	var sections := MapRenderer._nation_war_detail_sections(state, 0)
	check(sections.any(func(section: Dictionary) -> bool:
		return (section["lines"] as Array).any(func(line: String) -> bool:
			return line.contains("暂停新建进攻线") and line.contains("60天"))), "war panel explains defeat cooldown")
	var snapshot := NativeSnapshotBuilder.build(state)
	check(snapshot.has("campaign_pairs") and not snapshot.has("campaign_offensive_cooldowns"),
		"snapshot stores the pair's cooldown truth without a duplicate global table")
	var pair: Variant = state.call("find_campaign_pair", first, 0, 2)
	var saved_deadline := -1
	for record: Dictionary in snapshot.get("campaign_pairs", []):
		if pair != null and int(record["pair_id"]) == int(pair.get("pair_id")):
			for entry: Vector2i in record["cooldowns"]:
				if entry.x == 0:
					saved_deadline = entry.y
	check(saved_deadline == 220, "pair snapshot retains the actual member deadline losslessly")
	var before := JSON.stringify(snapshot.get("campaign_pairs", {}))
	check(before == JSON.stringify(NativeSnapshotBuilder.build(state).get("campaign_pairs", {})),
		"pair snapshot serialization is stable across repeated reads")
	state.call("record_campaign_offensive_failure", first, [0] as Array[int], 221, [2] as Array[int])
	check(before != JSON.stringify(NativeSnapshotBuilder.build(state).get("campaign_pairs", {})),
		"pair snapshot and deterministic state reflect changes to a cooldown deadline")
	state.release_war_pool(first)
	check((state.call("campaign_pairs_for_nation", 0, first) as Array).is_empty(),
		"war end removes pair-owned cooldowns and battlefields together")
	finish()


func _deadline(state: GameState, war_id: int, members: Array[int], opponents: Array[int]) -> int:
	return int(state.call("campaign_offensive_cooldown_until", war_id, members, opponents))


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("CAMPAIGN_OFFENSIVE_COOLDOWN_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
