class_name RegionalNames
extends RefCounted
const PATH := "res://assets/atlas/regional_names.json"
static var _data: Dictionary = {}
static var _reserved: Dictionary = {}
static var _fingerprint: String = ""

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		for pool in _data.pools.values():
			for character in str(pool.preferred)+str(pool.extension): _reserved[character] = true
	return _data

static func fingerprint() -> String:
	if _fingerprint.is_empty(): _fingerprint = FileAccess.get_file_as_string(PATH).sha256_text()
	return _fingerprint

static func reserved(character: String) -> bool:
	data()
	return _reserved.has(character)

static func capacity_error(profiles: Dictionary) -> String:
	var counts := {}
	for profile in profiles.values():
		var kind: String = profile.kind
		counts[kind] = int(counts.get(kind,0))+1
	for kind in NationEnvironment.KINDS:
		var pool: Dictionary = data().pools[kind]
		var capacity := str(pool.preferred).length()+str(pool.extension).length()
		if int(counts.get(kind,0)) > capacity:
			return "%s州治简称字库容量不足：需要 %d 个，仅有 %d 个。原地图已保留。"%[NationEnvironment.LABELS[kind],counts[kind],capacity]
	return ""

static func assign(state, seed: int, full_registry: Dictionary, short_registry: Dictionary, stable_index: Callable) -> void:
	var profiles: Dictionary = state.atlas_layout.nation_environment.profiles
	var capitals := {}
	for nation in state.nations: capitals[nation.capital_city_id] = true
	var ids: Array = profiles.keys()
	ids.sort_custom(func(a,b): return int(a)<int(b) if capitals.has(a)==capitals.has(b) else capitals.has(a))
	# Explicit legacy identities reserve first, including roots of later seats.
	for city in state.cities:
		if city.is_traffic: continue
		if not str(city.name).is_empty(): full_registry[str(city.name)]=int(city.id)
		if not str(city.short_name).is_empty(): short_registry[str(city.short_name)]=int(city.id)
	for id in ids:
		var city = state.cities[int(id)]
		if not str(city.name).is_empty() and not str(city.short_name).is_empty(): continue
		var kind: String = profiles[id].kind
		var pool: Dictionary = data().pools[kind]
		var root := ""
		for phase in ["preferred","extension"]:
			var chars: String = pool[phase]
			var start: int = stable_index.call(seed,int(id),"regional/"+kind+"/"+phase,chars.length())
			for offset in range(chars.length()):
				var candidate := chars.substr((start+offset)%chars.length(),1)
				if not short_registry.has(candidate): root=candidate; break
			if not root.is_empty(): break
		assert(not root.is_empty(), "Regional naming capacity must be checked before world installation")
		var suffixes: Array = pool.endings
		var start: int = stable_index.call(seed,int(id),"regional/full/"+kind,suffixes.size())
		var full := ""
		for offset in range(suffixes.size()):
			var candidate: String = root+str(suffixes[(start+offset)%suffixes.size()])
			if str(suffixes[(start+offset)%suffixes.size()]) != root and not full_registry.has(candidate): full=candidate; break
		assert(not full.is_empty())
		city.name=full; city.short_name=root
		full_registry[full]=int(id); short_registry[root]=int(id)
