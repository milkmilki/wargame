extends RefCounted
## Disposable generated inputs, never a running GameState or saved campaign.
const REVISION := "atlas-startup-v1"
const MAGIC := "ATSTART1"
const HEADER := 120
const LIMIT := 768*1024*1024
const DIRECTORY := "user://atlas_startup_cache"
static func path_for(directory: String,key: String) -> String:
	return directory.path_join(REVISION+"-"+key+".bin")
static func digest(bytes: PackedByteArray) -> PackedByteArray:
	var hash_value := HashingContext.new(); hash_value.start(HashingContext.HASH_SHA256); hash_value.update(bytes); return hash_value.finish()
static func key_for(seed_value: int,threshold: float,options: Dictionary,source: String) -> String:
	var version: Dictionary=Engine.get_version_info()
	var keys: Array=options.keys(); keys.sort(); var normalized: Array=[]
	for key in keys: normalized.append([key,options[key]])
	return JSON.stringify([REVISION,version.major,version.minor,version.patch,seed_value,threshold,normalized,source]).sha256_text()
static func read(directory: String,key: String) -> Dictionary:
	var file := FileAccess.open(path_for(directory,key),FileAccess.READ)
	if file==null or file.get_length()<HEADER: return {}
	if file.get_buffer(8).get_string_from_utf8()!=MAGIC or file.get_buffer(64).get_string_from_utf8()!=key: return {}
	var size_value := file.get_64(); var compressed_size := file.get_64(); var expected := file.get_buffer(32)
	if size_value<4 or size_value>LIMIT or compressed_size<=0 or compressed_size>LIMIT or file.get_length()!=HEADER+compressed_size: return {}
	var compressed := file.get_buffer(compressed_size)
	if digest(compressed)!=expected: return {}
	var bytes := compressed.decompress(size_value,FileAccess.COMPRESSION_ZSTD)
	if bytes.size()!=size_value: return {}
	var value = bytes_to_var(bytes) # Object decoding stays disabled.
	return value if value is Dictionary and value.get("payload") is Dictionary and value.get("display") is Dictionary else {}
static func write(directory: String,key: String,value: Dictionary) -> Error:
	var bytes := var_to_bytes(value)
	if bytes.size()>LIMIT: return ERR_OUT_OF_MEMORY
	var compressed := bytes.compress(FileAccess.COMPRESSION_ZSTD)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error!=OK: return error
	var path := path_for(directory,key); var temporary := path+".%d.tmp"%OS.get_process_id()
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return FileAccess.get_open_error()
	file.store_buffer(MAGIC.to_utf8_buffer()); file.store_buffer(key.to_utf8_buffer())
	file.store_64(bytes.size()); file.store_64(compressed.size()); file.store_buffer(digest(compressed)); file.store_buffer(compressed); file.flush()
	error=file.get_error(); file.close()
	if error!=OK: DirAccess.remove_absolute(temporary); return error
	# Only our disposable file is replaced; a failed write preserves the old one.
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	error=DirAccess.rename_absolute(temporary,path)
	if error!=OK: DirAccess.remove_absolute(temporary); return error
	var entries: Array = []
	for name_value in DirAccess.get_files_at(directory):
		if name_value.begins_with(REVISION+"-") and name_value.ends_with(".bin"):
			var entry := directory.path_join(name_value)
			entries.append({"path":entry,"modified":FileAccess.get_modified_time(entry)})
	entries.sort_custom(func(a,b): return a.modified<b.modified if a.modified!=b.modified else a.path<b.path)
	var count := entries.size()
	while count>3 and not entries.is_empty():
		var old: Dictionary=entries.pop_front()
		if old.path!=path: DirAccess.remove_absolute(old.path); count-=1
	return OK
