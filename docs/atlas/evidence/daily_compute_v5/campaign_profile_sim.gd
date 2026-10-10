extends Simulation
var segments := {}
var requests := {}
func record(key: String, before: int):
	var entry: Dictionary = segments.get(key,{"calls":0,"us":0})
	entry.calls += 1;entry.us += Time.get_ticks_usec()-before;segments[key]=entry
func _prepare_coalition_campaign_batch() -> Array[Dictionary]:
	var before := Time.get_ticks_usec()
	var result := super._prepare_coalition_campaign_batch()
	record("prepare",before);return result
func _plan_coalition_component(component: Dictionary, defense_centers: Array[int], cache: Dictionary) -> bool:
	var before := Time.get_ticks_usec()
	var result := super._plan_coalition_component(component,defense_centers,cache)
	record("component",before);return result
func _plan_campaign_pair(pair: CoalitionCampaignPair, cache: Dictionary) -> bool:
	var before := Time.get_ticks_usec()
	var result := super._plan_campaign_pair(pair,cache)
	record("pair",before);return result
func _allocate_coalition_fronts(component: Dictionary) -> bool:
	var before := Time.get_ticks_usec()
	var result := super._allocate_coalition_fronts(component)
	record("allocation",before);return result
func _campaign_deployment_distance(army: Army,target: int) -> float:
	var before := Time.get_ticks_usec()
	var result := super._campaign_deployment_distance(army,target)
	record("deployment_distance",before);return result
func _cached_campaign_objective(nation_id: int,target_id: int,cache: Dictionary,excluded: Dictionary = {},counterattack: bool = false) -> Dictionary:
	var before := Time.get_ticks_usec()
	var result := super._cached_campaign_objective(nation_id,target_id,cache,excluded,counterattack)
	record("objective",before);return result
func _cached_ai_path_field(cache_nation_id: int,start: int,allowed_nation: int=-1,block_contested_edges: bool=false,use_danger_weight: bool=true,allowed_goal: int=-1,required_manpower: int=0) -> Dictionary:
	var cache: Dictionary = _ai_path_field_cache_by_nation.get(cache_nation_id,{})
	var keys := cache.keys()
	var old_context = cache.get("__atlas_context","")
	var before := Time.get_ticks_usec()
	var result := super._cached_ai_path_field(cache_nation_id,start,allowed_nation,block_contested_edges,use_danger_weight,allowed_goal,required_manpower)
	var elapsed := Time.get_ticks_usec()-before
	cache = _ai_path_field_cache_by_nation[cache_nation_id]
	var hit: bool = old_context==cache.get("__atlas_context","") and keys.has(cache.keys()[-1])
	var key := "hit" if hit else "miss"
	var entry: Dictionary = requests.get(key,{"calls":0,"us":0})
	entry.calls += 1;entry.us += elapsed; requests[key]=entry
	return result
