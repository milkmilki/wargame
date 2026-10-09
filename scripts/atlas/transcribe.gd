extends RefCounted
## gen/names/transcribe.ts, civ-atlas 103afd3. AGPL-3.0-only.
var tables: Dictionary
var base := {}
func _init(value: Dictionary) -> void:
	tables = value
	for onset in tables.rows:
		for i in range(tables.cols.size()): base[onset+tables.cols[i]] = tables.rows[onset][i]

static func vowel(ch: String) -> bool: return not ch.is_empty() and "aeiou".contains(ch)
static func replace_pattern(text: String,pattern: String,replacement: String) -> String:
	var re := RegEx.new(); re.compile(pattern); return re.sub(text,replacement,true)

func tokenize(word: String,j_as_y: bool) -> Array:
	var s := replace_pattern(word.to_lower(),"[^a-z]","")
	for pair in [["ph","f"],["ck","k"],["qu","kv"],["q","k"],["x","ks"]]: s = s.replace(pair[0],pair[1])
	s = replace_pattern(s,"c(?!h)(?=[eiy])","s"); s = replace_pattern(s,"c(?!h)","k")
	s = replace_pattern(s,"([bdfgklprstvz])\\1","$1"); s = replace_pattern(s,"(n)n(?![aeiouy])","$1"); s = replace_pattern(s,"(m)m(?![aeiouy])","$1")
	var out: Array = []; var i := 0
	while i<s.length():
		var ch := s[i]; var next := s[i+1] if i+1<s.length() else ""; var two := s.substr(i,2); var third := s[i+2] if i+2<s.length() else ""
		if ch=="y": out.append({"c":"y"} if vowel(next) else {"v":"i"}); i += 1; continue
		if ch=="w":
			if vowel(next): out.append({"c":"w"})
			elif not out.is_empty() and out[-1].has("v"): out[-1].v += "u"
			i += 1; continue
		if vowel(ch):
			if tables.diph.has(two) and not vowel(third): out.append({"v":tables.diph[two]}); i += 2
			else: out.append({"v":ch}); i += 1
			continue
		if ch=="j": out.append({"c":"y" if j_as_y else "j"}); i += 1; continue
		if next=="h" and "sctkgdz".contains(ch): out.append({"c":"z" if two=="zh" else two}); i += 2; continue
		if ch=="h":
			if vowel(next) or next=="y": out.append({"c":"h"})
			elif not out.is_empty() and out[-1].has("v") and not next.is_empty(): out.append({"c":"H"})
			i += 1; continue
		if two=="ts" and (vowel(third) or i+2==s.length()): out.append({"c":"ts"}); i += 2; continue
		assert("bcdfgklmnprstvz".contains(ch),"Unsupported transcription letter: "+ch)
		out.append({"c":ch}); i += 1
	return out

static func syllabify(tokens: Array) -> Array:
	var out: Array = []; var i := 0; var previous: Variant = null
	while i<tokens.size():
		var cons: Array = []
		while i<tokens.size() and tokens[i].has("c"): cons.append(tokens[i].c); i += 1
		var v: Variant = tokens[i].v if i<tokens.size() else null; var start := 0
		if previous!=null and not cons.is_empty() and not (v!=null and cons.size()==1):
			if cons[0]=="n" and cons.size()==2 and cons[1]=="g" and v==null: out[-1].nasal = "ng"; start = 2
			elif cons[0]=="n" or (cons[0]=="m" and cons.size()>1 and cons[1] in ["b","p"]): out[-1].nasal = "n"; start = 1
			elif cons[0]=="H" and cons.size()==1 and v==null: start = 1
		for k in range(start,cons.size()-(1 if v!=null else 0)): out.append({"onset":"h" if cons[k]=="H" else cons[k],"vowel":null})
		if v==null: break
		var onset: String = cons[-1] if cons.size()>start else ""
		out.append({"onset":"h" if onset=="H" else onset,"vowel":v,"after_front":onset.is_empty() and previous in ["i","e"]})
		previous = v; i += 1
	return out

func convert(latin: String,options: Dictionary) -> String:
	var over: Dictionary = options.get("table",{}); var syllables := syllabify(tokenize(latin,options.get("jAsY",false))); var out := ""
	for k in range(syllables.size()):
		var s: Dictionary = syllables[k]; var onset: String = s.onset
		if s.vowel==null:
			if onset in ["f","v"] and k+1<syllables.size() and syllables[k+1].onset in ["l","r"]: out += over.get("-"+onset+"r","弗")
			else: out += over.get("-"+onset,tables.lone[onset])
			continue
		var v: String = s.vowel; var nasal: String = s.get("nasal","")
		if onset.is_empty() and s.after_front and v=="a": out += over.get("yan","安") if not nasal.is_empty() else over.get("ya","亚"); continue
		if onset.is_empty() and s.after_front and v=="o" and not nasal.is_empty(): out += over.get("yon","昂"); continue
		if v=="oi": out += over.get(onset+"o",base.get(onset+"o",""))+"伊"; continue
		if not nasal.is_empty():
			var key := onset+("ang" if v=="a" else "ong" if v=="o" else v+"n") if nasal=="ng" else onset+v+"n"
			out += over.get(key,base.get(key,over.get(onset+v,base.get(onset+v,""))+"恩")); continue
		out += over.get(onset+v,base.get(onset+v,tables.lone.get(onset,"")+over.get(v,base.get(v,""))))
	return out
