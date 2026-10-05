extends SceneTree
func _init() -> void:
	Combat.battle_log_enabled = false
	var heterogeneous := OS.get_cmdline_user_args().has("--heterogeneous")
	var rng := RandomNumberGenerator.new()
	var elapsed := 0
	var peak := 0
	for sample in range(13):
		var battles: Array[Battle] = []
		for index in range(200):
			var battle := Battle.new()
			for side in [battle.side_a, battle.side_b]:
				for member in range(6):
					var army := Army.new()
					army.size = 15000
					army.morale = 2
					if heterogeneous:
						army.size = 12000 + (member * 731 + index * 101) % 6000
						army.attack = 8 + member % 4
						army.defense = 8 + (member + index) % 4
						army.morale = 1.5 + member * 0.08
					side.append(army)
			battles.append(battle)
		rng.seed = 62012
		var start := Time.get_ticks_usec()
		for battle in battles:
			for round_index in range(10):
				CombatFixture.resolve_round(battle)
		var duration := Time.get_ticks_usec() - start
		if sample > 0:
			elapsed += duration
			peak = maxi(peak, duration)
	print("FUNDING_COMBAT_BENCH samples=12 rounds=2000 heterogeneous=%s avg_ms=%.3f peak_ms=%.3f" % [heterogeneous, elapsed / 12000.0, peak / 1000.0])
	quit()
