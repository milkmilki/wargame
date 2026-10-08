extends AStarGrid2D
var module: GDScript
var context: Dictionary
var positions: PackedVector2Array
var first: int
var last: int
var reuse: Dictionary
var grid: Vector2i
func _compute_cost(from: Vector2i,to: Vector2i) -> float:
	var i:=from.y*grid.x+from.x;var j:=to.y*grid.x+to.x
	var key:=mini(i,j)*positions.size()+maxi(i,j);var endpoint:=i in [first,last] or j in [first,last]
	if endpoint or not context.legal.has(key):
		var valid: bool=module._safe_segment(positions[i],positions[j],context.options)
		if not endpoint: context.legal[key]=valid
		if not valid: return INF
	elif not context.legal[key]: return INF
	var base: float=context.step_base.get(key,0.0)
	if endpoint or base==0:
		var delta:=positions[j]-positions[i];delta.x*=context.aspect;var length:=delta.length()
		var h0: float=context.heights[i];var h1: float=context.heights[j]
		if endpoint:
			var image: Image=context.options.image
			h0=TerrainMapGenerator.packed_altitude(image.get_pixelv(Vector2i(positions[i]*Vector2(image.get_size())).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE)))
			h1=TerrainMapGenerator.packed_altitude(image.get_pixelv(Vector2i(positions[j]*Vector2(image.get_size())).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE)))
		base=module.step_cost(h0,h1,length,length*context.km_per_height,false,true)
		if not endpoint: context.step_base[key]=base
	return base*(0.5 if reuse.has(key) else 1.0)*(1 if context.city_cells.has(j) else 2)
func _estimate_cost(from: Vector2i,to: Vector2i) -> float:
	var delta:=positions[from.y*grid.x+from.x]-positions[to.y*grid.x+to.x];delta.x*=context.aspect
	return delta.length()*0.5
