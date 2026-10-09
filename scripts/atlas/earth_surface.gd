extends RefCounted
## Numeric input adapter: SRTM15+ v2.7 relief, Natural Earth v5.1.2 land/lakes.
## Data provenance and hashes: assets/atlas/earth_source.json. No runtime network.
const SOURCE := "res://assets/atlas/earth_source.json"

static func load_surface() -> Dictionary:
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not metadata is Dictionary or metadata.get("format")!="atlas-earth-surface-v1": return {}
	var w := int(metadata.width); var h := int(metadata.height)
	if w!=3600 or h!=1800: return {}
	var height_bytes := FileAccess.get_file_as_bytes("res://assets/atlas/"+metadata.relief_file)
	var water_bytes := FileAccess.get_file_as_bytes("res://assets/atlas/"+metadata.water_file)
	for item in [[height_bytes,metadata.relief_sha256],[water_bytes,metadata.water_sha256]]:
		var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(item[0])
		if context.finish().hex_encode()!=item[1]: return {}
	height_bytes = height_bytes.decompress_dynamic(w*h*2,FileAccess.COMPRESSION_GZIP)
	water_bytes = water_bytes.decompress_dynamic(w*h,FileAccess.COMPRESSION_GZIP)
	if height_bytes.size()!=w*h*2 or water_bytes.size()!=w*h: return {}
	return {"width":w,"height":h,"heights":height_bytes,"water":water_bytes,"metadata":metadata}

static func elevation_at(surface: Dictionary,longitude: float,latitude: float) -> float:
	var w: int = surface.width; var h: int = surface.height
	var x := fposmod((longitude+180.)/360.*w-.5,w); var y := clampf((90.-latitude)/180.*h-.5,0,h-1)
	var x0 := floori(x); var y0 := floori(y); var x1 := (x0+1)%w; var y1 := mini(y0+1,h-1)
	var values: PackedByteArray = surface.heights; var a := values.decode_s16((y0*w+x0)*2); var b := values.decode_s16((y0*w+x1)*2)
	var c := values.decode_s16((y1*w+x0)*2); var d := values.decode_s16((y1*w+x1)*2)
	return lerpf(lerpf(a,b,x-x0),lerpf(c,d,x-x0),y-y0)*surface.metadata.elevation_scale_m

static func water_at(surface: Dictionary,longitude: float,latitude: float) -> int:
	var x := floori(fposmod((longitude+180.)/360.*surface.width,surface.width))
	var y := clampi(floori((90.-latitude)/180.*surface.height),0,surface.height-1)
	return surface.water[y*surface.width+x]
