class_name TerrainLandComponents
extends RefCounted
## Run-length components retain narrow straits lost by the province grid.
static var _cache := {}
static func build(image: Image) -> Dictionary:
	var source: Image = image.duplicate()
	if source.get_format()!=Image.FORMAT_RGBA8: source.convert(Image.FORMAT_RGBA8)
	var data := source.get_data()
	var key := hash([source.get_size(),data])
	if _cache.has(key): return _cache[key]
	var width := source.get_width()
	var rows: Array=[]
	var parent := PackedInt32Array()
	var lengths := PackedInt32Array()
	var previous: Array=[]
	for y in range(source.get_height()):
		var current: Array=[]
		var x := 0
		while x<width:
			if data[(y*width+x)*4+3]<=128: x+=1; continue
			var start := x
			while x<width and data[(y*width+x)*4+3]>128: x+=1
			var id := parent.size()
			parent.append(id)
			lengths.append(x-start)
			current.append(Vector3i(start,x,id))
		var index := 0
		for run in current:
			while index<previous.size() and previous[index].y<=run.x: index+=1
			var other := index
			while other<previous.size() and previous[other].x<run.y:
				parent[_root(parent,run.z)]=_root(parent,previous[other].z)
				other+=1
		rows.append(current)
		previous=current
	var areas := {}
	var largest := 0
	var mainland := -1
	for id in range(parent.size()):
		var root := _root(parent,id)
		parent[id]=root
		areas[root]=int(areas.get(root,0))+lengths[id]
		if areas[root]>largest: largest=areas[root]; mainland=root
	var result := {"size":source.get_size(),"rows":rows,"labels":parent,"mainland":mainland,"areas":areas}
	if _cache.size()>=2: _cache.erase(_cache.keys()[0])
	_cache[key]=result
	return result

static func at(components: Dictionary,point: Vector2) -> int:
	if point.x<0 or point.x>=1 or point.y<0 or point.y>=1: return -1
	var pixel := Vector2i(point*Vector2(components.size))
	for run in components.rows[pixel.y]:
		if pixel.x>=run.x and pixel.x<run.y: return components.labels[run.z]
	return -1

static func _root(parent: PackedInt32Array,index: int) -> int:
	var result := index
	while parent[result]!=result: result=parent[result]
	while parent[index]!=index:
		var next := parent[index]
		parent[index]=result
		index=next
	return result
