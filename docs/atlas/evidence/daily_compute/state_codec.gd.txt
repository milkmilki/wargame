extends RefCounted
var records: Array = []
var ids := {}
var instances: Array = []
func encode(value: Variant) -> Variant:
	if value is Script: return {"@script":value.resource_path}
	if value is Object:
		var id: int = value.get_instance_id()
		if ids.has(id): return {"@ref":ids[id]}
		var index := records.size(); ids[id]=index
		var script: Script=value.get_script()
		var row := {"class":value.get_class(),"script":script.resource_path if script else "","properties":{}}
		records.append(row)
		for property in value.get_property_list():
			if property.name=="script": continue
			if (script and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or (not script and property.usage & PROPERTY_USAGE_STORAGE):
				row.properties[property.name]=encode(value.get(property.name))
		return {"@ref":index}
	if value is Array:
		var items: Array=[]
		for item in value: items.append(encode(item))
		return {"@array":items,"builtin":value.get_typed_builtin(),"class":value.get_typed_class_name(),"script":encode(value.get_typed_script())}
	if value is Dictionary:
		var items: Array=[]
		for key in value: items.append([encode(key),encode(value[key])])
		return {"@dict":items}
	assert(not value is Callable or not value.is_valid(),"Cannot freeze a valid callable")
	return null if value is Callable else value
func save(path: String,value: Variant):
	var root_value: Variant = encode(value)
	FileAccess.open(path,FileAccess.WRITE).store_var({"records":records,"root":root_value},false)
func decode(value: Variant) -> Variant:
	if not value is Dictionary: return value
	if value.has("@ref"): return instances[value["@ref"]]
	if value.has("@script"): return load(value["@script"])
	if value.has("@array"):
		var array: Array=[]
		if value.builtin != TYPE_NIL: array=Array([],value.builtin,value.class,decode(value.script))
		for item in value["@array"]: array.append(decode(item))
		return array
	var dictionary := {}
	for pair in value["@dict"]: dictionary[decode(pair[0])]=decode(pair[1])
	return dictionary
func restore(path: String, root_script: String = "") -> Variant:
	var snapshot: Dictionary=FileAccess.open(path,FileAccess.READ).get_var(false)
	for index in range(snapshot.records.size()):
		var row: Dictionary = snapshot.records[index]
		if index == int(snapshot.root["@ref"]) and not root_script.is_empty(): row.script = root_script
		if row.script=="res://scripts/ai/encirclement_index.gd": instances.append(load(row.script).new(null,-1))
		else: instances.append(load(row.script).new() if not row.script.is_empty() else ClassDB.instantiate(row.class))
	for index in range(instances.size()):
		var instance: Object=instances[index]
		for key in snapshot.records[index].properties:
			instance.set(key,decode(snapshot.records[index].properties[key]))
	return decode(snapshot.root)
