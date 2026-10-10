extends SceneTree
const Codec=preload("res://.dbg/state_codec.gd")
var last_frame := 0
var frame_gaps: Array[float] = []
func _initialize(): call_deferred("run")
func frame():
	var now := Time.get_ticks_usec()
	if last_frame > 0: frame_gaps.append(float(now-last_frame)/1000.)
	last_frame = now
func run():
	var sim: Simulation=Codec.new().restore("res://.dbg/eurasia-frozen-day720.bin")
	root.add_child(sim);sim.paused=true;sim.runtime_stage_profiling_enabled=true
	var oracle := []
	for line in FileAccess.open("res://.dbg/eurasia-profile-prewar-after-0.jsonl",FileAccess.READ).get_as_text().split("\n"):
		if not line.is_empty(): oracle.append(JSON.parse_string(line))
	var rows := []
	process_frame.connect(frame)
	for warmup in range(28): sim._advance_day(false)
	for day in range(2):
		frame_gaps.clear(); last_frame = Time.get_ticks_usec()
		var before := Time.get_ticks_usec()
		await sim.advance_one_day()
		var elapsed := Time.get_ticks_usec()-before
		var digest := HashingContext.new();digest.start(HashingContext.HASH_SHA256)
		digest.update(var_to_bytes(NativeSnapshotBuilder.build(sim.state)))
		var hash_value := digest.finish().hex_encode()
		assert(hash_value==oracle[day+28].sha256,"Heavy-war synchronous vs frame runtime mismatch")
		frame_gaps.sort()
		rows.append({"day":sim.state.day,"elapsed_ms":float(elapsed)/1000.,"headless_frame_gaps_not_gui_fps":true,
			"max_frame_gap_ms":frame_gaps[-1] if not frame_gaps.is_empty() else 0.,
			"p95_frame_gap_ms":frame_gaps[floori((frame_gaps.size()-1)*.95)] if not frame_gaps.is_empty() else 0.,
			"runtime_spans_us":sim.runtime_span_peak_usec.duplicate(),"hash":hash_value})
		print(JSON.stringify(rows[-1]));last_frame=0
	process_frame.disconnect(frame)
	FileAccess.open("res://.dbg/eurasia-runtime-spans.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	sim.free();quit()
