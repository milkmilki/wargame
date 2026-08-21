class_name CampaignAllocationPlan
extends RefCounted
## 国家级攻势的纯规划结果。战团归属是唯一真源；Nation 里的旧目标/军队
## Dictionary 只由 Simulation 原子投影，不能反向参与预算或目标选择。

var nation_id: int = -1
var generated_day: int = -1
var strict_group_readiness: bool = false
var requested_primary_city: int = -1
var primary_city: int = -1
var candidate_target_ids: Array[int] = []
var assigned_target_ids: Array[int] = []
var target_demands: Dictionary = {}       ## target_city -> demand Dictionary
var target_group_budget: Dictionary = {}  ## target_city -> desired group slots
var desired_group_count: int = 0          ## 未受16团上限截断的完整战区需求
var target_assigned_manpower: Dictionary = {} ## target_city -> planned manpower
var target_assigned_power: Dictionary = {}    ## target_city -> planned power
var group_to_target: Dictionary = {}      ## group_id -> target_city
var target_to_groups: Dictionary = {}     ## target_city -> Array[int]
var all_member_ids: Dictionary = {}       ## group_id -> Array[int]
var eligible_member_ids: Dictionary = {}  ## group_id -> Array[int]
var excluded_member_reasons: Dictionary = {} ## group_id -> {army_id -> reason}
var required_group_count: int = 0
var assigned_group_count: int = 0
var unfilled_group_slots: int = 0


func target_for_group(group_id: int) -> int:
	return int(group_to_target.get(group_id, -1))


func groups_for_target(target_city: int) -> Array[int]:
	var result: Array[int] = []
	result.assign(target_to_groups.get(target_city, []))
	return result


func member_ids_for_group(group_id: int) -> Array[int]:
	var result: Array[int] = []
	result.assign(eligible_member_ids.get(group_id, []))
	return result


func duplicate_plan() -> CampaignAllocationPlan:
	var copy := CampaignAllocationPlan.new()
	copy.nation_id = nation_id
	copy.generated_day = generated_day
	copy.strict_group_readiness = strict_group_readiness
	copy.requested_primary_city = requested_primary_city
	copy.primary_city = primary_city
	copy.candidate_target_ids.assign(candidate_target_ids)
	copy.assigned_target_ids.assign(assigned_target_ids)
	copy.target_demands = target_demands.duplicate(true)
	copy.target_group_budget = target_group_budget.duplicate(true)
	copy.desired_group_count = desired_group_count
	copy.target_assigned_manpower = target_assigned_manpower.duplicate(true)
	copy.target_assigned_power = target_assigned_power.duplicate(true)
	copy.group_to_target = group_to_target.duplicate(true)
	copy.target_to_groups = target_to_groups.duplicate(true)
	copy.all_member_ids = all_member_ids.duplicate(true)
	copy.eligible_member_ids = eligible_member_ids.duplicate(true)
	copy.excluded_member_reasons = excluded_member_reasons.duplicate(true)
	copy.required_group_count = required_group_count
	copy.assigned_group_count = assigned_group_count
	copy.unfilled_group_slots = unfilled_group_slots
	return copy


## 只比较规划语义，不比较对象身份，供确定性测试和调用方判断是否需要投影。
func same_allocation(other: CampaignAllocationPlan) -> bool:
	if other == null:
		return false
	return (
		nation_id == other.nation_id
		and strict_group_readiness == other.strict_group_readiness
		and requested_primary_city == other.requested_primary_city
		and primary_city == other.primary_city
		and candidate_target_ids == other.candidate_target_ids
		and assigned_target_ids == other.assigned_target_ids
		and target_demands == other.target_demands
		and target_group_budget == other.target_group_budget
		and desired_group_count == other.desired_group_count
		and target_assigned_manpower == other.target_assigned_manpower
		and target_assigned_power == other.target_assigned_power
		and group_to_target == other.group_to_target
		and target_to_groups == other.target_to_groups
		and all_member_ids == other.all_member_ids
		and eligible_member_ids == other.eligible_member_ids
		and excluded_member_reasons == other.excluded_member_reasons
		and required_group_count == other.required_group_count
		and assigned_group_count == other.assigned_group_count
		and unfilled_group_slots == other.unfilled_group_slots
	)
