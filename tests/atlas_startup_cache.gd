extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_STARTUP_CACHE_FAIL ",message)
func _initialize():
	var path := "res://scripts/atlas/startup_cache.gd"
	if not FileAccess.file_exists(path): check(false,"persistent generated-map cache is available"); quit(1); return
	var cache=load(path); var directory := "user://atlas_cache_test_%d"%OS.get_process_id()
	check(cache.key_for(7,1.,{"a":1,"b":2},"code")==cache.key_for(7,1.,{"b":2,"a":1},"code"),"option insertion order does not alter the cache key")
	var key := "fixture".sha256_text(); var other := "different parameters or source revision".sha256_text()
	var payload := {"payload":{"seed":7,"cities":[{"name":"甲"}],"pixels":PackedInt32Array([1,-1,2])},"display":{"field":PackedFloat32Array([1.25,2.5])}}
	check(cache.read(directory,key).is_empty(),"missing cache falls back to generation")
	check(cache.write(directory,key,payload)==OK,"complete data is published")
	check(var_to_bytes(cache.read(directory,key))==var_to_bytes(payload),"cache round trip preserves all numeric data")
	check(cache.read(directory,other).is_empty(),"different seed/options/source never reuses a previous world")
	var file: String=cache.path_for(directory,key); var bytes := FileAccess.get_file_as_bytes(file)
	var broken := bytes.duplicate(); broken[-1]=broken[-1]^1; FileAccess.open(file,FileAccess.WRITE).store_buffer(broken)
	check(cache.read(directory,key).is_empty(),"corrupt bytes are rejected before decoding")
	FileAccess.open(file,FileAccess.WRITE).store_buffer(bytes.slice(0,50))
	check(cache.read(directory,key).is_empty(),"partial writes cannot become a valid cache")
	check(cache.write(directory,key,payload)==OK and not cache.read(directory,key).is_empty(),"regeneration repairs a rejected cache")
	for i in range(5): cache.write(directory,str(i).sha256_text(),payload)
	check(DirAccess.get_files_at(directory).size()<=3,"obsolete seeds cannot grow the cache without a bound")
	check(not cache.read(directory,"4".sha256_text()).is_empty(),"the newest generated world survives same-second eviction")
	for name_value in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name_value))
	DirAccess.remove_absolute(directory)
	print("ATLAS_STARTUP_CACHE failures=",failures); quit(1 if failures else 0)
