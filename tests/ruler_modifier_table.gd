extends SceneTree

const Reference = preload("res://tests/support/ruler_modifiers_reference.gd")
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func equal_reference(profile: Variant, traits: Array, label: String):
	check(var_to_bytes(RulerProfile.modifiers(profile,traits)) == var_to_bytes(Reference.modifiers(profile,traits)),label)
func run():
	var implementation := RulerProfile.new()
	check(implementation.has_method("_build_combined_modifiers"),"finite immutable modifier combinations are prepared before runtime")
	if not implementation.has_method("_build_combined_modifiers"):
		finish(); return
	for archetype in RulerProfile.ARCHETYPE_IDS + [-1,999]:
		equal_reference(archetype,[],"empty traits")
		for first in RulerProfile.TRAIT_IDS:
			equal_reference(archetype,[first],"one trait")
			equal_reference(archetype,[first,first,"unknown"],"normalization and duplicates")
			for second in RulerProfile.TRAIT_IDS:
				var pair: Array = [second,first]
				equal_reference(archetype,pair,"two traits, input order")
				equal_reference({"ruler_archetype":archetype,"ruler_traits":pair},[],"dictionary profile")
				var nation := Nation.new(); nation.ruler_archetype=archetype; nation.ruler_traits.assign(pair)
				equal_reference(nation,[],"object profile")
				equal_reference(nation,[first],"explicit trait override")
		var result := RulerProfile.modifiers(archetype,[RulerProfile.TRAIT_HARSH])
		result[RulerProfile.KEY_AGGRESSION] = -999
		result["caller_local"] = true
		equal_reference(archetype,[RulerProfile.TRAIT_HARSH],"callers cannot change stored combinations")
	for profile in [{}, {"ruler_traits":42}, {"ruler_traits":["invalid",17]}, {"ruler_traits":RulerProfile.TRAIT_IDS}]:
		equal_reference(profile,[],"invalid and truncated inputs")
	var mutable := Nation.new(); mutable.ruler_archetype = RulerProfile.MERCHANT
	for trait_id in RulerProfile.TRAIT_IDS:
		mutable.ruler_traits.assign([trait_id]); equal_reference(mutable,[],"live trait edits without revision changes")
	var jobs := []
	var tasks: Array[int] = []
	for slot in range(4):
		var job := {"slot":slot,"ok":true}; jobs.append(job)
		tasks.append(WorkerThreadPool.add_task(func():
			for iteration in range(500):
				var archetype := int(RulerProfile.ARCHETYPE_IDS[(iteration+slot)%RulerProfile.ARCHETYPE_IDS.size()])
				var traits: Array = [RulerProfile.TRAIT_IDS[iteration%RulerProfile.TRAIT_IDS.size()],
					RulerProfile.TRAIT_IDS[(iteration*7+slot+1)%RulerProfile.TRAIT_IDS.size()]]
				var output := RulerProfile.modifiers(archetype,traits)
				if var_to_bytes(output) != var_to_bytes(Reference.modifiers(archetype,traits)): job.ok=false
				output[RulerProfile.KEY_UPKEEP] = -999
		))
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	for job in jobs: check(job.ok,"parallel readers return independent mutable copies")
	finish()
func finish():
	for failure in failures: printerr("RULER_MODIFIER_TABLE_FAIL ",failure)
	print("RULER_MODIFIER_TABLE_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
