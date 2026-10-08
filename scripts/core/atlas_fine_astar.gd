extends AStarGrid2D
var alpha: PackedByteArray
var width:=1
var aspect:=1.0
var maximum_height:=1.0
func _compute_cost(from: Vector2i,to: Vector2i) -> float:
	var difference:=absf(float(alpha[(from.y*width+from.x)*4+3])-float(alpha[(to.y*width+to.x)*4+3]))/127.0
	if difference>maximum_height: return INF
	return (aspect if from.x!=to.x else 1.0)*(1.0+7.0*difference)
func _estimate_cost(from: Vector2i,to: Vector2i) -> float: return absi(from.x-to.x)*aspect+absi(from.y-to.y)
