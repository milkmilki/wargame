class_name WorldNaming
extends RefCounted
## 古代中国风格的确定性世界命名。
##
## 所有选择只依赖显式 seed、稳定实体 id 和字符串域；本类从不读取或推进
## GameState.rng。城市全称与君主姓名保持战役唯一；国家称号则严格服从
## founding_city / 首府的地域语义，即使历史政权因此同名也不改换地域锚点。

const HASH_MODULUS: int = 2147483647
const HASH_MULTIPLIER: int = 48271
const HASH_INITIAL: int = 216613626

const KIND_DYNASTY: String = "dynasty"
const KIND_WARRING_STATE: String = "state"
## 割据国在持久化/UI 层仍属于 state；词典分类不扩张 name_kind 枚举。
const KIND_SEPARATIST: String = "state"
const KIND_VASSAL: String = "vassal"
const KIND_REBEL: String = "rebel"

const _NATION_REGISTRY_META: StringName = &"world_naming_used_nations"
const _CITY_REGISTRY_META: StringName = &"world_naming_used_cities"
const _CITY_SHORT_REGISTRY_META: StringName = &"world_naming_used_city_shorts"
const _RULER_REGISTRY_META: StringName = &"world_naming_used_rulers"

## 帝国级、初始独立主权国只从单字国号中取名。三个词典有意保留历史
## 分类；合并分配时会去重（如“秦”同时属于王朝与战国诸侯）。
const DYNASTY_NAMES: Array[String] = [
	"夏", "商", "周", "秦", "汉", "晋", "隋", "唐",
	"宋", "辽", "金", "元", "明", "清", "新", "梁",
	"陈", "齐", "魏", "赵", "燕", "蜀", "吴", "成",
	"凉",
]

const WARRING_STATE_NAMES: Array[String] = [
	"秦", "齐", "楚", "燕", "韩", "赵", "魏", "宋",
	"卫", "郑", "鲁", "越", "蔡", "曹", "滕", "薛",
	"邹", "莒", "邢", "许", "陈", "徐", "巴", "蜀",
]

const SEPARATIST_STATE_NAMES: Array[String] = [
	"代", "岐", "荆", "闽", "粤", "湘", "赣", "淮",
	"朔", "陇", "雍", "冀", "幽", "并", "青", "兖",
	"豫", "扬", "益", "交", "宁", "平", "定", "顺",
	"义", "兴", "昌", "安", "康", "靖", "武", "昭",
	"景", "泰", "熙", "弘", "隆", "乾", "坤", "华",
	"宛", "郢", "邺", "蓟", "鄴", "邯", "郯", "莱",
	"谭", "遂", "宿", "鄫", "任", "申", "息", "邓",
	"随", "庸", "夔", "邾", "虢", "虞", "芮", "霍",
	"管", "耿", "贾", "鄘", "邶", "郐", "缯", "奄",
	"孤", "蒲", "箕", "密", "郜", "樊", "罗", "黄",
	"钟", "舒", "弦", "葛", "萧", "郕", "巢", "赖",
]

## 藩王和地方叛军共用的多字地域词典。它们永远不会从上面的单字主权
## 国号池取名，即使叛军后来取得独立，仍保留地域政权身份。
const REGIONAL_TITLES: Array[String] = [
	"河间", "淮南", "琅琊", "颍川", "汝南", "南阳",
	"弘农", "河内", "河南", "上党", "太原", "雁门",
	"常山", "中山", "渔阳", "北平", "辽西", "辽东",
	"乐浪", "玄菟", "西河", "上郡", "北地", "安定",
	"陇西", "武威", "张掖", "酒泉", "敦煌", "汉中",
	"巴郡", "蜀郡", "广汉", "犍为", "永昌", "牂牁",
	"会稽", "丹阳", "豫章", "庐江", "九江", "江夏",
	"南郡", "长沙", "桂阳", "零陵", "武陵", "苍梧",
	"南海", "合浦", "交趾", "朔方", "五原", "云中",
	"定襄", "涿郡", "广阳", "魏郡", "清河", "巨鹿",
	"东郡", "陈留", "梁郡", "沛郡", "彭城", "东海",
	"泰山", "济南", "北海", "胶东", "济北", "山阳",
	"广陵", "吴郡", "新都", "建安", "临海", "南康",
	"宜都", "襄阳", "江陵", "江州", "巴东", "梓潼",
	"武都", "天水", "扶风", "京兆", "冯翊", "新平",
	"平阳", "河东", "博陵", "范阳", "赵郡", "广平",
	"平原", "乐安", "高密", "鲁郡", "谯郡", "弋阳",
	"义阳", "庐陵", "始安", "桂林", "临贺", "郁林",
	"日南", "武昌", "夷陵", "建宁", "朱提", "越嶲",
]

## 历史城市池。超过词典容量后使用“地域字 + 城邑古称”的确定性组合，
## 组合空间远大于 500，最后仍有纯汉字的 id 兜底。
const HISTORIC_CITY_NAMES: Array[String] = [
	"幽州", "冀州", "并州", "兖州", "青州", "徐州",
	"扬州", "荆州", "豫州", "益州", "雍州", "凉州",
	"交州", "司州", "朔州", "云州",
	"咸阳", "长安", "洛阳", "邯郸", "临淄", "蓟城",
	"大梁", "郢都", "建业", "成都", "襄阳", "江陵",
	"寿春", "许昌", "宛城", "晋阳", "平城", "邺城",
	"睢阳", "彭城", "广陵", "吴县", "会稽", "柴桑",
	"豫章", "庐江", "江夏", "武昌", "长沙", "零陵",
	"桂阳", "武陵", "南海", "番禺", "交趾", "合浦",
	"汉中", "梓潼", "江州", "永安", "建宁", "永昌",
	"武都", "天水", "陇西", "金城", "武威", "张掖",
	"酒泉", "敦煌", "安定", "北地", "上郡", "西河",
	"河东", "弘农", "河内", "上党", "雁门", "云中",
	"五原", "朔方", "代郡", "常山", "中山", "巨鹿",
	"清河", "渤海", "涿郡", "渔阳", "辽西", "辽东",
	"玄菟", "乐浪", "北海", "东莱", "琅琊", "泰山",
	"济南", "济北", "东平", "任城", "山阳", "陈留",
	"颍川", "汝南", "谯县", "沛县", "下邳", "东海",
	"丹阳", "建安", "临海", "庐陵", "南康", "宜春",
	"桂林", "苍梧", "郁林", "日南", "九真", "朱崖",
	"夷陵", "宜都", "公安", "巴东", "涪陵", "犍为",
	"广汉", "巴西", "越嶲", "牂牁", "扶风", "冯翊",
	"京兆", "新平", "始平", "临洮", "姑臧", "居延",
	"轮台", "龟兹", "疏勒", "于阗", "楼兰", "高昌",
	"襄平", "柳城", "昌黎", "右北平", "范阳", "博陵",
	"河间", "广平", "赵国", "魏郡", "平原", "乐安",
	"高密", "城阳", "鲁县", "兰陵", "小沛", "广固",
]

const GEOGRAPHIC_STEMS: Array[String] = [
	"安", "昌", "宁", "平", "定", "靖", "康", "泰",
	"永", "长", "兴", "隆", "丰", "盛", "嘉", "庆",
	"昭", "景", "弘", "广", "新", "德", "义", "信",
	"武", "文", "宣", "威", "怀", "顺", "和", "清",
	"阳", "阴", "东", "西", "南", "北", "河", "江",
	"山", "海", "临", "上", "下", "中", "高", "大",
	"金", "玉", "龙", "凤", "云", "石", "青", "白",
	"赤", "黄", "紫", "丹", "松", "桂", "柳", "兰",
]

const SETTLEMENT_ENDINGS: Array[String] = [
	"安", "昌", "宁", "平", "定", "阳", "阴", "城",
	"邑", "亭", "关", "原", "川", "谷", "陵", "丘",
	"泽", "湖", "泉", "溪", "浦", "口", "津", "渡",
	"台", "郡", "县", "州", "府", "寨", "堡", "营",
	"集", "里", "庄", "陂", "陉", "坂", "坞", "壁",
]

const REGION_ENDINGS: Array[String] = [
	"川", "原", "阳", "阴", "山", "河", "江", "海",
	"陵", "泽", "谷", "关", "郡", "州", "城", "邑",
	"东", "西", "南", "北", "安", "平", "宁", "昌",
	"源", "野", "陂", "浦", "亭", "台", "津", "口",
]

const DOCK_SUFFIXES: Array[String] = ["津", "渡", "浦", "港"]
const DOCK_QUALIFIERS: Array[String] = [
	"东", "西", "南", "北", "上", "下", "新", "外",
	"前", "后", "大", "小",
]

const RULER_SURNAMES: Array[String] = [
	"赵", "钱", "孙", "李", "周", "吴", "郑", "王",
	"冯", "陈", "褚", "卫", "蒋", "沈", "韩", "杨",
	"朱", "秦", "尤", "许", "何", "吕", "施", "张",
	"孔", "曹", "严", "华", "金", "魏", "陶", "姜",
	"戚", "谢", "邹", "喻", "柏", "窦", "章", "云",
	"苏", "潘", "葛", "奚", "范", "彭", "郎", "鲁",
]

const RULER_GIVEN_NAMES: Array[String] = [
	"安", "昂", "彬", "昌", "诚", "达", "德", "端",
	"弘", "济", "靖", "恺", "礼", "明", "宁", "平",
	"睿", "绍", "泰", "威", "文", "修", "彦", "昭",
	"伯安", "子敬", "公瑾", "元直", "仲达", "奉孝",
	"士元", "文和", "景略", "玄德", "孟德", "仲谋",
	"道济", "怀德", "承礼", "守仁", "知远", "思齐",
]

## 城市全称到传统地域国号字的优先映射。没有明确历史对应的城市会从
## 单字国号池稳定派生；城市名与地域字因此都是 seed-stable 的。
const CITY_REGION_OVERRIDES: Dictionary = {
	"幽州": "燕", "冀州": "赵", "并州": "晋",
	"兖州": "鲁", "青州": "齐", "徐州": "徐",
	"扬州": "吴", "荆州": "楚", "豫州": "韩",
	"益州": "蜀", "雍州": "秦", "凉州": "凉",
	"交州": "越", "司州": "周", "朔州": "代",
	"云州": "代",
	"咸阳": "秦", "长安": "秦", "洛阳": "周",
	"邯郸": "赵", "临淄": "齐", "蓟城": "燕",
	"大梁": "魏", "郢都": "楚", "建业": "吴",
	"成都": "蜀", "襄阳": "荆", "江陵": "楚",
	"寿春": "淮", "许昌": "魏", "宛城": "宛",
	"晋阳": "晋", "平城": "代", "邺城": "魏",
	"睢阳": "宋", "彭城": "徐", "广陵": "扬",
	"吴县": "吴", "会稽": "越", "柴桑": "江",
	"豫章": "赣", "庐江": "庐", "江夏": "鄂",
	"武昌": "鄂", "长沙": "湘", "零陵": "湘",
	"桂阳": "桂", "武陵": "荆", "南海": "粤",
	"番禺": "粤", "交趾": "交", "合浦": "粤",
	"汉中": "汉", "梓潼": "蜀", "江州": "巴",
	"永安": "巴", "建宁": "宁", "永昌": "滇",
	"武都": "陇", "天水": "陇", "陇西": "陇",
	"金城": "凉", "武威": "凉", "张掖": "凉",
	"酒泉": "凉", "敦煌": "凉", "安定": "雍",
	"北地": "雍", "上郡": "秦", "西河": "晋",
	"河东": "晋", "弘农": "虢", "河内": "卫",
	"上党": "韩", "雁门": "代", "云中": "朔",
	"五原": "朔", "朔方": "朔", "代郡": "代",
	"常山": "赵", "中山": "赵", "巨鹿": "赵",
	"清河": "冀", "渤海": "冀", "涿郡": "燕",
	"渔阳": "燕", "辽西": "辽", "辽东": "辽",
	"玄菟": "辽", "乐浪": "辽", "北海": "齐",
	"东莱": "齐", "琅琊": "鲁", "泰山": "鲁",
	"济南": "齐", "济北": "齐", "东平": "鲁",
	"任城": "鲁", "山阳": "兖", "陈留": "陈",
	"颍川": "韩", "汝南": "蔡", "谯县": "谯",
	"沛县": "沛", "下邳": "徐", "东海": "徐",
	"丹阳": "吴", "建安": "闽", "临海": "越",
	"庐陵": "赣", "南康": "赣", "宜春": "湘",
	"桂林": "桂", "苍梧": "桂", "郁林": "桂",
	"日南": "交", "九真": "交", "朱崖": "琼",
	"夷陵": "荆", "宜都": "荆", "公安": "荆",
	"巴东": "巴", "涪陵": "巴", "犍为": "蜀",
	"广汉": "蜀", "巴西": "巴", "越嶲": "蜀",
	"牂牁": "黔", "扶风": "岐", "冯翊": "雍",
	"京兆": "秦", "新平": "雍", "始平": "雍",
	"临洮": "陇", "姑臧": "凉", "居延": "凉",
	"轮台": "西", "龟兹": "西", "疏勒": "西",
	"于阗": "西", "楼兰": "西", "高昌": "西",
	"襄平": "辽", "柳城": "辽", "昌黎": "辽",
	"右北平": "燕", "范阳": "燕", "博陵": "冀",
	"河间": "冀", "广平": "赵", "赵国": "赵",
	"魏郡": "魏", "平原": "齐", "乐安": "齐",
	"高密": "齐", "城阳": "齐", "鲁县": "鲁",
	"兰陵": "鲁", "小沛": "沛", "广固": "齐",
}


## 为新生成的整个世界分配名称。重复调用是幂等的：已有合法名称保留，
## 仅为空白或冲突实体补名。调用前后 GameState.rng.state 完全不变。
static func assign_initial_names(game_state, world_seed: int) -> void:
	if game_state == null:
		return
	game_state.world_seed = world_seed
	_reset_registries(game_state)
	var changed := false
	# 城市必须先命名，国家国号随后才可从首都或发迹城市的地域字产生。
	var city_registry := _registry(game_state, _CITY_REGISTRY_META)
	var unnamed_land: Array[int] = []
	var unnamed_docks: Array[int] = []
	for city_index in range(game_state.cities.size()):
		var city = game_state.cities[city_index]
		var city_id := int(city.id)
		var existing := str(city.name).strip_edges()
		if not existing.is_empty() and _reserve(city_registry, existing, city_id):
			if city.name != existing:
				city.name = existing
				changed = true
			continue
		if not existing.is_empty():
			city.name = ""
			changed = true
		if city.is_dock:
			unnamed_docks.append(city_index)
		else:
			unnamed_land.append(city_index)
	unnamed_land.sort()
	unnamed_docks.sort()
	for city_index in unnamed_land:
		var city = game_state.cities[city_index]
		city.name = _allocate_land_city_name(
			world_seed, int(city.id), city, city_registry
		)
		changed = true
	for city_index in range(game_state.cities.size()):
		var city = game_state.cities[city_index]
		if city.is_dock:
			continue
		var symbol := str(city.region_symbol).strip_edges()
		if not _is_single_character(symbol):
			city.region_symbol = _region_symbol_for_city(
				world_seed, int(city.id), str(city.name)
			)
			changed = true
	for city_index in unnamed_docks:
		var city = game_state.cities[city_index]
		city.name = _allocate_dock_name(
			game_state, world_seed, int(city.id), city_registry
		)
		changed = true
	for city_index in range(game_state.cities.size()):
		var city = game_state.cities[city_index]
		if not city.is_dock:
			continue
		var symbol := str(city.region_symbol).strip_edges()
		if _is_single_character(symbol):
			continue
		var anchor_id := _dock_anchor_id(game_state, int(city.id))
		city.region_symbol = (
			city_region_symbol(game_state, anchor_id)
			if anchor_id >= 0
			else _region_symbol_for_city(world_seed, int(city.id), str(city.name))
		)
		changed = true

	# 城市简称：单字、战役唯一。优先复用 region_symbol，冲突再从全称派生。
	# 城市 id 升序保证同 seed 稳定去重；藩王单字王封号取自首都简称。
	var short_registry := _registry(game_state, _CITY_SHORT_REGISTRY_META)
	for city_index in range(game_state.cities.size()):
		var city = game_state.cities[city_index]
		var current_short := str(city.short_name).strip_edges()
		if (
			_is_single_character(current_short)
			and _reserve(short_registry, current_short, int(city.id))
		):
			if city.short_name != current_short:
				city.short_name = current_short
				changed = true
			continue
		var allocated := _allocate_city_short_name(
			world_seed, int(city.id),
			city_region_symbol(game_state, int(city.id)),
			str(city.name), short_registry
		)
		if city.short_name != allocated:
			city.short_name = allocated
			changed = true

	var nation_registry := _registry(game_state, _NATION_REGISTRY_META)
	var ruler_registry := _registry(game_state, _RULER_REGISTRY_META)
	for nation_index in range(game_state.nations.size()):
		var nation = game_state.nations[nation_index]
		var nation_id := int(nation.id)
		var founding_before := int(nation.founding_city_id)
		ensure_founding_city_id(game_state, nation_id)
		changed = int(nation.founding_city_id) != founding_before or changed
		var kind := str(nation.name_kind)
		var formal := str(nation.name).strip_edges()
		if kind == KIND_VASSAL:
			formal = _vassal_display_name(game_state, nation_id)
			if nation.name != formal or nation.short_name != formal:
				nation.name = formal
				nation.short_name = formal
				changed = true
		elif kind == KIND_REBEL:
			var base := _nation_base(nation)
			formal = base + "军" if _is_regional_base(base) else ""
			if formal.is_empty() or not _reserve(nation_registry, formal, nation_id):
				formal = _allocate_regional_formal(
					game_state, world_seed, nation_id,
					_owned_land_city_ids(game_state, nation_id), nation_registry,
					"nation/rebel", -1, "军"
				)
			var rebel_base := formal.substr(0, formal.length() - 1)
			if nation.name != formal or nation.short_name != rebel_base:
				nation.name = formal
				nation.short_name = rebel_base
				changed = true
		else:
			var replacement: Dictionary = _founding_sovereign_identity(
				game_state, world_seed, nation_id
			)
			var base := str(replacement["base"])
			var resolved_kind := str(replacement["kind"])
			if (
				nation.name != base
				or nation.short_name != base
				or nation.name_kind != resolved_kind
			):
				nation.name = base
				nation.short_name = base
				nation.name_kind = resolved_kind
				changed = true
		changed = _assign_unique_ruler(
			nation, world_seed, nation_id, ruler_registry
		) or changed

	if changed:
		_bump_revision(game_state)


## 地图模板可选地携带名称；旧版模板没有这些键时，自动回退到稳定生成。
static func assign_from_definition(
	game_state,
	definition: Dictionary,
	world_seed: int
) -> void:
	if game_state == null:
		return
	var injected := false
	var nation_records: Variant = definition.get("nations", [])
	if nation_records is Array:
		for index in range(mini(nation_records.size(), game_state.nations.size())):
			var record_value: Variant = nation_records[index]
			if record_value is Dictionary:
				var record: Dictionary = record_value
				var nation = game_state.nations[index]
				for field in [
					"name", "short_name", "name_kind", "ruler_name",
					"founding_city_id",
					"ruler_archetype", "ruler_traits", "ruler_started_day",
					"ruler_revision", "trade_policy",
				]:
					if record.has(field):
						if field in ["name", "short_name", "name_kind", "ruler_name"]:
							nation.set(field, str(record[field]))
						elif field == "ruler_traits":
							var traits: Array[String] = []
							for trait_value in record[field]:
								traits.append(str(trait_value))
							nation.ruler_traits = traits
						else:
							nation.set(field, int(record[field]))
						injected = true
	var legacy_names: Variant = definition.get("nation_names", [])
	if legacy_names is Array:
		for index in range(mini(legacy_names.size(), game_state.nations.size())):
			if str(legacy_names[index]).strip_edges().is_empty():
				continue
			game_state.nations[index].name = str(legacy_names[index])
			injected = true

	var city_records: Variant = definition.get("cities", [])
	if city_records is Array:
		for index in range(mini(city_records.size(), game_state.cities.size())):
			var record_value: Variant = city_records[index]
			if record_value is not Dictionary:
				continue
			var record: Dictionary = record_value
			if record.has("name"):
				game_state.cities[index].name = str(record["name"])
				injected = true
			if record.has("region_symbol"):
				game_state.cities[index].region_symbol = str(record["region_symbol"])
				injected = true
	var revision_before := int(game_state.naming_revision)
	assign_initial_names(game_state, world_seed)
	if injected and int(game_state.naming_revision) == revision_before:
		_bump_revision(game_state)


## 为运行时新建藩王分配稳定基础名；不足五城用藩都全称，五城起用
## 藩都地域字，正式显示统一追加“王”。
static func assign_vassal_name(
	game_state,
	subject_id: int,
	granted_city_ids: Array[int]
) -> String:
	if not _valid_nation_id(game_state, subject_id):
		return ""
	var nation = game_state.nations[subject_id]
	var old_signature := "%s|%s|%s|%s|%d" % [
		nation.name, nation.short_name, nation.name_kind, nation.ruler_name,
		nation.founding_city_id,
	]
	nation.name_kind = KIND_VASSAL
	ensure_founding_city_id(game_state, subject_id)
	var formal := _vassal_display_name(game_state, subject_id)
	nation.short_name = formal
	nation.name = formal
	var rulers := _registry(game_state, _RULER_REGISTRY_META)
	_backfill_ruler_registry(game_state, rulers, subject_id)
	_assign_unique_ruler(nation, int(game_state.world_seed), subject_id, rulers)
	var new_signature := "%s|%s|%s|%s|%d" % [
		nation.name, nation.short_name, nation.name_kind, nation.ruler_name,
		nation.founding_city_id,
	]
	if new_signature != old_signature:
		_bump_revision(game_state)
	return nation.name


## 为地方叛军分配二至四字地域基础名。叛军保留“地域军”身份，不会在
## 独立后改用任何单字帝国国号。
static func assign_rebel_name(
	game_state,
	rebel_id: int,
	parent_id: int,
	city_ids: Array[int]
) -> String:
	if not _valid_nation_id(game_state, rebel_id):
		return ""
	var nation = game_state.nations[rebel_id]
	var old_signature := "%s|%s|%s|%s|%d" % [
		nation.name, nation.short_name, nation.name_kind, nation.ruler_name,
		nation.founding_city_id,
	]
	ensure_founding_city_id(game_state, rebel_id)
	var registry := _registry(game_state, _NATION_REGISTRY_META)
	_backfill_nation_registry(game_state, registry, rebel_id)
	var base := _nation_base(nation)
	var formal := base + "军" if _is_regional_base(base) else ""
	if formal.is_empty() or not _reserve(registry, formal, rebel_id):
		formal = _allocate_regional_formal(
			game_state, int(game_state.world_seed), rebel_id, city_ids, registry,
			"nation/rebel", parent_id, "军"
		)
		base = formal.substr(0, formal.length() - 1)
	nation.short_name = base
	nation.name = formal
	nation.name_kind = KIND_REBEL
	var rulers := _registry(game_state, _RULER_REGISTRY_META)
	_backfill_ruler_registry(game_state, rulers, rebel_id)
	_assign_unique_ruler(
		nation, int(game_state.world_seed), rebel_id + parent_id * 4099, rulers
	)
	var new_signature := "%s|%s|%s|%s|%d" % [
		nation.name, nation.short_name, nation.name_kind, nation.ruler_name,
		nation.founding_city_id,
	]
	if new_signature != old_signature:
		_bump_revision(game_state)
	return nation.name


## 把一个已脱离宗藩关系的藩王统一升格为主权国。建国城市只在旧状态
## 缺失时补一次；国号严格取该城 region_symbol，不因历史同名而换锚点。
static func promote_vassal_to_sovereign(
	game_state,
	nation_id: int
) -> String:
	if not _valid_nation_id(game_state, nation_id):
		return ""
	var nation = game_state.nations[nation_id]
	if not nation.alive:
		return str(nation.name)
	if str(nation.name_kind) != KIND_VASSAL:
		return str(nation.name)
	var founding_before := int(nation.founding_city_id)
	var founding_id := ensure_founding_city_id(game_state, nation_id)
	if founding_id < 0:
		return str(nation.name)
	var symbol := city_region_symbol(game_state, founding_id)
	if not _is_single_character(symbol):
		return str(nation.name)
	var kind := _sovereign_kind(symbol)
	var changed: bool = (
		founding_id != founding_before
		or nation.name != symbol
		or nation.short_name != symbol
		or nation.name_kind != kind
	)
	nation.name = symbol
	nation.short_name = symbol
	nation.name_kind = kind
	if changed:
		_bump_revision(game_state)
	return symbol


## 首次确定并持久化建国城。已经有效的历史锚点即使失地也不改变。
static func ensure_founding_city_id(game_state, nation_id: int) -> int:
	if not _valid_nation_id(game_state, nation_id):
		return -1
	var nation = game_state.nations[nation_id]
	var existing := int(nation.founding_city_id)
	if _valid_land_city_id(game_state, existing):
		return existing
	var candidate := int(nation.capital_city_id)
	if (
		not _valid_land_city_id(game_state, candidate)
		or game_state.cities[candidate].owner_nation != nation_id
	):
		candidate = -1
		for city_index in range(game_state.cities.size()):
			var city = game_state.cities[city_index]
			if city.owner_nation == nation_id and not city.is_dock:
				candidate = int(city.id)
				break
	if candidate >= 0:
		nation.founding_city_id = candidate
	return candidate


## 给初始分配后追加的城市（尤其动态码头）补名。
static func assign_city_name(game_state, city_id: int) -> String:
	if not _valid_city_id(game_state, city_id):
		return ""
	var city = game_state.cities[city_id]
	if not str(city.name).strip_edges().is_empty():
		if not _is_single_character(str(city.region_symbol)):
			var anchor_id := _dock_anchor_id(game_state, city_id) if city.is_dock else -1
			city.region_symbol = (
				city_region_symbol(game_state, anchor_id)
				if anchor_id >= 0
				else _region_symbol_for_city(
					int(game_state.world_seed), city_id, str(city.name)
				)
			)
			_bump_revision(game_state)
		_ensure_city_short_name(game_state, city_id)
		return str(city.name)
	var registry := _registry(game_state, _CITY_REGISTRY_META)
	_backfill_city_registry(game_state, registry, city_id)
	if city.is_dock:
		city.name = _allocate_dock_name(
			game_state, int(game_state.world_seed), city_id, registry
		)
	else:
		city.name = _allocate_land_city_name(
			int(game_state.world_seed), city_id, city, registry
		)
	var anchor_id := _dock_anchor_id(game_state, city_id) if city.is_dock else -1
	city.region_symbol = (
		city_region_symbol(game_state, anchor_id)
		if anchor_id >= 0
		else _region_symbol_for_city(
			int(game_state.world_seed), city_id, str(city.name)
		)
	)
	_ensure_city_short_name(game_state, city_id)
	_bump_revision(game_state)
	return str(city.name)


## 为运行时新增城市补一个战役唯一的单字简称：优先复用 region_symbol，
## 冲突再从全称派生。已合法且未冲突的简称保留。
static func _ensure_city_short_name(game_state, city_id: int) -> void:
	if not _valid_city_id(game_state, city_id):
		return
	var city = game_state.cities[city_id]
	var short_registry := _registry(game_state, _CITY_SHORT_REGISTRY_META)
	_backfill_city_short_registry(game_state, short_registry, city_id)
	var current_short := str(city.short_name).strip_edges()
	if (
		_is_single_character(current_short)
		and _reserve(short_registry, current_short, city_id)
	):
		if city.short_name != current_short:
			city.short_name = current_short
		return
	city.short_name = _allocate_city_short_name(
		int(game_state.world_seed), city_id,
		city_region_symbol(game_state, city_id),
		str(city.name), short_registry
	)


## 可传 (game_state, nation_id)；也可直接传 Nation。short_form 用于地图
## 大字，默认返回正式显示名。
static func nation_display_name(
	game_state_or_nation,
	nation_id: Variant = null,
	short_form: bool = false
) -> String:
	var nation = null
	var fallback_id := -1
	if nation_id == null:
		nation = game_state_or_nation
		if nation != null:
			fallback_id = int(nation.id)
	elif game_state_or_nation != null:
		fallback_id = int(nation_id)
		if _valid_nation_id(game_state_or_nation, fallback_id):
			nation = game_state_or_nation.nations[fallback_id]
	if nation == null:
		return "国%d" % fallback_id if fallback_id >= 0 else "无名国"
	var short_name := str(nation.short_name).strip_edges()
	var formal_name := str(nation.name).strip_edges()
	if str(nation.name_kind) == KIND_VASSAL and nation_id != null:
		return _vassal_display_name(game_state_or_nation, fallback_id)
	if short_form and not short_name.is_empty():
		return short_name
	if not formal_name.is_empty():
		return formal_name
	if not short_name.is_empty():
		return short_name
	return "国%d" % int(nation.id)


## 可传 (game_state, city_id)；也可直接传 City。码头名本身已经含
## 津/渡/浦/港，不再叠加第二个类型后缀。
static func city_display_name(
	game_state_or_city,
	city_id: Variant = null,
	include_kind: bool = false
) -> String:
	var city = null
	var fallback_id := -1
	if city_id == null:
		city = game_state_or_city
		if city != null:
			fallback_id = int(city.id)
	elif game_state_or_city != null:
		fallback_id = int(city_id)
		if _valid_city_id(game_state_or_city, fallback_id):
			city = game_state_or_city.cities[fallback_id]
	if city == null:
		return "城%d" % fallback_id if fallback_id >= 0 else "无名城"
	var assigned := str(city.name).strip_edges()
	if not assigned.is_empty():
		if include_kind and not city.is_dock and not assigned.ends_with("城"):
			return assigned + "城"
		return assigned
	return ("港%d" if city.is_dock else "城%d") % int(city.id)


## 城市信息页展示的单字简称。接口接受 City 或 (GameState, city_id)。已持久化
## 的单字简称直接返回；缺失时回退到 region_symbol（不去重，仅即时展示）。
static func city_short_name(
	game_state_or_city,
	city_id: Variant = null
) -> String:
	var city = null
	if city_id == null:
		city = game_state_or_city
	elif game_state_or_city != null:
		var resolved_id := int(city_id)
		if _valid_city_id(game_state_or_city, resolved_id):
			city = game_state_or_city.cities[resolved_id]
	if city == null:
		return ""
	var assigned := str(city.short_name).strip_edges()
	if _is_single_character(assigned):
		return assigned
	return city_region_symbol(game_state_or_city, city_id)


## 返回城市对应的单字地域国号。接口接受 City 或 (GameState, city_id)。
static func city_region_symbol(
	game_state_or_city,
	city_id: Variant = null
) -> String:
	var city = null
	var world_seed := 0
	if city_id == null:
		city = game_state_or_city
	elif game_state_or_city != null:
		world_seed = int(game_state_or_city.world_seed)
		var resolved_id := int(city_id)
		if _valid_city_id(game_state_or_city, resolved_id):
			city = game_state_or_city.cities[resolved_id]
	if city == null:
		return ""
	var assigned := str(city.region_symbol).strip_edges()
	if _is_single_character(assigned):
		return assigned
	return _region_symbol_for_city(world_seed, int(city.id), str(city.name))


## 主权身份严格锚定不可变 founding_city_id；历史同名单字不会触发换城。
## 只有无任何有效建国城的畸形状态才回退到稳定单字池。
static func _founding_sovereign_identity(
	game_state,
	world_seed: int,
	nation_id: int
) -> Dictionary:
	var founding_id := ensure_founding_city_id(game_state, nation_id)
	if founding_id >= 0:
		var symbol := city_region_symbol(game_state, founding_id)
		if _is_single_character(symbol):
			return {
				"base": symbol,
				"name": symbol,
				"kind": _sovereign_kind(symbol),
			}
	return _allocate_sovereign_name(world_seed, nation_id, {})


## 藩王展示：封号单向棘轮。陆城数达到过 5 座即永久升为「单字王」（藩都
## 简称 + 王），之后即使失地也保持单字王，绝不降回双字王；未达到过 5 座
## 前采用藩都全称 + 王。单字取自首都的战役唯一简称，故不同藩王不会撞字。
static func _vassal_display_name(game_state, nation_id: int) -> String:
	if not _valid_nation_id(game_state, nation_id):
		return ""
	var nation = game_state.nations[nation_id]
	var owned := _owned_land_city_ids(game_state, nation_id)
	var capital_id := int(nation.capital_city_id)
	if (
		not _valid_land_city_id(game_state, capital_id)
		or game_state.cities[capital_id].owner_nation != nation_id
	):
		capital_id = owned[0] if not owned.is_empty() else -1
	if capital_id < 0:
		var stored := str(nation.name).strip_edges()
		return stored if not stored.is_empty() else "无名王"
	# 单向棘轮：陆城数达到过 5 即永久锁定单字王，失地不再降回双字王。
	if owned.size() >= 5:
		nation.vassal_single_char = true
	var base := (
		city_short_name(game_state, capital_id)
		if bool(nation.vassal_single_char)
		else city_display_name(game_state, capital_id)
	)
	return base + "王"


static func _allocate_regional_formal(
	game_state,
	world_seed: int,
	nation_id: int,
	city_ids: Array[int],
	registry: Dictionary,
	domain: String,
	parent_id: int,
	suffix: String
) -> String:
	var attempted: Dictionary = {}
	var serial := 0
	while true:
		var allocation_id := nation_id + serial * 8191
		var base := _allocate_regional_base(
			game_state, world_seed, allocation_id, city_ids, attempted,
			domain + "/collision", parent_id
		)
		var formal := base + suffix
		if _reserve(registry, formal, nation_id):
			return formal
		attempted[base] = -1
		serial += 1
	return ""


static func _region_symbol_for_city(
	world_seed: int,
	city_id: int,
	city_name: String
) -> String:
	var clean := city_name.strip_edges()
	if CITY_REGION_OVERRIDES.has(clean):
		return str(CITY_REGION_OVERRIDES[clean])
	var pool := _sovereign_pool()
	return pool[stable_index(
		world_seed, city_id, "city/region_symbol", pool.size()
	)]


## 跨平台稳定的正整数 hash；公开给命名相关测试与未来继位逻辑复用。
static func stable_hash(
	world_seed: int,
	entity_id: int,
	domain: String,
	salt: int = 0
) -> int:
	var value := _hash_step(HASH_INITIAL, world_seed)
	value = _hash_step(value, entity_id)
	value = _hash_step(value, salt)
	value = _hash_step(value, domain.length())
	for index in range(domain.length()):
		value = _hash_step(value, domain.unicode_at(index) + index * 257)
	return value


static func stable_index(
	world_seed: int,
	entity_id: int,
	domain: String,
	upper_bound: int,
	salt: int = 0
) -> int:
	if upper_bound <= 0:
		return -1
	return stable_hash(world_seed, entity_id, domain, salt) % upper_bound


static func _allocate_sovereign_name(
	world_seed: int,
	nation_id: int,
	registry: Dictionary
) -> Dictionary:
	var pool := _sovereign_pool()
	var start := stable_index(
		world_seed, nation_id, "nation/sovereign/start", pool.size()
	)
	for offset in range(pool.size()):
		var candidate := pool[(start + offset) % pool.size()]
		if _reserve(registry, candidate, nation_id):
			return {
				"base": candidate,
				"name": candidate,
				"kind": _sovereign_kind(candidate),
			}
	# 极端自定义地图耗尽词典时仍严格保持单字：从 CJK 基本区确定性扫描。
	var cjk_count := 0x9FFF - 0x4E00 + 1
	var cjk_start := stable_index(
		world_seed, nation_id, "nation/sovereign/cjk", cjk_count
	)
	for offset in range(cjk_count):
		var candidate := String.chr(0x4E00 + (cjk_start + offset) % cjk_count)
		if _reserve(registry, candidate, nation_id):
			return {
				"base": candidate,
				"name": candidate,
				"kind": KIND_SEPARATIST,
			}
	return {"base": "国", "name": "国", "kind": KIND_SEPARATIST}


## 战役唯一的单字城市简称分配。候选顺序：先 region_symbol，再全称各单字
## （首、尾、其余），最后从 CJK 基本区确定性扫描兜底。城市 id 升序保证同
## seed 稳定去重，因此不同城市的简称永不重复。
static func _allocate_city_short_name(
	world_seed: int,
	city_id: int,
	region_symbol: String,
	city_name: String,
	registry: Dictionary
) -> String:
	for candidate in _city_short_candidates(region_symbol, city_name):
		if _reserve(registry, candidate, city_id):
			return candidate
	# 单字词典理论上够用；极端自定义地图撞满时从 CJK 基本区扫描保持单字唯一。
	var cjk_count := 0x9FFF - 0x4E00 + 1
	var cjk_start := stable_index(
		world_seed, city_id, "city/short/cjk", cjk_count
	)
	for offset in range(cjk_count):
		var candidate := String.chr(0x4E00 + (cjk_start + offset) % cjk_count)
		if _reserve(registry, candidate, city_id):
			return candidate
	return region_symbol.strip_edges()


## 单字简称候选的确定性展开：region_symbol 优先，其次全称首字、尾字、
## 其余各字。所有候选去重且顺序稳定，均为单字。
static func _city_short_candidates(
	region_symbol: String,
	city_name: String
) -> Array[String]:
	var result: Array[String] = []
	_append_short_candidate(result, region_symbol)
	var clean := city_name.strip_edges()
	var length := clean.length()
	if length >= 1:
		_append_short_candidate(result, clean.substr(0, 1))
	if length >= 2:
		_append_short_candidate(result, clean.substr(length - 1, 1))
	for index in range(1, maxi(length - 1, 1)):
		_append_short_candidate(result, clean.substr(index, 1))
	return result


static func _append_short_candidate(
	target: Array[String], candidate: String
) -> void:
	var value := candidate.strip_edges()
	if not _is_single_character(value) or target.has(value):
		return
	target.append(value)


## 陆地城市全称分配：优先历史城市池，其次地域词根组合，最后中文序号兜底。
static func _allocate_land_city_name(
	world_seed: int,
	city_id: int,
	city,
	registry: Dictionary
) -> String:
	var historic_start := stable_index(
		world_seed, city_id, "city/historic/start", HISTORIC_CITY_NAMES.size()
	)
	for offset in range(HISTORIC_CITY_NAMES.size()):
		var candidate := HISTORIC_CITY_NAMES[
			(historic_start + offset) % HISTORIC_CITY_NAMES.size()
		]
		if _reserve(registry, candidate, city_id):
			return candidate

	var combination_count := GEOGRAPHIC_STEMS.size() * SETTLEMENT_ENDINGS.size()
	var sector_salt := _position_sector(city.map_position)
	var combination_start := stable_index(
		world_seed, city_id, "city/combination/start",
		combination_count, sector_salt
	)
	for offset in range(combination_count):
		var combination := (combination_start + offset) % combination_count
		var stem := GEOGRAPHIC_STEMS[combination / SETTLEMENT_ENDINGS.size()]
		var ending := SETTLEMENT_ENDINGS[combination % SETTLEMENT_ENDINGS.size()]
		if stem == ending:
			continue
		var candidate := stem + ending
		if _reserve(registry, candidate, city_id):
			return candidate

	var serial := city_id + 1
	while true:
		var candidate := "承序" + _chinese_digits(serial)
		if _reserve(registry, candidate, city_id):
			return candidate
		serial += 1
	return ""


static func _allocate_dock_name(
	game_state,
	world_seed: int,
	dock_id: int,
	registry: Dictionary
) -> String:
	var anchor_id := _dock_anchor_id(game_state, dock_id)
	var anchor := (
		str(game_state.cities[anchor_id].name).strip_edges()
		if anchor_id >= 0 else "临水"
	)
	if anchor.is_empty():
		anchor = "临水"
	var suffix_start := stable_index(
		world_seed, dock_id, "city/dock/suffix", DOCK_SUFFIXES.size(), anchor_id
	)
	for offset in range(DOCK_SUFFIXES.size()):
		var suffix := DOCK_SUFFIXES[(suffix_start + offset) % DOCK_SUFFIXES.size()]
		var candidate := anchor + suffix
		if _reserve(registry, candidate, dock_id):
			return candidate
	var pair_count := DOCK_QUALIFIERS.size() * DOCK_SUFFIXES.size()
	var pair_start := stable_index(
		world_seed, dock_id, "city/dock/qualified", pair_count, anchor_id
	)
	for offset in range(pair_count):
		var pair := (pair_start + offset) % pair_count
		var candidate := (
			anchor
			+ DOCK_QUALIFIERS[pair / DOCK_SUFFIXES.size()]
			+ DOCK_SUFFIXES[pair % DOCK_SUFFIXES.size()]
		)
		if _reserve(registry, candidate, dock_id):
			return candidate
	var serial := dock_id + 1
	while true:
		var suffix := DOCK_SUFFIXES[suffix_start]
		var candidate := anchor + _chinese_digits(serial) + suffix
		if _reserve(registry, candidate, dock_id):
			return candidate
		serial += 1
	return ""


static func _allocate_regional_base(
	game_state,
	world_seed: int,
	nation_id: int,
	city_ids: Array[int],
	registry: Dictionary,
	domain: String,
	parent_id: int
) -> String:
	var ordered_city_ids := _ordered_region_city_ids(game_state, city_ids, nation_id)
	for city_id in ordered_city_ids:
		var candidate := _clean_regional_base(
			str(game_state.cities[city_id].name)
		)
		if _is_regional_base(candidate) and _reserve(registry, candidate, nation_id):
			return candidate

	var title_start := stable_index(
		world_seed, nation_id, domain + "/title", REGIONAL_TITLES.size(), parent_id
	)
	for offset in range(REGIONAL_TITLES.size()):
		var candidate := REGIONAL_TITLES[
			(title_start + offset) % REGIONAL_TITLES.size()
		]
		if _reserve(registry, candidate, nation_id):
			return candidate

	var pair_count := GEOGRAPHIC_STEMS.size() * REGION_ENDINGS.size()
	var pair_start := stable_index(
		world_seed, nation_id, domain + "/combination", pair_count, parent_id
	)
	for offset in range(pair_count):
		var pair := (pair_start + offset) % pair_count
		var stem := GEOGRAPHIC_STEMS[pair / REGION_ENDINGS.size()]
		var ending := REGION_ENDINGS[pair % REGION_ENDINGS.size()]
		if stem == ending:
			continue
		var candidate := stem + ending
		if _reserve(registry, candidate, nation_id):
			return candidate

	# 仍保持二字且不使用阿拉伯数字；仅在数千个地域组合全部耗尽时触发。
	var cjk_count := 0x9FFF - 0x4E00 + 1
	var first_start := stable_index(
		world_seed, nation_id, domain + "/cjk/a", cjk_count, parent_id
	)
	var second_start := stable_index(
		world_seed, nation_id, domain + "/cjk/b", cjk_count, parent_id
	)
	for offset in range(cjk_count):
		var candidate := (
			String.chr(0x4E00 + (first_start + offset) % cjk_count)
			+ String.chr(0x4E00 + (second_start + offset * 131) % cjk_count)
		)
		if _reserve(registry, candidate, nation_id):
			return candidate
	return "无名"


static func _assign_unique_ruler(
	nation,
	world_seed: int,
	identity: int,
	registry: Dictionary
) -> bool:
	var nation_id := int(nation.id)
	var current := str(nation.ruler_name).strip_edges()
	if not current.is_empty() and _reserve(registry, current, nation_id):
		if nation.ruler_name != current:
			nation.ruler_name = current
			return true
		return false
	var total := RULER_SURNAMES.size() * RULER_GIVEN_NAMES.size()
	var start := stable_index(
		world_seed, identity, "ruler/name", total, nation_id
	)
	for offset in range(total):
		var pair := (start + offset) % total
		var candidate := (
			RULER_SURNAMES[pair / RULER_GIVEN_NAMES.size()]
			+ RULER_GIVEN_NAMES[pair % RULER_GIVEN_NAMES.size()]
		)
		if _reserve(registry, candidate, nation_id):
			nation.ruler_name = candidate
			return true
	var serial := nation_id + 1
	while true:
		var candidate := RULER_SURNAMES[start % RULER_SURNAMES.size()] + _chinese_digits(serial)
		if _reserve(registry, candidate, nation_id):
			nation.ruler_name = candidate
			return true
		serial += 1
	return false


static func _normalize_existing_nation(nation, base: String, kind: String) -> bool:
	var changed := false
	var formal := base
	if kind == KIND_VASSAL:
		formal = base + "国"
	elif kind == KIND_REBEL:
		formal = base + "军"
	else:
		kind = _sovereign_kind(base)
	if nation.short_name != base:
		nation.short_name = base
		changed = true
	if nation.name != formal:
		nation.name = formal
		changed = true
	if nation.name_kind != kind:
		nation.name_kind = kind
		changed = true
	return changed


static func _ordered_region_city_ids(
	game_state,
	city_ids: Array[int],
	nation_id: int
) -> Array[int]:
	var unique: Dictionary = {}
	var valid: Array[int] = []
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		if (
			not unique.has(city_id)
			and _valid_city_id(game_state, city_id)
			and not game_state.cities[city_id].is_dock
		):
			unique[city_id] = true
			valid.append(city_id)
	if valid.is_empty():
		valid = _owned_land_city_ids(game_state, nation_id)
	if valid.is_empty():
		return valid
	var capital_id := -1
	if _valid_nation_id(game_state, nation_id):
		capital_id = int(game_state.nations[nation_id].capital_city_id)
	var centroid := Vector2.ZERO
	for city_id in valid:
		centroid += game_state.cities[city_id].map_position
	centroid /= float(valid.size())
	valid.sort_custom(func(a: int, b: int) -> bool:
		if a == capital_id:
			return b != capital_id
		if b == capital_id:
			return false
		var da: float = game_state.cities[a].map_position.distance_squared_to(centroid)
		var db: float = game_state.cities[b].map_position.distance_squared_to(centroid)
		if not is_equal_approx(da, db):
			return da < db
		return a < b
	)
	return valid


static func _dock_anchor_id(game_state, dock_id: int) -> int:
	if not _valid_city_id(game_state, dock_id):
		return -1
	var dock = game_state.cities[dock_id]
	var candidates: Array[int] = []
	var seen: Dictionary = {}
	var neighbors: Variant = game_state.adjacency.get(dock_id, [])
	if neighbors is Array:
		for neighbor_value in neighbors:
			var neighbor := int(neighbor_value)
			if (
				_valid_city_id(game_state, neighbor)
				and not game_state.cities[neighbor].is_dock
				and not seen.has(neighbor)
			):
				seen[neighbor] = true
				candidates.append(neighbor)
	if candidates.is_empty():
		for city_index in range(game_state.cities.size()):
			if not game_state.cities[city_index].is_dock:
				candidates.append(city_index)
	var best := -1
	var best_distance := INF
	for candidate in candidates:
		var distance: float = dock.map_position.distance_squared_to(
			game_state.cities[candidate].map_position
		)
		if (
			distance < best_distance
			or (is_equal_approx(distance, best_distance) and candidate < best)
		):
			best = candidate
			best_distance = distance
	return best


static func _owned_land_city_ids(game_state, nation_id: int) -> Array[int]:
	var result: Array[int] = []
	for city_index in range(game_state.cities.size()):
		var city = game_state.cities[city_index]
		if city.owner_nation == nation_id and not city.is_dock:
			result.append(city_index)
	return result


static func _sovereign_pool() -> Array[String]:
	var result: Array[String] = []
	_append_unique(result, DYNASTY_NAMES)
	_append_unique(result, WARRING_STATE_NAMES)
	_append_unique(result, SEPARATIST_STATE_NAMES)
	return result


static func _append_unique(target: Array[String], source: Array[String]) -> void:
	for value in source:
		if _is_single_character(value) and not target.has(value):
			target.append(value)


static func _sovereign_kind(candidate: String) -> String:
	if DYNASTY_NAMES.has(candidate):
		return KIND_DYNASTY
	if WARRING_STATE_NAMES.has(candidate):
		return KIND_WARRING_STATE
	return KIND_SEPARATIST


static func _nation_base(nation) -> String:
	var base := str(nation.short_name).strip_edges()
	if base.is_empty():
		base = str(nation.name).strip_edges()
	for suffix in ["义军", "国", "王", "军", "朝"]:
		if base.ends_with(suffix) and base.length() > suffix.length():
			base = base.substr(0, base.length() - suffix.length())
			break
	return base


static func _clean_regional_base(value: String) -> String:
	var result := value.strip_edges()
	for suffix in ["义军", "国", "王", "军"]:
		if result.ends_with(suffix) and result.length() > suffix.length():
			result = result.substr(0, result.length() - suffix.length())
			break
	if result.length() > 4:
		result = result.substr(0, 4)
	return result


static func _is_single_character(value: String) -> bool:
	return value.strip_edges().length() == 1


static func _is_regional_base(value: String) -> bool:
	var length := value.strip_edges().length()
	return length >= 2 and length <= 4


static func _position_sector(position: Vector2) -> int:
	var x := clampi(int(floor(position.x * 4.0)), 0, 3)
	var y := clampi(int(floor(position.y * 4.0)), 0, 3)
	return y * 4 + x


static func _chinese_digits(value: int) -> String:
	const DIGITS: Array[String] = [
		"零", "一", "二", "三", "四", "五", "六", "七", "八", "九",
	]
	var text := str(maxi(value, 0))
	var result := ""
	for index in range(text.length()):
		var digit := text.unicode_at(index) - 48
		result += DIGITS[clampi(digit, 0, 9)]
	return result


static func _reset_registries(game_state) -> void:
	game_state.set_meta(_NATION_REGISTRY_META, {})
	game_state.set_meta(_CITY_REGISTRY_META, {})
	game_state.set_meta(_CITY_SHORT_REGISTRY_META, {})
	game_state.set_meta(_RULER_REGISTRY_META, {})


static func _registry(game_state, key: StringName) -> Dictionary:
	var value: Variant = game_state.get_meta(key, {})
	if value is Dictionary:
		return value
	var created: Dictionary = {}
	game_state.set_meta(key, created)
	return created


static func _reserve(registry: Dictionary, value: String, owner_id: int) -> bool:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return false
	if registry.has(normalized) and int(registry[normalized]) != owner_id:
		return false
	registry[normalized] = owner_id
	return true


static func _backfill_nation_registry(
	game_state,
	registry: Dictionary,
	excluded_id: int
) -> void:
	for nation in game_state.nations:
		if int(nation.id) == excluded_id:
			continue
		var formal := str(nation.name).strip_edges()
		if formal.is_empty():
			formal = _nation_base(nation)
		if not formal.is_empty():
			_reserve(registry, formal, int(nation.id))


static func _backfill_city_registry(
	game_state,
	registry: Dictionary,
	excluded_id: int
) -> void:
	for city in game_state.cities:
		if int(city.id) == excluded_id:
			continue
		var assigned := str(city.name).strip_edges()
		if not assigned.is_empty():
			_reserve(registry, assigned, int(city.id))


static func _backfill_city_short_registry(
	game_state,
	registry: Dictionary,
	excluded_id: int
) -> void:
	for city in game_state.cities:
		if int(city.id) == excluded_id:
			continue
		var assigned := str(city.short_name).strip_edges()
		if _is_single_character(assigned):
			_reserve(registry, assigned, int(city.id))


static func _backfill_ruler_registry(
	game_state,
	registry: Dictionary,
	excluded_id: int
) -> void:
	for nation in game_state.nations:
		if int(nation.id) == excluded_id:
			continue
		var ruler := str(nation.ruler_name).strip_edges()
		if not ruler.is_empty():
			_reserve(registry, ruler, int(nation.id))


static func _valid_nation_id(game_state, nation_id: int) -> bool:
	return (
		game_state != null
		and nation_id >= 0
		and nation_id < game_state.nations.size()
	)


static func _valid_city_id(game_state, city_id: int) -> bool:
	return (
		game_state != null
		and city_id >= 0
		and city_id < game_state.cities.size()
	)


static func _valid_land_city_id(game_state, city_id: int) -> bool:
	return (
		_valid_city_id(game_state, city_id)
		and not game_state.cities[city_id].is_dock
	)


static func _bump_revision(game_state) -> void:
	game_state.naming_revision = int(game_state.naming_revision) + 1


static func _hash_step(seed_value: int, input_value: int) -> int:
	var seed_normalized := posmod(seed_value, HASH_MODULUS)
	var input_normalized := posmod(input_value, HASH_MODULUS)
	var mixed := posmod(
		seed_normalized + input_normalized * 1000003 + HASH_MULTIPLIER,
		HASH_MODULUS
	)
	mixed = mixed ^ (mixed >> 16)
	mixed = posmod(mixed * 73856093, HASH_MODULUS)
	mixed = mixed ^ (mixed >> 13)
	mixed = posmod(mixed * 19349663, HASH_MODULUS)
	return mixed ^ (mixed >> 16)
