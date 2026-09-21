extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94002)
	var center_id := int(state.administrative_center_city_ids[0])
	var center := state.cities[center_id]
	var attacker := (center.owner_nation + 1) % state.nations.size()
	center.garrison_manpower = 15000
	for member_id in state.administrative_members(center_id):
		if member_id != center_id:
			state.cities[member_id].owner_nation = center.owner_nation
	var requirement_full := state.campaign_siege_requirement(attacker, center_id)
	var defense_full := state.city_garrison_defense_bonus(attacker, center_id)
	var share_full := state.administrative_campaign_control_share(
		attacker, center_id
	)
	for member_id in state.administrative_members(center_id):
		if member_id != center_id:
			state.cities[member_id].owner_nation = attacker
	var requirement_encircled := state.campaign_siege_requirement(
		attacker, center_id
	)
	var defense_encircled := state.city_garrison_defense_bonus(
		attacker, center_id
	)
	var share_encircled := state.administrative_campaign_control_share(
		attacker, center_id
	)
	var valid := (
		is_equal_approx(share_full, 0.0)
		and is_equal_approx(defense_full, 3.0)
		and requirement_full == 45000
		and is_equal_approx(share_encircled, 1.0)
		and is_equal_approx(defense_encircled, 1.0)
		and requirement_encircled == 15000
	)
	if valid:
		print("ADMINISTRATIVE_COMBAT_OK")
		quit(0)
		return
	push_error(
		"ADMINISTRATIVE_COMBAT_FAILED F=%.2f/%.2f D=%.2f/%.2f R=%d/%d"
		% [
			share_full, share_encircled,
			defense_full, defense_encircled,
			requirement_full, requirement_encircled,
		]
	)
	quit(1)
