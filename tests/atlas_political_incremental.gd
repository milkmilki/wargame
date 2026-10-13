extends SceneTree
## Real Eurasia geometry, immutable published caches, and independent complete
## GDScript recomputation. This test never rewrites a developer fixture or log.
const Display = preload("res://scripts/atlas/political_display.gd")
const Borders = preload("res://scripts/atlas/borders.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Zoom = preload("res://scripts/atlas/zoom_geometry.gd")
const Wash = preload("res://scripts/atlas/wash.gd")
const Labels = preload("res://scripts/atlas/polity_labels.gd")
const Mask = preload("res://scripts/atlas/settlement_mask.gd")
const FIXTURE := "res://.dbg/atlas-military-eurasia-mask.bin"
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready(): pass
var failures := 0
var checks := 0
var source: GameState
var provinces := PackedInt32Array()
var grid := PackedInt32Array()
var base_input := {}
var display_service: RefCounted = Display.new()
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks += 1
	if not ok: failures += 1; printerr("POLITICAL_INCREMENTAL_FAIL ",message)
func finish():
	print("ATLAS_POLITICAL_INCREMENTAL checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func full_reference(input: Dictionary) -> Dictionary:
	var lines := Borders.build(input.chains,input.ownership,input.mesh,input.raster,input.region_of)
	var labels := PackedInt32Array(); labels.resize(input.provinces.size())
	for i in range(labels.size()): labels[i] = input.ownership[input.provinces[i]] if input.provinces[i] >= 0 else -2
	Geometry.band_labels(labels,2048,1024,lines,input.weak)
	return {"lines":lines,"index":Zoom.build(lines),"labels":labels,
		"edge":Wash.edge_data(labels,2048,1024),
		"names":Labels.fit_all(input.data,Labels.field(grid,input.ownership,512,256))}
func request(cache: Dictionary,owners: PackedInt32Array,nations: Array = []) -> Dictionary:
	var input: Dictionary = base_input.duplicate()
	input.ownership = owners.duplicate(); input.cache = cache
	input.data = base_input.data.duplicate()
	input.data.ownership = input.ownership
	input.data.nations = base_input.data.nations.duplicate(true) if nations.is_empty() else nations.duplicate(true)
	return input
func published_signature(cache: Dictionary) -> int:
	return hash([cache.get("ownership"),cache.get("labels"),cache.get("lines"),cache.get("names"),cache.get("tiles"),cache.get("tile_hashes")])
func run():
	if not display_service.has_method("initialize"):
		check(false,"political display can initialize an immutable incremental cache")
		finish(); return
	if not FileAccess.file_exists(FIXTURE):
		check(false,"the existing Eurasia fixture is available for read-only regression")
		finish(); return
	var payload: Dictionary = FileAccess.open(FIXTURE,FileAccess.READ).get_var(false)
	check(int(payload.data.seed) == 1 and payload.data.options.settlement_mask == Mask.EURASIA,"the actual fixture is Earth seed 1 with enabled 20–55/-15–145 Eurasia mask")
	source = GameState.new(); source.generate_from_atlas(payload)
	check(source.world_seed == 1 and source.nations.size() == 40,"the actual military fixture contains the agreed initial 40 countries")
	var view := View.new(); view.state = source; view.military_payload = payload
	var data: Dictionary = view.visual_data(); view.free()
	var rng_before := source.rng.state
	var model_before := hash([source.ownership_revision,source.province_ids,source.cities.map(func(city): return [city.owner_nation,city.map_position])])
	provinces = payload.district_pixels
	var weak := PackedByteArray(); weak.resize(provinces.size())
	for i in range(provinces.size()): weak[i] = int(payload.raster.water[i] == 0 and data.regions.of[payload.raster.cell[i]] < 0)
	grid.resize(512*256)
	for y in range(256):
		for x in range(512): grid[y*512+x] = provinces[(y*4+2)*2048+x*4+2]
	base_input = {"chains":Borders.trace(data.mesh,PackedInt32Array(data.regions.of)),
		"ownership":PackedInt32Array(data.ownership),"mesh":data.mesh,"raster":payload.raster,
		"region_of":PackedInt32Array(data.regions.of),"provinces":provinces,"weak":weak,
		"fronts":{"roles":{},"signature":0},"data":{"mesh":data.mesh,"regions":data.regions,
			"ownership":PackedInt32Array(data.ownership),"nations":data.nations}}
	var reference := full_reference(base_input)
	var geo := {"lines":reference.lines,"political_index":reference.index,"political_labels":reference.labels,"names":reference.names}
	var cache: Dictionary = display_service.call("initialize",base_input,geo)
	check(cache.has("ownership") and cache.has("labels") and cache.has("region_tiles") and cache.has("tiles"),"initialized display cache retains geometry, owners and reusable upload tiles")
	if not cache.has("labels"): finish(); return
	check(cache.labels == reference.labels,"initial cache preserves the published political picking raster")
	check(var_to_bytes(cache.names) == var_to_bytes(reference.names),"initial cache preserves complete published label layouts")
	check(var_to_bytes(cache.grid) == var_to_bytes(grid),"coarse label field samples the actual province raster")
	test_complete_native_labels(base_input,reference.names)
	var unchanged := verify_result(request(cache,base_input.ownership),"unchanged revision",reference)
	check(unchanged.get("dirty_tiles",PackedInt32Array()).is_empty() and unchanged.get("tile_updates",[]).is_empty(),"unchanged political state requests no pixel uploads")
	var targets := small_border_districts(payload,data.ownership)
	check(targets.size() >= 2,"the real fixture contains small independently occupiable border府")
	if targets.size() < 2: finish(); return
	var target: int = targets[0].city; var old_owner: int = data.ownership[target]; var other_owner: int = targets[0].owner
	var old_cache_signature := published_signature(cache)
	var small_owners: PackedInt32Array = base_input.ownership.duplicate(); small_owners[target] = other_owner
	var first := verify_result(request(cache,small_owners),"small府 occupation")
	check(first.get("dirty_tiles",PackedInt32Array()).size() > 0 and first.get("dirty_tiles",PackedInt32Array()).size() < 128,"small府 occupation only publishes part of the world raster")
	check(published_signature(cache) == old_cache_signature,"a worker update cannot mutate the still-visible previous cache")
	if not first.has("cache"): finish(); return
	await process_frame
	var restored := verify_result(request(first.cache,base_input.ownership),"restore historical owners",reference)
	check(restored.get("labels",PackedInt32Array()) == reference.labels,"restoring history rebuilds the original smoothed political border exactly")
	await process_frame
	# Multiple ownership commits may arrive while one older result is pending.
	# Calculate their latest combined input from the original published cache.
	var latest_owners := small_owners.duplicate(); latest_owners[targets[1].city] = targets[1].owner
	var latest := verify_result(request(cache,latest_owners),"coalesced multiple府 changes")
	check(published_signature(cache) == old_cache_signature,"independent pending results retain the same original immutable cache")
	if not latest.has("cache"): finish(); return
	await process_frame
	var merged_owners := latest_owners.duplicate()
	for city in range(merged_owners.size()):
		if merged_owners[city] == old_owner: merged_owners[city] = other_owner
	var merged := verify_result(request(latest.cache,merged_owners),"remove a country's political borders")
	check(merged.get("lines",[]).all(func(border): return border.left != old_owner and border.right != old_owner),"a fully absorbed country leaves no obsolete political border")
	check(merged.get("names",[]).all(func(label): return label.polity != old_owner),"a country with no districts loses its political label")
	if not merged.has("cache"): finish(); return
	await process_frame
	var returned := verify_result(request(merged.cache,base_input.ownership),"add borders when leaving history",reference)
	check(returned.get("lines",[]).any(func(border): return border.left == old_owner or border.right == old_owner),"restored territory recreates the country's removed borders")
	if not returned.has("cache"): finish(); return
	await process_frame
	var front_input := request(returned.cache,base_input.ownership)
	var border: Dictionary = reference.lines[0]
	var key := "%d:%d" % [mini(border.left,border.right),maxi(border.left,border.right)]
	front_input.fronts = {"roles":{key:border.right},"signature":1}
	var front_only := verify_result(front_input,"diplomacy front-only",reference)
	check(front_only.get("dirty_tiles",PackedInt32Array()).is_empty() and front_only.get("tile_updates",[]).is_empty(),"a new war-front classification does not repaint political pixels")
	check(not front_only.get("stroke_plans",{}).get("front",[]).is_empty(),"diplomacy still publishes the actual frontier drawing")
	await process_frame
	var renamed_nations: Array = base_input.data.nations.duplicate(true)
	renamed_nations[old_owner].name += "新"
	var renamed := verify_result(request(returned.cache,base_input.ownership,renamed_nations),"country title-only change")
	check(renamed.get("dirty_tiles",PackedInt32Array()).is_empty() and renamed.get("tile_updates",[]).is_empty(),"renaming a country updates its layout without repainting political pixels")
	check(renamed.get("names",[]).any(func(label): return label.polity == old_owner and label.text == renamed_nations[old_owner].name),"the changed country title is actually published")
	check(source.rng.state == rng_before,"all cached/full display calculations preserve the simulation random stream")
	check(hash([source.ownership_revision,source.province_ids,source.cities.map(func(city): return [city.owner_nation,city.map_position])]) == model_before,"display fixtures never modify simulation territory or map geometry")
	finish()
func test_complete_native_labels(input: Dictionary,expected: Array):
	if not ClassDB.class_exists("NativeAtlasDisplay"):
		check(false,"complete label equivalence uses the actual native display kernel"); return
	var native: RefCounted = ClassDB.instantiate("NativeAtlasDisplay")
	var field: Dictionary = native.call("label_field",grid,input.ownership,512,256)
	var before := hash([input.data,field])
	var label_math: RefCounted = Labels.new()
	var actual: Array = label_math.call("fit_all",input.data,field,PackedInt32Array(),native)
	check(var_to_bytes(actual) == var_to_bytes(expected),"native-assisted full labels preserve GDScript paths, alternate capital holes, sizes and ordering")
	check(hash([input.data,field]) == before,"native label fitting preserves shared input and label fields")
func small_border_districts(payload: Dictionary,owners: PackedInt32Array) -> Array:
	var pixels := PackedInt32Array(); pixels.resize(owners.size())
	for province in provinces:
		if province >= 0: pixels[province] += 1
	var candidates := {}; var choices: Array = []
	for pair in payload.territorial_pairs:
		if owners[pair.x] == owners[pair.y]: continue
		for ids in [[pair.x,pair.y],[pair.y,pair.x]]:
			var city: int = ids[0]; var other: int = ids[1]
			if source.is_zhou_city(city) or pixels[city] == 0 or candidates.has(city): continue
			candidates[city] = true
			choices.append({"city":city,"owner":owners[other],"pixels":pixels[city]})
	choices.sort_custom(func(a,b): return a.city < b.city if a.pixels == b.pixels else a.pixels < b.pixels)
	return choices
func verify_result(input: Dictionary,label: String,prepared_reference: Dictionary = {}) -> Dictionary:
	var before := published_signature(input.cache)
	var owners_before: PackedByteArray = input.ownership.to_byte_array()
	var nations_before := var_to_bytes(input.data.nations)
	var geometry_before := hash([input.mesh,input.provinces,input.region_of,input.weak])
	var reference: Dictionary = full_reference(input) if prepared_reference.is_empty() else prepared_reference
	var result: Dictionary = Display.calculate(input)
	check(result.has("cache") and result.has("labels") and result.has("names") and result.has("tile_updates"),label+": incremental computation returns a complete new publication")
	check(result.get("labels",PackedInt32Array()) == reference.labels,label+": picking raster equals a complete GDScript recomputation")
	check(var_to_bytes(result.get("lines",[])) == var_to_bytes(reference.lines),label+": complete smoothed political border geometry matches")
	check(var_to_bytes(result.get("index",{})) == var_to_bytes(reference.index),label+": border segment index follows the new geometry")
	check(var_to_bytes(result.get("names",[])) == var_to_bytes(reference.names),label+": country labels match the complete GDScript layout")
	if result.has("edge") and not result.edge.is_empty():
		check(result.edge.get("bytes",PackedByteArray()) == reference.edge.bytes,label+": political border distance bytes remain exact")
	check(published_signature(input.cache) == before,label+": original published cache is unchanged")
	check(input.ownership.to_byte_array() == owners_before,label+": requested ownership input remains unchanged")
	check(var_to_bytes(input.data.nations) == nations_before,label+": country metadata remains unchanged")
	check(hash([input.mesh,input.provinces,input.region_of,input.weak]) == geometry_before,label+": display calculation never alters province or raster geometry")
	if result.has("cache"):
		check(result.cache.ownership == input.ownership,label+": new cache belongs to the requested owners")
		check(result.cache.labels == result.labels,label+": cache and published picking data share one revision")
		verify_tiles(result,input.cache,label)
	print("POLITICAL_INCREMENTAL_CASE ",label," dirty_tiles=",result.get("dirty_tiles",[]).size()," uploads=",result.get("tile_updates",[]).size()," failures=",failures)
	return result
func verify_tiles(result: Dictionary,previous: Dictionary,label: String):
	var updates: Array = result.get("tile_updates",[])
	var dirty: PackedInt32Array = result.get("dirty_tiles",PackedInt32Array())
	var seen := {}
	for row in updates:
		var id: int = row.id
		check(id >= 0 and id < 128 and not seen.has(id),label+": upload tile IDs are valid and unique")
		seen[id] = true
		check(dirty.has(id),label+": uploaded tiles belong to this revision's dirty set")
		check(result.cache.tiles[id] == row.bytes,label+": retained tile cache contains the exact published RF bytes")
	var changed := 0
	for id in range(128):
		var pixels := PackedFloat32Array(); pixels.resize(128*128)
		for y in range(128):
			for x in range(128): pixels[y*128+x] = float(result.labels[((id/16)*128+y)*2048+(id%16)*128+x])
		var bytes := pixels.to_byte_array()
		check(result.cache.tiles[id] == bytes,label+": every cached tile contains the latest picking labels")
		if previous.tiles[id] != bytes:
			changed += 1
			check(seen.has(id),label+": every changed tile has an actual GPU upload")
		else:
			check(not seen.has(id),label+": an unchanged tile does not upload redundant RF data")
	check(changed == seen.size(),label+": actual uploads exactly cover all changed political tiles")
