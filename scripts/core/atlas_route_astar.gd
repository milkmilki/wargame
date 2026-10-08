extends AStar2D
var costs: Dictionary={}
var node_count:=1
func _compute_cost(from: int,to: int) -> float: return costs[from*node_count+to]
func _estimate_cost(from: int,to: int) -> float: return get_point_position(from).distance_to(get_point_position(to))*0.5
