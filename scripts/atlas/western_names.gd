extends RefCounted
## gen/names/western.ts, civ-atlas 103afd3. AGPL-3.0-only.
const Transcribe = preload("res://scripts/atlas/transcribe.gd")
const Maths = preload("res://scripts/atlas/math.gd")
const SONOR = ["l","r","n","m","s"]
const OBSTR = ["b","d","g","k","p","t","f","v","th","kh","gh"]
const BAD = ["sr","sz","nm","mn","ml","mr","nl","lr","ms","mz","ns","nz"]
const TRIPLES = ["str","spr","skr","ndr","ntr","nst","rst","nsk","rsk","lsk","lst","mbr","ngr","ldr","rth","nth","lth","rsh"]
var transcriber: RefCounted
func _init(tables: Dictionary) -> void: transcriber = Transcribe.new(tables.transcription)
static func pick(r: Maths.Stream,list: Array) -> Variant: return list[floori(r.next()*list.size())]
static func weighted(r: Maths.Stream,list: Array) -> Variant:
	var total := 0.0
	for item in list: total += float(item.w)
	var x := r.next()*total
	for item in list:
		x -= float(item.w)
		if x<0: return item.item
	return list[-1].item
static func is_vowel(ch: String) -> bool: return not ch.is_empty() and "aeiouy".contains(ch)
static func cluster_ok(text: String) -> bool:
	var units: Array = []; var i := 0
	while i<text.length():
		var pair := text.substr(i,2)
		if pair in ["th","sh","ch","kh","gh","ph","dh"]: units.append(pair); i += 2
		else: units.append(text[i]); i += 1
	if units.size()<=1: return true
	if units.size()==2:
		var x: String = units[0]; var y: String = units[1]
		if x==y or x+y in BAD: return false
		return x in SONOR or (y in ["l","r"] and x in OBSTR and x+y not in ["dl","tl"]) or x+y in ["ks","ps","ft","kt","pt","sv","tv","dv","sk","st"]
	return units.size()==3 and text in TRIPLES
static func append(segs: Array,part: Dictionary,link: String) -> bool:
	if part.l.is_empty(): return true
	var b := part.duplicate()
	if segs.is_empty() or (segs[-1].has("zh") and b.has("zh")): segs.append(b); return true
	var a: Dictionary = segs[-1]; var ending: String = a.l[-1]; var start: String = b.l[0]
	if is_vowel(ending) and is_vowel(start):
		if not a.get("zh",""):
			a.l = a.l.left(-1)
			if a.l.is_empty(): segs.pop_back()
		elif not b.get("zh","") and b.l.length()>1: b.l = b.l.substr(1)
	elif not is_vowel(ending) and not is_vowel(start):
		var trailing := ""; var leading := ""
		for i in range(a.l.length()-1,-1,-1):
			if is_vowel(a.l[i]): break
			trailing = a.l[i]+trailing
		for ch in b.l:
			if is_vowel(ch): break
			leading += ch
		var ok: bool = (trailing+leading).length()<=3 if b.has("zh") else cluster_ok(trailing+leading)
		if not ok:
			if not a.get("zh",""): a.l += link
			elif not b.get("zh",""): b.l = link+b.l
			else: return false
	segs.append(b); return true
func render(segs: Array,options: Dictionary) -> Dictionary:
	var latin := ""; var zh := ""; var pending := ""
	for s in segs:
		latin += s.l
		if not s.has("zh"): pending += s.l
		else:
			if not pending.is_empty(): zh += transcriber.convert(pending,options)
			pending = ""; zh += s.zh
	if not pending.is_empty(): zh += transcriber.convert(pending,options)
	return {"latin":latin[0].to_upper()+latin.substr(1),"zh":zh}
static func latin_shape_ok(text: String) -> bool:
	var s := text.to_lower()
	for pattern in ["[aeiou]{3}","(aa|ii|uu|ee|oo|yy)","[^aeiouy]{4}","nen"]:
		var re := RegEx.new(); re.compile(pattern)
		if re.search(s)!=null: return false
	return true
func root(style: Dictionary,kind: String,r: Maths.Stream) -> Variant:
	var rule: Dictionary = style.kinds[kind]; var stem: Dictionary = pick(r,rule.get("stems",style.stems)); var segs: Array = []
	append(segs,stem,style.link); var tokens: Array = [stem.l]
	if rule.mid>0 and r.next()<rule.mid:
		var mid: Dictionary = pick(r,style.mids)
		if not append(segs,mid,style.link): return null
		tokens.append(stem.l+mid.l)
	var end: Dictionary = weighted(r,rule.ends)
	if not append(segs,end,style.link): return null
	var result := render(segs,style.tr)
	for s in segs:
		if not s.has("zh") and not latin_shape_ok(result.latin): return null
	if result.zh.length()<2 or ((end.has("zh") or kind in ["state","city","region"]) and result.zh.length()<3): return null
	result.tokens = tokens
	if end.get("gen",false): result.generic = end.zh
	return result
func candidate(style: Dictionary,kind: String,r: Maths.Stream) -> Variant:
	if style.has("epithet") and kind in ["sea","mountain"] and r.next()<style.epithet.chance:
		var pair: PackedStringArray = pick(r,style.epithet[kind]).split("|")
		var result := {"zh":pair[0],"latin":pair[1],"tokens":[pair[1]]}
		if kind=="sea": result.generic = "海"
		elif pair[0].ends_with("山脉"): result.generic = "山脉"
		return result
	var result = root(style,kind,r)
	if result==null or result.has("generic"): return result
	match kind:
		"mountain":
			if r.next()<style.get("mount",.15): result.zh += "山"; result.latin = "Mount "+result.latin; result.generic = "山"
			else: result.zh += "山脉"; result.latin += " Mountains"; result.generic = "山脉"
		"sea": result.zh += "海"; result.latin += " Sea"; result.generic = "海"
		"river": result.zh += "河"; result.latin += " River"; result.generic = "河"
	return result
