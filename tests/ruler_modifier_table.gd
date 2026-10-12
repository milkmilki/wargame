extends SceneTree

const Reference = preload("res://tests/support/ruler_modifiers_reference.gd")
var checks := 0
var failures: Array[String] = []
var scalar_api := RulerProfile.new()
const SCALARS := {
	"aggression_multiplier": RulerProfile.KEY_AGGRESSION,
	"peace_multiplier": RulerProfile.KEY_PEACE,
	"alliance_multiplier": RulerProfile.KEY_ALLIANCE,
	"food_output_multiplier": RulerProfile.KEY_FOOD_OUTPUT,
	"manpower_output_multiplier": RulerProfile.KEY_MANPOWER_OUTPUT,
	"upkeep_multiplier": RulerProfile.KEY_UPKEEP,
	"war_benefit_multiplier": RulerProfile.KEY_WAR_BENEFIT,
	"offensive_interval_multiplier": RulerProfile.KEY_OFFENSIVE_INTERVAL,
	"food_consumption_multiplier": RulerProfile.KEY_FOOD_CONSUMPTION,
	"attack_multiplier": RulerProfile.KEY_ATTACK,
	"morale_multiplier": RulerProfile.KEY_MORALE,
	"defense_multiplier": RulerProfile.KEY_DEFENSE,
	"city_defense_multiplier": RulerProfile.KEY_CITY_DEFENSE,
	"reserve_months_bonus": RulerProfile.KEY_RESERVE_MONTHS,
	"enfeoff_multiplier": RulerProfile.KEY_ENFEOFF,
	"centralize_multiplier": RulerProfile.KEY_CENTRALIZE,
	"trade_multiplier": RulerProfile.KEY_TRADE,
	"loyalty_multiplier": RulerProfile.KEY_LOYALTY,
}
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func equal_reference(profile: Variant, traits: Array, label: String):
	var expected: Dictionary = Reference.modifiers(profile,traits)
	check(var_to_bytes(RulerProfile.modifiers(profile,traits)) == var_to_bytes(expected),label)
	for method in SCALARS:
		var value: Variant = scalar_api.call(method,profile,traits)
		var reference: Variant = int(expected[SCALARS[method]]) if method == "reserve_months_bonus" else float(expected[SCALARS[method]])
		check(var_to_bytes(value) == var_to_bytes(reference), label+" exact scalar bytes: "+method)
func run():
	var implementation := RulerProfile.new()
	check(implementation.has_method("_modifier_value"),"scalar queries read the immutable table without allocating a mutable dictionary")
	if not implementation.has_method("_modifier_value"):
		finish(); return
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
	RulerProfile.scalar_modifiers_disabled_for_tests = true
	for archetype in RulerProfile.ARCHETYPE_IDS:
		equal_reference(archetype,[RulerProfile.TRAIT_HARSH],"debug scalar reference path")
	RulerProfile.scalar_modifiers_disabled_for_tests = false
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
				var reference: Dictionary = Reference.modifiers(archetype,traits)
				if var_to_bytes(output) != var_to_bytes(reference): job.ok=false
				for method in SCALARS:
					var expected: Variant = int(reference[SCALARS[method]]) if method == "reserve_months_bonus" else float(reference[SCALARS[method]])
					if var_to_bytes(scalar_api.call(method,archetype,traits)) != var_to_bytes(expected): job.ok=false
				output[RulerProfile.KEY_UPKEEP] = -999
		))
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	for job in jobs: check(job.ok,"parallel readers return independent mutable copies")
	finish()
func finish():
	for failure in failures: printerr("RULER_MODIFIER_TABLE_FAIL ",failure)
	print("RULER_MODIFIER_TABLE_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
