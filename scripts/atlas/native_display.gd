extends RefCounted
## Pure numeric display boundary; the GDScript routines remain the oracle.
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Wash = preload("res://scripts/atlas/wash.gd")
const Labels = preload("res://scripts/atlas/polity_labels.gd")

static func kernel() -> RefCounted:
	if OS.get_environment("WARGAME_DISPLAY_BACKEND")=="gdscript" or not ClassDB.class_exists("NativeAtlasDisplay"): return null
	var service = ClassDB.instantiate("NativeAtlasDisplay")
	return service if service!=null and service.call("api_version")==1 else null

static func paint_labels(input: Dictionary) -> Dictionary:
	var service := kernel()
	if service!=null: return service.call("paint_labels",input)
	var labels := PackedInt32Array(); labels.resize(input.provinces.size())
	for i in range(labels.size()): labels[i]=input.ownership[input.provinces[i]] if input.provinces[i]>=0 else -2
	Geometry.band_labels(labels,input.w,input.h,input.lines,input.weak)
	return {"labels":labels,"dirty_tiles":all_tiles(input.w,input.h,input.get("tile",128))}

static func edge_data(labels: PackedInt32Array,w: int,h: int) -> Dictionary:
	var service := kernel()
	var out: Dictionary = service.call("edge_field",labels,w,h) if service!=null else Wash.edge_data(labels,w,h)
	out.format=Image.FORMAT_RF; return out

static func label_field(regions: PackedInt32Array,ownership: PackedInt32Array,w: int,h: int) -> Dictionary:
	var service := kernel()
	return service.call("label_field",regions,ownership,w,h) if service!=null else Labels.field(regions,ownership,w,h)

static func all_tiles(w: int,h: int,tile: int) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for i in range(ceili(float(w)/tile)*ceili(float(h)/tile)): ids.append(i)
	return ids

static func region_tiles(provinces: PackedInt32Array,count: int,w: int,h: int,tile: int) -> Array:
	var service := kernel()
	if service!=null: return service.call("region_tiles",provinces,count,w,h,tile)
	var result: Array = []; var seen: Array = []
	for i in range(count): seen.append({})
	var nx := ceili(float(w)/tile)
	for y in range(h):
		for x in range(w):
			var region := provinces[y*w+x]
			if region>=0: seen[region][(y/tile)*nx+x/tile]=true
	for regions in seen:
		var ids: Array = regions.keys(); ids.sort(); result.append(PackedInt32Array(ids))
	return result

static func label_tiles(labels: PackedInt32Array,w: int,h: int,tile: int,ids: PackedInt32Array) -> Array:
	var service := kernel()
	if service!=null: return service.call("label_tiles",labels,w,h,tile,ids)
	var result: Array = []; var nx := ceili(float(w)/tile)
	for id in ids:
		var pixels := PackedFloat32Array(); pixels.resize(tile*tile)
		for y in range(tile):
			for x in range(tile):
				var px := (id%nx)*tile+x; var py := (id/nx)*tile+y
				pixels[y*tile+x]=labels[py*w+px] if px<w and py<h else -2.
		result.append({"id":id,"bytes":pixels.to_byte_array()})
	return result
