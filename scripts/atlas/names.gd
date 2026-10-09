extends RefCounted
## Original eastern grammar, candidate filters, recent roots and keyed streams.
## Port of gen/names/{index,eastern,spec,filters}.ts, 103afd3. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Western = preload("res://scripts/atlas/western_names.gd")
const KINDS = ["state","city","mountain","sea","river","region"]
const LIMITS = {"state":[2,5],"city":[2,5],"mountain":[2,7],"sea":[2,6],"river":[2,6],"region":[2,6]}
const PREFIXES = ["新","北","南","东","西","上","下","大","小","外","内"]
const LATIN_PREFIXES = ["New","North","South","East","West","Upper","Lower","Great","Little","Outer","Inner"]
var tables: Dictionary
var style: Dictionary
var style_id: String
var seed_value: int
var rng: Maths.Stream
var used := {}
var recent := {}
var western_tables: Dictionary
var western: RefCounted

func _init(seed_input: int = 1,style_input: String = "central") -> void:
	seed_value = seed_input; style_id = style_input
	tables = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas/eastern-names.json"))
	western_tables = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas/western-names.json"))
	for s in western_tables.styles:
		if s.id==style_id: style = s; western = Western.new(western_tables); break
	for s in tables.styles:
		if s.id==style_id: style = s; break
	assert(not style.is_empty(),"Unknown native name grammar: "+style_id)
	rng = Maths.Stream.new(Maths.sub_seed(seed_value,"names:"+style_id))

static func pick(r: Maths.Stream,items: Variant) -> Variant: return items[int(floor(r.next()*items.size()))] if items is Array else items[int(floor(r.next()*items.length()))]

static func weighted(r: Maths.Stream,items: Array) -> Variant:
	var total := 0.0
	for item in items: total += float(item[1])
	var value := r.next()*total
	for item in items:
		value -= float(item[1])
		if value<0: return item[0]
	return items[-1][0]

func generate_node(node: Dictionary,r: Maths.Stream) -> Variant:
	match node.op:
		"one": return pick(r,node.chars)
		"pair":
			var a: String = pick(r,node.a); var b: String = pick(r,node.b)
			for _t in range(4):
				if b!=a: break
				b = pick(r,node.b)
			return a+b
		"combos":
			var all: Array = []
			for group in node.spec.split(" ",false):
				var parts: PackedStringArray = group.split(":")
				for a in parts[0]:
					for b in parts[1]:
						if a!=b: all.append(a+b)
			return pick(r,all)
		"either": return generate_node(weighted(r,node.items),r)
		"named":
			var core: String = generate_node(node.core,r); var generics: Array = []
			for part in node.generics.split(" ",false):
				var parts: PackedStringArray = part.split(":"); generics.append(["" if parts[0]=="-" else parts[0],float(parts[1]) if parts.size()>1 else 1.0])
			var g: String = weighted(r,generics)
			return {"zh":core+g,"generic":g.substr(1) if g.begins_with("之") else g,"tokens":tokens(core)}
		"prefixed":
			var core: String = generate_node(node.core,r)
			return {"zh":pick(r,node.prefixes)+core+node.suffix,"generic":node.suffix,"tokens":tokens(core)}
	return null

static func tokens(text: String) -> Array:
	var out: Array = []
	for ch in text:
		if not "东西南北中外左右".contains(ch): out.append(ch)
	return out

func candidate(kind: String,r: Maths.Stream) -> Variant:
	if western!=null: return western.candidate(style,kind,r)
	var c: Dictionary = generate_node(weighted(r,style.kinds[kind]),r)
	var unique := {}; var all_ping := true; var all_ze := true
	for ch in c.zh:
		if unique.has(ch): return null
		unique[ch] = true
		var ze: bool = tables.ze.contains(ch); all_ping = all_ping and not ze; all_ze = all_ze and ze
	if c.zh.length()>=3:
		if all_ze: return null
		if c.zh.length()==3 and all_ping and r.next()<.4: return null
	return c

func blocked(text: String) -> bool:
	if tables.blocked.exact.has(text): return true
	for ch in text:
		if tables.blocked.chars.has(ch): return true
	for part in tables.blocked.substr:
		if text.contains(part): return true
	for i in range(1,text.length()):
		if text[i]==text[i-1]: return true
	for i in range(text.length()-3):
		if text[i]==text[i+2] and text[i+1]==text[i+3]: return true
	return false

func shape_ok(c: Dictionary,kind: String) -> bool:
	return c.zh.length()>=LIMITS[kind][0] and c.zh.length()<=LIMITS[kind][1] and not blocked(c.zh) and not latin_blocked(c.get("latin",""))

func latin_blocked(text: String) -> bool:
	if text.is_empty(): return false
	var w := ""
	for ch in text.to_lower():
		if "abcdefghijklmnopqrstuvwxyz ".contains(ch): w += ch
	for part in w.split(" "):
		if western_tables.blocked.exact.has(part): return true
	var joined := w.replace(" ","")
	for part in western_tables.blocked.substr:
		if joined.contains(part): return true
	return false

static func output(c: Dictionary) -> Dictionary:
	var out := {"zh":c.zh}
	if not c.get("latin","").is_empty(): out.latin = c.latin
	if not c.get("generic","").is_empty(): out.generic = c.generic
	return out

func name_value(kind: String) -> Dictionary:
	var roots: Array = recent.get(kind,[]); var best: Variant = null
	for t in range(80):
		var c = candidate(kind,rng)
		if c==null or used.has(c.zh) or not shape_ok(c,kind): continue
		var repeats := false
		for token in c.tokens:
			if roots.has(token): repeats = true; break
		if t<80*2.0/3 and repeats:
			if best==null: best = c
			continue
		best = c; break
	if best==null: best = fallback(kind)
	used[best.zh] = true; roots.append_array(best.tokens)
	while roots.size()>12: roots.pop_front()
	recent[kind] = roots
	return output(best)

func fallback(kind: String) -> Dictionary:
	var base: Variant = null
	for _t in range(160):
		var c = candidate(kind,rng)
		if c==null or blocked(c.zh) or latin_blocked(c.get("latin","")): continue
		if base==null: base = c
		if c.zh.length()>=LIMITS[kind][1]: continue
		for pi in range(PREFIXES.size()):
			var prefix: String = PREFIXES[pi]
			var text: String = prefix+c.zh
			if not used.has(text) and not blocked(text):
				var out: Dictionary = c.duplicate(); out.zh = text; out.tokens = []
				if c.has("latin"): out.latin = LATIN_PREFIXES[pi]+" "+c.latin
				return out
	if base==null: base = {"zh":"无名河" if kind=="river" else "无名地","tokens":[]}
	var n := 2
	while true:
		var text: String = base.zh+cn_number(n)
		if not used.has(text):
			var out: Dictionary = base.duplicate(); out.zh = text; out.tokens = []
			if base.has("latin"): out.latin = base.latin+" "+str(n)
			return out
		n += 1
	return {}

static func cn_number(n: int) -> String:
	var d := "零一二三四五六七八九"
	if n<10: return d[n]
	if n<20: return "十"+(d[n%10] if n%10 else "")
	if n<100: return d[n/10]+"十"+(d[n%10] if n%10 else "")
	var rest := n%100
	return cn_number(n/100)+"百"+("" if rest==0 else "零"+d[rest] if rest<10 else "一"+cn_number(rest) if rest<20 else cn_number(rest))

func keyed(kind: String,keys: Array) -> KeyedStream:
	var h := Maths.fmix(Maths.sub_seed(seed_value,"names-keyed:"+style_id)^(((KINDS.find(kind)+1)*0x27d4eb2f)&0xffffffff))
	for key in keys: h = Maths.fmix(h^((int(key)*0x9e3779b1)&0xffffffff))
	return KeyedStream.new(self,kind,Maths.Stream.new(h))

static func assign(data: Dictionary) -> void:
	var namer = load("res://scripts/atlas/names.gd").new(int(data.seed),"central")
	var taken := {}
	var region_names: Array = []
	for r in range(data.regions.count):
		var stream = namer.keyed("region",[int(data.regions.seat[r])]); var value: Dictionary = stream.next()
		while taken.has(value.zh): value = stream.next()
		taken[value.zh] = true; region_names.append(value.zh)
	data.regions.names = region_names
	for city in data.cities:
		var stream = namer.keyed("city",[int(city.cell)]); var value: Dictionary = stream.next()
		while taken.has(value.zh): value = stream.next()
		taken[value.zh] = true; city.name = value.zh
	for nation in data.nations:
		var stream = namer.keyed("state",[int(data.regions.seat[nation.seat])]); var value: Dictionary = stream.next()
		while taken.has(value.zh): value = stream.next()
		taken[value.zh] = true; nation.name = value.zh

class KeyedStream:
	var namer: RefCounted
	var kind: String
	var stream: Maths.Stream
	var firsts: Array = []
	var given := 0
	var fb := 0
	func _init(n: RefCounted,k: String,r: Maths.Stream) -> void: namer = n; kind = k; stream = r
	func next() -> Dictionary:
		while given<48:
			var c: Variant = null
			for _t in range(80):
				var x = namer.candidate(kind,stream)
				if x!=null and namer.shape_ok(x,kind): c = x; break
			if c==null: break
			given += 1
			if firsts.size()<3: firsts.append(c)
			return namer.output(c)
		given = 48
		var bases: Array = firsts if not firsts.is_empty() else [{"zh":"无名河" if kind=="river" else "无名地","tokens":[]}]
		var prefixed: Array = []
		for c in bases:
			if c.zh.length()>=namer.LIMITS[kind][1]: continue
			for pi in range(namer.PREFIXES.size()):
				var prefix: String = namer.PREFIXES[pi]
				var text: String = prefix+c.zh
				if not namer.blocked(text):
					var out: Dictionary = c.duplicate(); out.zh = text; out.tokens = []
					if c.has("latin"): out.latin = namer.LATIN_PREFIXES[pi]+" "+c.latin
					prefixed.append(out)
		var c: Dictionary
		if fb<prefixed.size(): c = prefixed[fb]
		else:
			var k := fb-prefixed.size(); c = bases[k%bases.size()].duplicate()
			c.zh += namer.cn_number(2+k/bases.size()); c.tokens = []
			if c.has("latin"): c.latin += " "+str(2+k/bases.size())
		fb += 1; return namer.output(c)
