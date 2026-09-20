class_name CityDefensePlan
extends RefCounted
## 州级战役系统的最小城市防守视图。
## 野战军只通过州战役绑定，不生成常态边境部署。

const MUST_HOLD_CITY_VALUE_FLOOR: float = 5.0

var view: AiWorldView
var snapshot: StrategicMapSnapshot
var threat: ThreatField

static func build(
	world_view: AiWorldView,
	strategic_snapshot: StrategicMapSnapshot,
	threat_field: ThreatField
) -> CityDefensePlan:
	var plan := CityDefensePlan.new()
	plan.view = world_view
	plan.snapshot = strategic_snapshot
	plan.threat = threat_field
	return plan


func can_redeploy(
	army: Army,
	_coordinator: ArmyCoordinator
) -> bool:
	return (
		army != null
		and view != null
		and view.day >= army.defensive_deployment_until_day
	)


func must_hold_city(city_id: int) -> bool:
	if view == null or city_id < 0 or city_id >= view.state.cities.size():
		return false
	var city := view.state.cities[city_id]
	return (
		city.owner_nation == view.nation_id
		and view.state.is_zhou_city(city_id)
		and (
			city.is_capital
			or city.id == view.capital_city_id
			or not view.state.wars_of(view.nation_id).is_empty()
		)
	)


func can_join_offensive(
	army: Army,
	_target_city: int,
	override_main_reserve_lock: bool = false
) -> bool:
	return (
		army != null
		and army.size > 0
		and (
			view == null
			or view.day >= army.defensive_deployment_until_day
			or override_main_reserve_lock
		)
	)


func urgent_defense_at(city_id: int) -> bool:
	return must_hold_city(city_id)


func requirement_at(city_id: int) -> float:
	if view == null or city_id < 0 or city_id >= view.state.cities.size():
		return 0.0
	var city := view.state.cities[city_id]
	return float(maxi(city.garrison_manpower, 0))
