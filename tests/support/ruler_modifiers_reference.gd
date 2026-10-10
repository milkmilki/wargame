extends RefCounted
## 君主性格与修正的确定性唯一真源。
##
## 本类不持有状态，也不读取 GameState.rng。君主原型、特质和姓名只由
## (world_seed, nation.id, domain, salt) 的稳定哈希决定。除储备月数为加法修正、
## offensive_allowed 为布尔门控、宫廷耗费为固定比例外，公开修正均为以1.0为中性的倍率。

enum Archetype {
	BALANCED,
	CONQUEROR,
	GUARDIAN,
	INEPT,
	TYRANT,
	MERCHANT,
	REFORMER,
	DIPLOMAT,
	BUILDER,
	PUPPET,
}

## 本地定义贸易政策值，避免依赖尚未落地的外部枚举。
## 数值与贸易系统约定保持一致，但此文件不引用 TradeNetwork，因而可独立解析。
enum TradePolicy {
	BALANCED,
	GOLD,
	FOOD,
	ISOLATION,
}

const MAX_TRAITS: int = 2
const CONQUEROR_COMBAT_MULTIPLIER: float = 5.0
const CONQUEROR_CAMPAIGN_REQUIREMENT_MULTIPLIER: float = 0.5

static var _archetype_base_modifiers: Dictionary = _build_archetype_base_modifiers()

## 常用裸常量别名，调用方既可写 RulerProfile.CONQUEROR，也可使用
## RulerProfile.Archetype.CONQUEROR。
const BALANCED: int = Archetype.BALANCED
const CONQUEROR: int = Archetype.CONQUEROR
const GUARDIAN: int = Archetype.GUARDIAN
const INEPT: int = Archetype.INEPT
const TYRANT: int = Archetype.TYRANT
const MERCHANT: int = Archetype.MERCHANT
const REFORMER: int = Archetype.REFORMER
const DIPLOMAT: int = Archetype.DIPLOMAT
const BUILDER: int = Archetype.BUILDER
const PUPPET: int = Archetype.PUPPET

const POLICY_BALANCED: int = TradePolicy.BALANCED
const POLICY_GOLD: int = TradePolicy.GOLD
const POLICY_FOOD: int = TradePolicy.FOOD
const POLICY_ISOLATION: int = TradePolicy.ISOLATION

const TRAIT_AMBITIOUS: String = "ambitious"
const TRAIT_CAUTIOUS: String = "cautious"
const TRAIT_CHARISMATIC: String = "charismatic"
const TRAIT_FRUGAL: String = "frugal"
const TRAIT_DILIGENT: String = "diligent"
const TRAIT_LOGISTICIAN: String = "logistician"
const TRAIT_MARTIAL: String = "martial"
const TRAIT_FORTIFIER: String = "fortifier"
const TRAIT_MERCANTILE: String = "mercantile"
const TRAIT_CENTRALIZER: String = "centralizer"
const TRAIT_FEUDALIST: String = "feudalist"
const TRAIT_HARSH: String = "harsh"

const ARCHETYPE_IDS: Array[int] = [
	Archetype.BALANCED,
	Archetype.CONQUEROR,
	Archetype.GUARDIAN,
	Archetype.INEPT,
	Archetype.TYRANT,
	Archetype.MERCHANT,
	Archetype.REFORMER,
	Archetype.DIPLOMAT,
	Archetype.BUILDER,
	Archetype.PUPPET,
]

const TRAIT_IDS: Array[String] = [
	TRAIT_AMBITIOUS,
	TRAIT_CAUTIOUS,
	TRAIT_CHARISMATIC,
	TRAIT_FRUGAL,
	TRAIT_DILIGENT,
	TRAIT_LOGISTICIAN,
	TRAIT_MARTIAL,
	TRAIT_FORTIFIER,
	TRAIT_MERCANTILE,
	TRAIT_CENTRALIZER,
	TRAIT_FEUDALIST,
	TRAIT_HARSH,
]

const ARCHETYPE_NAMES: Dictionary = {
	Archetype.BALANCED: "持衡者",
	Archetype.CONQUEROR: "征服者",
	Archetype.GUARDIAN: "守成者",
	Archetype.INEPT: "庸主",
	Archetype.TYRANT: "暴君",
	Archetype.MERCHANT: "商君",
	Archetype.REFORMER: "改革者",
	Archetype.DIPLOMAT: "纵横家",
	Archetype.BUILDER: "营造者",
	Archetype.PUPPET: "傀儡君主",
}

const ARCHETYPE_DESCRIPTIONS: Dictionary = {
	Archetype.BALANCED: "行事稳健，各项国政均衡，没有明显长处或短板。",
	Archetype.CONQUEROR: "崇尚武功，军队基础攻防提高至五倍，以半数州战役需求发动攻势，并能以更低成本维持强军。",
	Archetype.GUARDIAN: "专注守土与积储，城防坚固，不会主动发动攻势。",
	Archetype.INEPT: "才具平庸，生产、军备与外交皆受拖累，也无力组织主动攻势。",
	Archetype.TYRANT: "以高压征集兵员，热衷集权，宫廷与腐败耗费较高，并损害民心、外交与长期稳定。",
	Archetype.MERCHANT: "重视通商和财政，擅长以较低成本维持国家，但军事动员较弱。",
	Archetype.REFORMER: "整饬制度、提升生产和征募效率，并倾向收拢中央权力。",
	Archetype.DIPLOMAT: "长于议和、结盟与贸易，不会主动发动攻势，但正面作战稍弱。",
	Archetype.BUILDER: "经营粮产、工事和长期储备，扩张欲较低而国土防御出色。",
	Archetype.PUPPET: "畏惧直辖重负，会不断把边疆分封给藩王，只保留首都附近的核心领土。",
}

const TRAIT_NAMES: Dictionary = {
	TRAIT_AMBITIOUS: "雄心勃勃",
	TRAIT_CAUTIOUS: "谨慎",
	TRAIT_CHARISMATIC: "富有魅力",
	TRAIT_FRUGAL: "节俭",
	TRAIT_DILIGENT: "勤政",
	TRAIT_LOGISTICIAN: "善理粮秣",
	TRAIT_MARTIAL: "尚武",
	TRAIT_FORTIFIER: "筑城能手",
	TRAIT_MERCANTILE: "精于商贸",
	TRAIT_CENTRALIZER: "集权倾向",
	TRAIT_FEUDALIST: "分封倾向",
	TRAIT_HARSH: "严酷",
}

const TRAIT_DESCRIPTIONS: Dictionary = {
	TRAIT_AMBITIOUS: "更愿开战、较难议和，并积极推动集权。",
	TRAIT_CAUTIOUS: "降低进攻意愿，偏好议和、守备和额外储备，完成经营区域后不再转向新区。",
	TRAIT_CHARISMATIC: "更易缔结联盟，也更能维持军队士气。",
	TRAIT_FRUGAL: "降低军费，并多留一个月的钱粮储备；不改变固定宫廷耗费比例。",
	TRAIT_DILIGENT: "小幅提升粮食和人力产出。",
	TRAIT_LOGISTICIAN: "提高粮产、降低军粮消耗，并增加两个月储备。",
	TRAIT_MARTIAL: "提高进攻意愿、士气和野战防御。",
	TRAIT_FORTIFIER: "偏重守势，强化野战防御、城防和储备。",
	TRAIT_MERCANTILE: "提高贸易收益，也略有助于结盟。",
	TRAIT_CENTRALIZER: "偏好削藩，排斥分封，并略微改善人力征集。",
	TRAIT_FEUDALIST: "偏好分封、排斥削藩，并略微改善地方防御。",
	TRAIT_HARSH: "以强硬手段增加人力，但不利议和、结盟与士气。",
}

const TRADE_POLICY_NAMES: Dictionary = {
	TradePolicy.BALANCED: "均衡贸易",
	TradePolicy.GOLD: "重商贸易",
	TradePolicy.FOOD: "粮食优先",
	TradePolicy.ISOLATION: "闭关自守",
}

const KEY_AGGRESSION: String = "aggression_multiplier"
const KEY_PEACE: String = "peace_multiplier"
const KEY_ALLIANCE: String = "alliance_multiplier"
const KEY_FOOD_OUTPUT: String = "food_output_multiplier"
const KEY_MANPOWER_OUTPUT: String = "manpower_output_multiplier"
const KEY_UPKEEP: String = "upkeep_multiplier"
const KEY_WAR_BENEFIT: String = "war_benefit_multiplier"
const KEY_OFFENSIVE_INTERVAL: String = "offensive_interval_multiplier"
const KEY_FOOD_CONSUMPTION: String = "food_consumption_multiplier"
const KEY_ATTACK: String = "attack_multiplier"
const KEY_MORALE: String = "morale_multiplier"
const KEY_DEFENSE: String = "defense_multiplier"
const KEY_CITY_DEFENSE: String = "city_defense_multiplier"
const KEY_RESERVE_MONTHS: String = "reserve_months_bonus"
const KEY_ENFEOFF: String = "enfeoff_multiplier"
const KEY_CENTRALIZE: String = "centralize_multiplier"
const KEY_TRADE: String = "trade_multiplier"
const KEY_OFFENSIVE_ALLOWED: String = "offensive_allowed"
const KEY_LOYALTY: String = "loyalty_multiplier"

const HASH_MODULUS: int = 2147483647
const HASH_MULTIPLIER: int = 48271
const HASH_INITIAL: int = 216613626
const DAYS_PER_YEAR: int = 360
const MIN_REIGN_YEARS: int = 1
const MAX_REIGN_YEARS: int = 60
## Inclusive minimum, maximum and percentage weight for each reign bucket.
const REIGN_YEAR_BUCKETS: Array[Vector3i] = [
	Vector3i(1, 4, 20), Vector3i(5, 9, 20), Vector3i(10, 19, 30),
	Vector3i(20, 29, 15), Vector3i(30, 39, 8), Vector3i(40, 49, 4),
	Vector3i(50, 60, 3),
]

## 初始化一国君主。salt 只用于隔离稳定哈希域；初始就任日统一为 0。
## 分封、叛军或继位产生的君主由调用方在初始化后覆写实际就任日。


static func modifiers(
	profile_or_archetype: Variant,
	traits: Array = []
) -> Dictionary:
	var archetype := _resolved_archetype(profile_or_archetype)
	var result := _base_modifiers(archetype).duplicate()
	for trait_id in _resolved_traits(profile_or_archetype, traits):
		_apply_trait(result, trait_id)
	return result


static func is_valid_archetype(archetype: int) -> bool:
	return ARCHETYPE_IDS.has(archetype)


static func is_valid_trait(trait_id: String) -> bool:
	return TRAIT_IDS.has(trait_id)


static func _base_modifiers(archetype: int) -> Dictionary:
	return _archetype_base_modifiers.get(archetype, _archetype_base_modifiers[Archetype.BALANCED])


static func _build_archetype_base_modifiers() -> Dictionary:
	var profiles := {}
	for archetype in ARCHETYPE_IDS:
		var base := _build_base_modifiers(archetype)
		base.make_read_only()
		profiles[archetype] = base
	profiles.make_read_only()
	return profiles


static func _build_base_modifiers(archetype: int) -> Dictionary:
	var result := {
		KEY_AGGRESSION: 1.0,
		KEY_PEACE: 1.0,
		KEY_ALLIANCE: 1.0,
		KEY_FOOD_OUTPUT: 1.0,
		KEY_MANPOWER_OUTPUT: 1.0,
		KEY_UPKEEP: 1.0,
		KEY_WAR_BENEFIT: 1.0,
		KEY_OFFENSIVE_INTERVAL: 1.0,
		KEY_FOOD_CONSUMPTION: 1.0,
		KEY_ATTACK: 1.0,
		KEY_MORALE: 1.0,
		KEY_DEFENSE: 1.0,
		KEY_CITY_DEFENSE: 1.0,
		KEY_RESERVE_MONTHS: 0,
		KEY_ENFEOFF: 1.0,
		KEY_CENTRALIZE: 1.0,
		KEY_TRADE: 1.0,
		KEY_OFFENSIVE_ALLOWED: true,
		KEY_LOYALTY: 1.0,
	}
	match _normalized_archetype(archetype):
		Archetype.CONQUEROR:
			_set_multipliers(result, {
				KEY_AGGRESSION: 2.00, KEY_PEACE: 0.45, KEY_ALLIANCE: 0.80,
				KEY_MANPOWER_OUTPUT: 1.50, KEY_UPKEEP: 0.50,
				KEY_WAR_BENEFIT: 2.00, KEY_OFFENSIVE_INTERVAL: 0.50,
				KEY_ATTACK: CONQUEROR_COMBAT_MULTIPLIER, KEY_MORALE: 2.00,
				KEY_DEFENSE: CONQUEROR_COMBAT_MULTIPLIER,
				KEY_ENFEOFF: 0.55, KEY_CENTRALIZE: 1.50,
			})
			result[KEY_RESERVE_MONTHS] = -3
		Archetype.GUARDIAN:
			_set_multipliers(result, {
				KEY_AGGRESSION: 0.35, KEY_PEACE: 1.80, KEY_ALLIANCE: 1.20,
				KEY_FOOD_OUTPUT: 1.35,
				KEY_MANPOWER_OUTPUT: 0.85, KEY_UPKEEP: 0.75,
				KEY_FOOD_CONSUMPTION: 0.70, KEY_MORALE: 1.25,
				KEY_DEFENSE: 1.60, KEY_CITY_DEFENSE: 2.00,
				KEY_ENFEOFF: 1.20, KEY_CENTRALIZE: 0.80, KEY_TRADE: 2.00,
			})
			result[KEY_RESERVE_MONTHS] = 8
			result[KEY_OFFENSIVE_ALLOWED] = false
		Archetype.INEPT:
			_set_multipliers(result, {
				KEY_AGGRESSION: 0.30, KEY_PEACE: 1.40, KEY_ALLIANCE: 0.50,
				KEY_FOOD_OUTPUT: 0.55,
				KEY_MANPOWER_OUTPUT: 0.50, KEY_UPKEEP: 1.80,
				KEY_FOOD_CONSUMPTION: 1.50, KEY_MORALE: 0.50,
				KEY_DEFENSE: 0.50, KEY_CITY_DEFENSE: 0.55,
				KEY_ENFEOFF: 1.80, KEY_CENTRALIZE: 0.30, KEY_TRADE: 0.50,
			})
			result[KEY_LOYALTY] = 0.45
			result[KEY_RESERVE_MONTHS] = -6
			result[KEY_OFFENSIVE_ALLOWED] = false
		Archetype.TYRANT:
			_set_multipliers(result, {
				KEY_AGGRESSION: 1.80, KEY_PEACE: 0.45, KEY_ALLIANCE: 0.35,
				KEY_FOOD_OUTPUT: 0.75,
				KEY_MANPOWER_OUTPUT: 1.70, KEY_UPKEEP: 1.25,
				KEY_FOOD_CONSUMPTION: 1.20, KEY_MORALE: 0.80,
				KEY_DEFENSE: 1.15, KEY_CITY_DEFENSE: 1.25,
				KEY_ENFEOFF: 0.20, KEY_CENTRALIZE: 3.00, KEY_TRADE: 0.50,
			})
			result[KEY_LOYALTY] = 0.35
		Archetype.MERCHANT:
			_set_multipliers(result, {
				KEY_AGGRESSION: 0.50, KEY_PEACE: 1.60, KEY_ALLIANCE: 1.40,
				KEY_FOOD_OUTPUT: 1.10,
				KEY_MANPOWER_OUTPUT: 0.60, KEY_UPKEEP: 0.65,
				KEY_FOOD_CONSUMPTION: 0.90, KEY_MORALE: 0.75,
				KEY_DEFENSE: 0.70, KEY_CITY_DEFENSE: 0.90,
				KEY_ENFEOFF: 1.10, KEY_CENTRALIZE: 0.70, KEY_TRADE: 2.50,
			})
			result[KEY_RESERVE_MONTHS] = 6
		Archetype.REFORMER:
			_set_multipliers(result, {
				KEY_AGGRESSION: 0.90, KEY_PEACE: 1.15, KEY_ALLIANCE: 1.15,
				KEY_FOOD_OUTPUT: 1.30,
				KEY_MANPOWER_OUTPUT: 1.60, KEY_UPKEEP: 0.75,
				KEY_FOOD_CONSUMPTION: 0.75, KEY_MORALE: 1.25,
				KEY_DEFENSE: 1.25, KEY_CITY_DEFENSE: 1.25,
				KEY_ENFEOFF: 0.45, KEY_CENTRALIZE: 2.00, KEY_TRADE: 1.40,
			})
			result[KEY_LOYALTY] = 1.40
			result[KEY_RESERVE_MONTHS] = 4
		Archetype.DIPLOMAT:
			_set_multipliers(result, {
				KEY_AGGRESSION: 0.20, KEY_PEACE: 2.50, KEY_ALLIANCE: 2.50,
				KEY_FOOD_OUTPUT: 1.00,
				KEY_MANPOWER_OUTPUT: 0.75, KEY_UPKEEP: 0.85,
				KEY_FOOD_CONSUMPTION: 0.95, KEY_MORALE: 0.85,
				KEY_DEFENSE: 0.75, KEY_CITY_DEFENSE: 0.85,
				KEY_ENFEOFF: 1.50, KEY_CENTRALIZE: 0.45, KEY_TRADE: 1.80,
			})
			result[KEY_RESERVE_MONTHS] = 5
			result[KEY_OFFENSIVE_ALLOWED] = false
		Archetype.BUILDER:
			_set_multipliers(result, {
				KEY_AGGRESSION: 0.40, KEY_PEACE: 1.60, KEY_ALLIANCE: 1.05,
				KEY_FOOD_OUTPUT: 1.80,
				KEY_MANPOWER_OUTPUT: 1.15, KEY_UPKEEP: 0.70,
				KEY_FOOD_CONSUMPTION: 0.65, KEY_MORALE: 1.10,
				KEY_DEFENSE: 1.50, KEY_CITY_DEFENSE: 2.25,
				KEY_ENFEOFF: 0.70, KEY_CENTRALIZE: 1.30, KEY_TRADE: 1.20,
			})
			result[KEY_RESERVE_MONTHS] = 8
		Archetype.PUPPET:
			_set_multipliers(result, {
				KEY_AGGRESSION: 0.25, KEY_PEACE: 1.80, KEY_ALLIANCE: 1.35,
				KEY_FOOD_OUTPUT: 0.80,
				KEY_MANPOWER_OUTPUT: 0.70, KEY_UPKEEP: 1.15,
				KEY_FOOD_CONSUMPTION: 1.10, KEY_MORALE: 0.70,
				KEY_DEFENSE: 0.70, KEY_CITY_DEFENSE: 0.85,
				KEY_ENFEOFF: 5.00, KEY_CENTRALIZE: 0.05, KEY_TRADE: 0.75,
			})
			result[KEY_LOYALTY] = 0.65
			result[KEY_RESERVE_MONTHS] = -3
			result[KEY_OFFENSIVE_ALLOWED] = false
	return result


static func _apply_trait(result: Dictionary, trait_id: String) -> void:
	match trait_id:
		TRAIT_AMBITIOUS:
			_multiply(result, KEY_AGGRESSION, 1.50)
			_multiply(result, KEY_PEACE, 0.75)
			_multiply(result, KEY_CENTRALIZE, 1.35)
		TRAIT_CAUTIOUS:
			_multiply(result, KEY_AGGRESSION, 0.65)
			_multiply(result, KEY_PEACE, 1.35)
			_multiply(result, KEY_DEFENSE, 1.30)
			_multiply(result, KEY_CITY_DEFENSE, 1.25)
			_add_reserve_months(result, 3)
		TRAIT_CHARISMATIC:
			_multiply(result, KEY_ALLIANCE, 1.50)
			_multiply(result, KEY_MORALE, 1.35)
			_multiply(result, KEY_LOYALTY, 1.35)
		TRAIT_FRUGAL:
			_multiply(result, KEY_UPKEEP, 0.65)
			_add_reserve_months(result, 4)
		TRAIT_DILIGENT:
			_multiply(result, KEY_FOOD_OUTPUT, 1.25)
			_multiply(result, KEY_MANPOWER_OUTPUT, 1.25)
			_multiply(result, KEY_LOYALTY, 1.20)
		TRAIT_LOGISTICIAN:
			_multiply(result, KEY_FOOD_OUTPUT, 1.35)
			_multiply(result, KEY_FOOD_CONSUMPTION, 0.60)
			_add_reserve_months(result, 5)
		TRAIT_MARTIAL:
			_multiply(result, KEY_AGGRESSION, 1.35)
			_multiply(result, KEY_MORALE, 1.45)
			_multiply(result, KEY_DEFENSE, 1.35)
		TRAIT_FORTIFIER:
			_multiply(result, KEY_AGGRESSION, 0.75)
			_multiply(result, KEY_DEFENSE, 1.40)
			_multiply(result, KEY_CITY_DEFENSE, 1.60)
			_add_reserve_months(result, 3)
		TRAIT_MERCANTILE:
			_multiply(result, KEY_TRADE, 1.60)
			_multiply(result, KEY_ALLIANCE, 1.20)
		TRAIT_CENTRALIZER:
			_multiply(result, KEY_ENFEOFF, 0.45)
			_multiply(result, KEY_CENTRALIZE, 1.80)
			_multiply(result, KEY_MANPOWER_OUTPUT, 1.20)
		TRAIT_FEUDALIST:
			_multiply(result, KEY_ENFEOFF, 1.80)
			_multiply(result, KEY_CENTRALIZE, 0.45)
			_multiply(result, KEY_DEFENSE, 1.20)
		TRAIT_HARSH:
			_multiply(result, KEY_PEACE, 0.70)
			_multiply(result, KEY_ALLIANCE, 0.70)
			_multiply(result, KEY_MANPOWER_OUTPUT, 1.40)
			_multiply(result, KEY_MORALE, 0.80)
			_multiply(result, KEY_LOYALTY, 0.65)


static func _set_multipliers(result: Dictionary, values: Dictionary) -> void:
	for key in values:
		result[key] = values[key]


static func _multiply(result: Dictionary, key: String, factor: float) -> void:
	result[key] = float(result[key]) * factor


static func _add_reserve_months(result: Dictionary, amount: int) -> void:
	result[KEY_RESERVE_MONTHS] = int(result[KEY_RESERVE_MONTHS]) + amount


static func _resolved_archetype(profile_or_archetype: Variant) -> int:
	var archetype := Archetype.BALANCED
	if typeof(profile_or_archetype) == TYPE_DICTIONARY:
		archetype = int(profile_or_archetype.get(
			"ruler_archetype", Archetype.BALANCED
		))
	elif typeof(profile_or_archetype) == TYPE_OBJECT:
		if profile_or_archetype != null:
			archetype = int(profile_or_archetype.get("ruler_archetype"))
	else:
		archetype = int(profile_or_archetype)
	return _normalized_archetype(archetype)


static func _resolved_traits(
	profile_or_archetype: Variant,
	traits: Array
) -> Array[String]:
	var source: Array = traits
	if source.is_empty():
		if typeof(profile_or_archetype) == TYPE_DICTIONARY:
			var dictionary_traits: Variant = profile_or_archetype.get(
				"ruler_traits", []
			)
			if typeof(dictionary_traits) == TYPE_ARRAY:
				source = dictionary_traits
		elif (
			typeof(profile_or_archetype) == TYPE_OBJECT
			and profile_or_archetype != null
		):
			var object_traits: Variant = profile_or_archetype.get("ruler_traits")
			if typeof(object_traits) == TYPE_ARRAY:
				source = object_traits
	var result: Array[String] = []
	for trait_value in source:
		var trait_id := str(trait_value)
		if is_valid_trait(trait_id) and not result.has(trait_id):
			result.append(trait_id)
	result.sort()
	if result.size() > MAX_TRAITS:
		result.resize(MAX_TRAITS)
	return result


static func _normalized_archetype(archetype: int) -> int:
	return archetype if is_valid_archetype(archetype) else Archetype.BALANCED
