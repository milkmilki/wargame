extends RefCounted
## Test-only object graph storage. Keeps shared Edge/Army references and typed arrays.
## Mutexes are recreated by constructors; no engine object decoder is used on files.
const FORMAT := "wargame-native-runtime-fixture-v1"
var _indices: Dictionary = {}
var _records: Array = []
var _objects: Array = []

func pack(state:GameState)->Dictionary:
	_indices.clear()
	_records.clear()
	var reference:Variant=_encode(state)
	return {"format":FORMAT,"root":reference,"objects":_records}

func unpack(payload:Dictionary)->GameState:
	assert(payload.get("format")==FORMAT,"Invalid test fixture format")
	var records:Array=payload.objects
	_objects.clear()
	for record in records:
		if record.kind=="rng": _objects.append(RandomNumberGenerator.new())
		else:
			var script:Script=load(record.script)
			assert(script!=null and record.script.begins_with("res://scripts/"),"Unsupported test fixture class")
			_objects.append(script.new())
	for index in range(records.size()):
		var record:Dictionary=records[index]
		var object:Object=_objects[index]
		if record.kind=="rng":
			object.seed=record.seed
			object.state=record.state
		else:
			for pair in record.properties: object.set(pair[0],_decode(pair[1]))
			for pair in record.meta: object.set_meta(pair[0],_decode(pair[1]))
	return _decode(payload.root) as GameState

func _encode(value:Variant)->Variant:
	if value is Object:
		if value==null or value is Mutex: return ["skip"]
		var instance_id:int=value.get_instance_id()
		if _indices.has(instance_id): return ["ref",_indices[instance_id]]
		var index:=_records.size()
		_indices[instance_id]=index
		_records.append({})
		if value is RandomNumberGenerator:
			_records[index]={"kind":"rng","seed":value.seed,"state":value.state}
		else:
			var script:Script=value.get_script()
			assert(script!=null,"Unsupported test fixture object "+value.get_class())
			var properties:Array=[]
			for property in value.get_property_list():
				var name:String=property.name
				if name in ["script","is_traffic"] or int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE==0: continue
				var property_value:Variant=value.get(name)
				if property_value is Mutex: continue
				properties.append([name,_encode(property_value)])
			var meta:Array=[]
			for key in value.get_meta_list(): meta.append([key,_encode(value.get_meta(key))])
			_records[index]={"kind":"script","script":script.resource_path,"properties":properties,"meta":meta}
		return ["ref",index]
	if value is Array:
		var contents:Array=[]
		for item in value: contents.append(_encode(item))
		var typed_script:Variant=value.get_typed_script()
		return ["array",value.get_typed_builtin(),value.get_typed_class_name(),typed_script.resource_path if typed_script is Script else "",contents]
	if value is Dictionary:
		var entries:Array=[]
		for key in value: entries.append([_encode(key),_encode(value[key])])
		return ["dict",entries]
	return ["value",value]

func _decode(value:Array)->Variant:
	match value[0]:
		"ref": return _objects[int(value[1])]
		"array":
			var contents:Array=[]
			for item in value[4]: contents.append(_decode(item))
			if int(value[1])!=TYPE_NIL:
				return Array(contents,int(value[1]),StringName(value[2]),load(value[3]) if not str(value[3]).is_empty() else null)
			return contents
		"dict":
			var result:Dictionary={}
			for entry in value[1]: result[_decode(entry[0])]=_decode(entry[1])
			return result
		"skip": return null
	return value[1]

static func hash_bytes(value:PackedByteArray)->String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()

static func snapshot(state:GameState)->Dictionary:
	return {"native":NativeSnapshotBuilder.build(state),"rng_seed":state.rng.seed,"month":state.month,"war_objectives":state.war_objectives.duplicate(true),"diplomatic_relations":state.diplomatic_relations.duplicate(true),"generation_metadata":state.generation_metadata.duplicate(true)}

static func validate_world(state:GameState,seed_value:int,initial_state:bool=true)->String:
	if state.world_seed!=seed_value: return "unexpected seed"
	if initial_state and state.nations.size()!=40: return "expected initial 40 nations"
	if not state.trade_enabled or not state._random_ruler_profiles_enabled: return "trade and rulers must be enabled"
	var mask:Dictionary=state.map_models.get("settlement_mask",{})
	if mask.is_empty(): mask=state.atlas_layout.get("settlement_mask",{})
	if mask.is_empty(): mask=state.generation_metadata.get("options",{}).get("settlement_mask",{})
	if mask!=preload("res://scripts/atlas/settlement_mask.gd").EURASIA: return "actual EURASIA settlement mask differs: "+str(state.generation_metadata)
	return ""
