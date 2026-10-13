extends SceneTree
## Independent C++ display API; the GDScript render math remains the numerical
## oracle. Neither implementation may mutate the shared simulation inputs.
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Wash = preload("res://scripts/atlas/wash.gd")
const Labels = preload("res://scripts/atlas/polity_labels.gd")
var kernel: RefCounted
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks += 1
	if not ok: failures += 1; printerr("NATIVE_DISPLAY_FAIL ",message)
func finish():
	print("ATLAS_NATIVE_DISPLAY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func run():
	if not ClassDB.class_exists("NativeAtlasDisplay"):
		check(false,"the independent native display kernel is actually loaded")
		finish(); return
	kernel = ClassDB.instantiate("NativeAtlasDisplay")
	for method in ["api_version","paint_labels","edge_field","label_field","label_rays","fit_label","label_tiles","region_tiles"]:
		check(kernel.has_method(method),"the display kernel exposes %s" % method)
	if failures: finish(); return
	check(int(kernel.call("api_version")) == 1,"the display API has its own version")
	if ClassDB.class_exists("NativeGraphSnapshot"):
		var simulation_kernel: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
		check(int(simulation_kernel.call("api_version")) == 7,"adding display math preserves the simulation kernel API")
	test_paint()
	test_sparse_ownership()
	test_unowned_and_noop_paint()
	test_edge_fields()
	test_label_fields_and_fits()
	test_vertical_label_fit()
	test_tiles()
	test_invalid_inputs()
	finish()
func line(points: Array,left: int = 0,right: int = 1,closed: bool = false,end0: bool = false,end1: bool = false) -> Dictionary:
	return {"pts":PackedFloat32Array(points),"left":left,"right":right,"closed":closed,"end0":end0,"end1":end1}
func paint_fixture(w: int,h: int,lines: Array,weak_on: bool,tile: int = 5) -> Dictionary:
	var provinces := PackedInt32Array(); var weak := PackedByteArray()
	provinces.resize(w*h); weak.resize(w*h)
	for y in range(h):
		for x in range(w):
			var ocean := (x+y*2)%17 == 0 or y == 0
			provinces[y*w+x] = -2 if ocean else (0 if x < w/2 else 1)
			weak[y*w+x] = 1 if weak_on and (x+y)%3 != 0 else 0
	return {"provinces":provinces,"ownership":PackedInt32Array([0,1]),"lines":lines,
		"weak":weak,"w":w,"h":h,"tile":tile,"previous":PackedInt32Array(),"dirty_tiles":PackedInt32Array()}
func paint_reference(input: Dictionary) -> PackedInt32Array:
	var labels := PackedInt32Array(); labels.resize(input.provinces.size())
	for i in range(labels.size()):
		labels[i] = input.ownership[input.provinces[i]] if input.provinces[i] >= 0 else -2
	Geometry.band_labels(labels,input.w,input.h,input.lines,input.weak)
	return labels
func tile_of(x: int,y: int,w: int,tile: int) -> int:
	return (y/tile)*ceili(float(w)/tile) + x/tile
func check_tile_ids(ids: PackedInt32Array,w: int,h: int,tile: int):
	var seen := {}; var total := ceili(float(w)/tile)*ceili(float(h)/tile)
	for id in ids:
		check(id >= 0 and id < total and not seen.has(id),"publication tile ids are valid and unique")
		seen[id] = true
func test_paint():
	for size in [Vector2i(8,8),Vector2i(16,12),Vector2i(17,13)]:
		var w: int = size.x; var h: int = size.y
		var variants: Array = [[],[line([w*.5,-2.,w*.5,h+2.])],
			[line([1.,1.,w*.4,h*.5,w-1.,h-1.],0,1,false,true,false)],
			[line([1.,1.,w*.4,h*.5,w-1.,h-1.],0,1,false,false,true)],
			[line([-2.,2.,2.,h*.5,-2.,h-2.],0,1,false,true,true)],
			[line([w-2.,1.,w+2.,h*.5,w-2.,h-1.])],
			[line([2.,2.,w-2.,2.,w-2.,h-2.,2.,h-2.,2.,2.],0,1,true)],
			[line([2.,2.,2.,2.,w-2.,h-2.],0,1,false,true,true)],
			[line([1.,1.,w-1.,h-1.]),line([1.,h-1.,w-1.,1.],1,0)],
			[line([1.,1.])]]
		for lines in variants:
			for weak_on in [false,true]:
				var input := paint_fixture(w,h,lines,weak_on)
				var before := var_to_bytes(input)
				var expected := paint_reference(input)
				var actual: Dictionary = kernel.call("paint_labels",input)
				check(actual.has("labels") and actual.has("dirty_tiles"),"initial political raster exposes labels and publication tiles")
				if not actual.has("labels"): continue
				check(actual.labels == expected,"native border raster matches GDScript for open, closed, wrapped, degenerate and weak-coast paths")
				check(var_to_bytes(input) == before,"full political painting does not modify its input arrays or paths")
				if actual.has("dirty_tiles"):
					check_tile_ids(actual.dirty_tiles,w,h,input.tile)
					check(actual.dirty_tiles.size() == ceili(float(w)/input.tile)*ceili(float(h)/input.tile),"initial publication includes every world tile")
				# Dirty tiles must recompute their base owner and all influencing
				# segments, rather than smoothing an already smoothed old raster.
				var previous := expected.duplicate()
				var count := ceili(float(w)/input.tile)*ceili(float(h)/input.tile)
				var dirty := PackedInt32Array([0,count-1])
				for y in range(h):
					for x in range(w):
						if dirty.has(tile_of(x,y,w,input.tile)): previous[y*w+x] = 999
				input.previous = previous; input.dirty_tiles = dirty
				before = var_to_bytes(input)
				actual = kernel.call("paint_labels",input)
				check(actual.get("labels",PackedInt32Array()) == expected,"dirty tiles rebuild independently to the same raster as a complete new paint")
				check(var_to_bytes(input) == before,"incremental painting retains prior published buffers")
				if actual.has("dirty_tiles"): check_tile_ids(actual.dirty_tiles,w,h,input.tile)
func test_sparse_ownership():
	var w := 17; var h := 13; var tile := 5
	var input := paint_fixture(w,h,[],false,tile)
	var count := ceili(float(w)/tile)*ceili(float(h)/tile)
	input.ownership = PackedInt32Array()
	for id in range(count): input.ownership.append(id%2)
	for y in range(h):
		for x in range(w): input.provinces[y*w+x] = tile_of(x,y,w,tile)
	var initial: Dictionary = kernel.call("paint_labels",input)
	if not initial.has("labels"): check(false,"sparse ownership fixture paints"); return
	input.previous = initial.labels; input.ownership[0] = 2; input.ownership[count-1] = 3
	input.dirty_tiles = PackedInt32Array([0,count-1])
	var before := var_to_bytes(input)
	var result: Dictionary = kernel.call("paint_labels",input)
	check(result.get("labels",PackedInt32Array()) == paint_reference(input),"changing only selected provinces equals a new full ownership raster")
	if result.has("labels"):
		for y in range(h):
			for x in range(w):
				if not input.dirty_tiles.has(tile_of(x,y,w,tile)):
					check(result.labels[y*w+x] == initial.labels[y*w+x],"an untouched tile preserves its published raster bytes")
	check(var_to_bytes(input) == before,"sparse ownership repaint does not mutate old ownership or publication state")
func test_unowned_and_noop_paint():
	var input := paint_fixture(16,12,[line([8.,-2.,8.,14.],-1,0,false,true,true)],true)
	input.ownership = PackedInt32Array([-1,0])
	var before := var_to_bytes(input)
	var initial: Dictionary = kernel.call("paint_labels",input)
	check(initial.get("labels",PackedInt32Array()) == paint_reference(input),"an unowned land side remains distinct from ocean while border bands match the reference")
	check(var_to_bytes(input) == before,"unowned territory painting is read-only")
	if not initial.has("labels"): return
	input.previous = initial.labels
	input.dirty_tiles = PackedInt32Array()
	before = var_to_bytes(input)
	var unchanged: Dictionary = kernel.call("paint_labels",input)
	check(unchanged.get("labels",PackedInt32Array()) == initial.labels,"a revision with no dirty tiles retains the published labels")
	check(unchanged.has("dirty_tiles") and unchanged.dirty_tiles.is_empty(),"unchanged tile publication does not request a full upload")
	check(var_to_bytes(input) == before,"a no-op paint does not rewrite existing buffers")
func raster(w: int,h: int,variant: int) -> PackedInt32Array:
	var out := PackedInt32Array(); out.resize(w*h)
	for y in range(h):
		for x in range(w):
			var owner := 0
			match variant:
				0: owner = 0
				1: owner = 0 if x < w/2 else 1
				2: owner = 0 if x <= 2 or x >= w-2 else (1 if x >= w/2-1 and x <= w/2+1 and y > 1 and y < h-2 else -2)
				3: owner = -2
				4: owner = -2 if (x+y*3)%7 == 0 else ((x*3+y*7)%3)
			out[y*w+x] = owner
	return out
func test_edge_fields():
	for size in [Vector2i(8,8),Vector2i(16,12),Vector2i(17,13)]:
		for variant in range(5):
			var labels := raster(size.x,size.y,variant); var before := labels.to_byte_array()
			var expected := Wash.edge_data(labels,size.x,size.y)
			var actual: Dictionary = kernel.call("edge_field",labels,size.x,size.y)
			check(actual.get("w",0) == expected.w and actual.get("h",0) == expected.h,"native edge field preserves wrap padding and odd image dimensions")
			check(actual.get("bytes",PackedByteArray()) == expected.bytes,"native political chamfer distances match the reference RF bytes exactly")
			check(labels.to_byte_array() == before,"edge field construction is read-only")
func test_label_fields_and_fits():
	var owners := PackedInt32Array([0,1,2])
	for size in [Vector2i(8,8),Vector2i(16,12),Vector2i(32,24)]:
		for variant in range(5):
			var regions := raster(size.x,size.y,variant); var before := var_to_bytes([regions,owners])
			var expected := Labels.field(regions,owners,size.x,size.y)
			var actual: Dictionary = kernel.call("label_field",regions,owners,size.x,size.y)
			check(actual.get("gw",0) == size.x and actual.get("gh",0) == size.y,"native label field preserves its dimensions")
			check(actual.get("owner",PackedInt32Array()) == expected.owner,"native label owners match ocean and island ownership")
			check(actual.get("dist",PackedFloat32Array()).to_byte_array() == expected.dist.to_byte_array(),"native label distances match the reference Float32 bytes exactly")
			check(var_to_bytes([regions,owners]) == before,"label field construction preserves input ownership and regions")
			if not actual.has("owner") or not actual.has("dist"): continue
			check(actual.has("best") and actual.has("boxes"),"native label metadata includes best anchors and territory bounds")
			for p in range(3):
				var best := -1; var depth := 0.; var bounds := [size.x,size.y,-1,-1]
				for i in range(expected.owner.size()):
					if expected.owner[i] != p: continue
					if expected.dist[i] > depth: depth = expected.dist[i]; best = i
					bounds[0] = mini(bounds[0],i%size.x); bounds[1] = mini(bounds[1],i/size.x)
					bounds[2] = maxi(bounds[2],i%size.x); bounds[3] = maxi(bounds[3],i/size.x)
				if best < 0: continue
				if actual.has("best") and actual.has("boxes"):
					check(actual.best[p] == best,"maximum depth chooses the same deterministic first anchor")
					check(Array(actual.boxes[p]) == bounds,"label territory bounds cover exactly the owned cells")
				for hole in [[],[(best%size.x+.5)*4.,(best/size.x+.5)*4.,3.]]:
					for length in [12.,48.]:
						var field_before := var_to_bytes(actual); var hole_before := var_to_bytes(hole)
						var rays_expected := Labels.cast_rays(expected,p,best,length,hole)
						var rays_actual: Dictionary = kernel.call("label_rays",actual,p,best,length,hole)
						for key in ["px","py","depth","max_steps"]:
							check(rays_actual.has(key) and absf(float(rays_actual.get(key,-999.))-float(rays_expected[key])) < 1e-9,"native label ray scalar %s matches the reference" % key)
						check(rays_actual.get("prof",PackedFloat32Array()).to_byte_array() == rays_expected.prof.to_byte_array(),"native 72-ray profiles match reference Float32 bytes exactly")
						check(rays_actual.get("len",PackedInt32Array()) == rays_expected.len,"native ray clipping lengths match the reference")
						check(var_to_bytes(actual) == field_before and var_to_bytes(hole) == hole_before,"ray casting leaves field and capital exclusion unchanged")
						if not rays_actual.has("prof"): continue
						for text_length in [1,2,6]:
							var sizes: Array = [12.,8.,5.,2.]
							var fit_expected := Labels.fit_both(rays_expected,sizes,"国".repeat(text_length))
							var rays_before := var_to_bytes(rays_actual)
							var fit_actual: Dictionary = kernel.call("fit_label",rays_actual,sizes,text_length)
							check(fit_actual.is_empty() == fit_expected.is_empty(),"native short and long labels share the reference fit eligibility")
							if not fit_actual.is_empty() and not fit_expected.is_empty():
								check(fit_actual.size() == fit_expected.size(),"native fit returns the same fitting fields")
								for key in fit_expected:
									check(fit_actual.has(key) and fit_actual.get(key) == fit_expected[key],"native label fit chooses exactly the same %s" % key)
							check(var_to_bytes(rays_actual) == rays_before,"label fitting leaves reusable ray data untouched")
func test_tiles():
	for size in [Vector2i(8,8),Vector2i(16,12),Vector2i(17,13)]:
		for tile in [3,5,8]:
			var labels := raster(size.x,size.y,4); var before := labels.to_byte_array()
			var count := ceili(float(size.x)/tile)*ceili(float(size.y)/tile)
			var ids := PackedInt32Array()
			for id in range(count): ids.append(id)
			var tiles: Array = kernel.call("label_tiles",labels,size.x,size.y,tile,ids)
			check(tiles.size() == count,"tile upload materializes all requested world tiles")
			var seen := {}
			for row in tiles:
				var id := int(row.id); check(ids.has(id) and not seen.has(id),"tile upload returns each requested id once"); seen[id] = true
				var origin := Vector2i((id%ceili(float(size.x)/tile))*tile,(id/ceili(float(size.x)/tile))*tile)
				var expected := PackedFloat32Array(); expected.resize(tile*tile); expected.fill(-2.)
				for y in range(tile):
					for x in range(tile):
						if origin.x+x < size.x and origin.y+y < size.y: expected[y*tile+x] = float(labels[(origin.y+y)*size.x+origin.x+x])
				check(row.bytes == expected.to_byte_array(),"RF upload tiles preserve labels and pad partial edges with ocean")
			check(labels.to_byte_array() == before,"tile upload conversion does not modify source labels")
			var inverse: Array = kernel.call("region_tiles",labels,3,size.x,size.y,tile)
			check(inverse.size() == 3,"reverse region index retains every region slot")
			for region in range(mini(3,inverse.size())):
				var wanted: Array[int] = []
				for id in ids:
					var contains := false
					for y in range(size.y):
						for x in range(size.x):
							if tile_of(x,y,size.x,tile) == id and labels[y*size.x+x] == region: contains = true
					if contains: wanted.append(id)
				check(inverse[region] == PackedInt32Array(wanted),"a region indexes only tiles containing its immutable province pixels")
			check(labels.to_byte_array() == before,"reverse tile indexing preserves immutable province pixels")
func test_vertical_label_fit():
	var w := 16; var h := 32
	var regions := PackedInt32Array(); regions.resize(w*h); regions.fill(-2)
	for y in range(1,h-1):
		for x in range(7,10): regions[y*w+x] = 0
	var owners := PackedInt32Array([0])
	var reference := Labels.field(regions,owners,w,h)
	var cell := 16*w+8
	var expected_rays := Labels.cast_rays(reference,0,cell,128.)
	var sizes: Array = [12.,8.,5.,2.]
	var expected := Labels.fit_both(expected_rays,sizes,"国".repeat(6))
	check(not expected.is_empty() and expected.vertical,"the narrow tall-island fixture actually exercises a vertical label")
	var field: Dictionary = kernel.call("label_field",regions,owners,w,h)
	var rays: Dictionary = kernel.call("label_rays",field,0,cell,128.,[])
	var fit: Dictionary = kernel.call("fit_label",rays,sizes,6)
	check(not fit.is_empty() and fit.get("vertical",false),"native label fitting preserves the vertical orientation on a narrow territory")
	for key in expected:
		check(fit.has(key) and fit.get(key) == expected[key],"the vertical native label matches reference fitting %s" % key)
func rejected(value: Variant) -> bool:
	return (value is Dictionary and (value.is_empty() or value.has("error"))) or (value is Array and value.is_empty())
func test_invalid_inputs():
	var small := PackedInt32Array([0,1,0])
	check(rejected(kernel.call("edge_field",small,0,1)),"zero-width distance fields are rejected safely")
	check(rejected(kernel.call("edge_field",small,8,8)),"distance fields reject truncated rasters")
	check(rejected(kernel.call("label_field",small,PackedInt32Array([0,1]),8,8)),"label fields reject truncated region buffers")
	check(rejected(kernel.call("label_tiles",small,8,8,4,PackedInt32Array([0]))),"tile upload rejects truncated label buffers")
	check(rejected(kernel.call("region_tiles",small,2,8,8,4)),"region indexing rejects truncated province buffers")
	var input := paint_fixture(8,8,[],false); input.w = -1
	check(rejected(kernel.call("paint_labels",input)),"negative political raster dimensions are rejected safely")
	input = paint_fixture(8,8,[],false); input.tile = 0
	check(rejected(kernel.call("paint_labels",input)),"zero tile width cannot divide or allocate publication buffers")
	check(rejected(kernel.call("label_tiles",small,1,3,0,PackedInt32Array([0]))),"tile conversion rejects a zero-size tile safely")
	check(rejected(kernel.call("region_tiles",small,2,1,3,0)),"reverse indexing rejects a zero-size tile safely")
