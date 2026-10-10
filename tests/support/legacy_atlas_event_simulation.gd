# Pre-preparation Atlas event scan; regression oracle only.
extends Simulation

func _advance_atlas_movement(spread_runtime_work: bool = false) -> void:
	# Integrate the day at global arrival/contact events. Every army consumes the
	# same elapsed time; junctions do not add a turn or allow an encounter bypass.
	var remaining := 1.; var stalled := {}
	for army in state.armies:
		if army.encounter_blocked: stalled[army.id] = true; army.encounter_blocked = false
	var iterations := 0
	var slice_started := Time.get_ticks_usec() if spread_runtime_work else 0
	while remaining>.0000001:
		var event_part_started := Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
		iterations += 1
		assert(iterations<=state.cities.size()*2+state.armies.size()+1,"Non-progressing traffic traversal")
		var moving: Array[Army] = []; var moving_days := PackedFloat64Array(); var dt := remaining
		for army in state.armies:
			if stalled.has(army.id) or not _is_travelling(army) or army.size<=0: continue
			if army.move_to<0: _begin_next_leg(army)
			if army.move_to<0: stalled[army.id] = true; continue
			var days := edge_travel_days(state.edge_of(army.move_from,army.move_to),army.max_size)
			var target := army.hold_target_progress if army.state==Army.State.MOVING and army.hold_target_progress>=0. else 1.
			dt = minf(dt,maxf(0.,target-army.move_progress)*days); moving.append(army); moving_days.append(days)
		_record_tick_profile_stage("atlas_event_scan", event_part_started)
		if moving.is_empty(): break
		event_part_started = Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
		var holding: Array[Army] = []
		for moving_index in range(moving.size()):
			var army := moving[moving_index]
			army.move_progress += dt/moving_days[moving_index]
			if army.state==Army.State.MOVING and army.hold_target_progress>=0. and army.move_progress>=army.hold_target_progress:
				army.move_progress = army.hold_target_progress; holding.append(army)
		remaining -= dt
		_record_tick_profile_stage("atlas_event_integrate", event_part_started)
		event_part_started = Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
		_resolve_movement_contacts(holding)
		_detect_atlas_junction_contacts()
		_record_tick_profile_stage("atlas_event_contacts", event_part_started)
		event_part_started = Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
		var changed := false
		for army in moving:
			if army.encounter_blocked: stalled[army.id] = true; continue
			if not _is_travelling(army) or army.move_to<0 or army.move_progress<1.-.0000001: continue
			army.move_progress = 1.; _arrive_at_node(army); changed = true
		if dt<=.0000001 and not changed:
			for army in moving: stalled[army.id] = true
		_record_tick_profile_stage("atlas_event_arrivals", event_part_started)
		# A whole arrival/contact event is atomic. Rendering may run between
		# events, while every army still receives exactly the same elapsed time.
		if spread_runtime_work and Time.get_ticks_usec() - slice_started >= AI_RUNTIME_SLICE_BUDGET_USEC:
			await get_tree().process_frame
			slice_started = Time.get_ticks_usec()

