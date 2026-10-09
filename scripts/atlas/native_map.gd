extends RefCounted
## Independent preview snapshots. No dependency on GameState or game templates.
const FORMAT := "atlas-native-map"
const VERSION := 1
const UPSTREAM := "103afd3"

static func numeric_array(value: Variant) -> bool:
	return typeof(value) in [TYPE_ARRAY,TYPE_PACKED_BYTE_ARRAY,TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY]

static func validate(data: Dictionary) -> String:
	if data.get("format") != FORMAT or data.get("version") != VERSION:
		return "Unsupported atlas snapshot."
	for field in ["mesh", "environment", "regions"]:
		if not data.get(field) is Dictionary: return "Missing " + field
	var mesh: Dictionary = data.mesh
	var env: Dictionary = data.environment
	var regions: Dictionary = data.regions
	for field in ["x", "y", "xyz", "triangles", "adj_start", "adj"]:
		if not numeric_array(mesh.get(field)): return "Missing mesh " + field
	var n: int = mesh.x.size()
	if n == 0 or mesh.y.size() != n or mesh.xyz.size() != n * 3:
		return "Invalid mesh dimensions."
	if mesh.adj_start.size() != n + 1 or int(mesh.adj_start[0]) != 0 or int(mesh.adj_start[-1]) != mesh.adj.size():
		return "Invalid adjacency offsets."
	for i in range(n):
		if int(mesh.adj_start[i]) > int(mesh.adj_start[i+1]): return "Unsorted adjacency offsets."
	for field in ["adj", "triangles"]:
		for value in mesh[field]:
			if int(value) != value or value < 0 or value >= n: return "Invalid mesh index."
	for field in ["elevation", "water", "suitability"]:
		if not numeric_array(env.get(field)) or env[field].size() != n: return "Invalid " + field
		for value in env[field]:
			if not is_finite(float(value)): return "Non-finite " + field
	for field in ["of", "seat", "area", "capacity"]:
		if not numeric_array(regions.get(field)): return "Missing region " + field
	var count: int = regions.seat.size()
	if regions.of.size() != n or regions.area.size() != count or regions.capacity.size() != count:
		return "Invalid region dimensions."
	for value in regions.of:
		if int(value) != value or value < -1 or value >= count: return "Invalid province index."
	for r in range(count):
		var cell: int = regions.seat[r]
		if cell < 0 or cell >= n or int(regions.of[cell]) != r: return "Invalid province seat."
	if not data.get("cities") is Array or not data.get("roads") is Array:
		return "Missing cities or roads."
	for city in data.cities:
		if not city is Dictionary: return "Invalid city."
		var cell := int(city.get("cell", -1))
		if cell < 0 or cell >= n or int(env.water[cell]) != 0: return "Invalid city cell."
		if int(city.get("region", -1)) != int(regions.of[cell]): return "Invalid city province."
	if not numeric_array(data.get("ownership")) or data.ownership.size() != count or not data.get("nations") is Array:
		return "Invalid ownership."
	for owner in data.ownership:
		if int(owner) != owner or owner < -1 or owner >= data.nations.size(): return "Invalid owner."
	for road in data.roads:
		if not road is Dictionary or not numeric_array(road.get("cells")): return "Invalid road."
		for cell in road.cells:
			if int(cell) != cell or cell < 0 or cell >= n or int(env.water[cell]) != 0: return "Invalid road cell."
	return ""

static func encode(data: Dictionary) -> String:
	return JSON.stringify(data)

static func decode(contents: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(contents) != OK or not json.data is Dictionary: return {}
	var data: Dictionary = json.data
	if not validate(data).is_empty(): return {}
	# JSON numbers are doubles. Restore categorical/index fields as integers.
	data.version = int(data.version)
	data.seed = int(data.seed)
	for field in ["triangles", "adj_start", "adj"]:
		data.mesh[field] = Array(PackedInt32Array(data.mesh[field]))
	data.environment.water = Array(PackedInt32Array(data.environment.water))
	for field in ["of", "seat"]:
		data.regions[field] = Array(PackedInt32Array(data.regions[field]))
	data.ownership = Array(PackedInt32Array(data.ownership))
	for city in data.cities:
		city.cell = int(city.cell)
		city.region = int(city.region)
	for road in data.roads:
		road.cells = Array(PackedInt32Array(road.cells))
	return data
