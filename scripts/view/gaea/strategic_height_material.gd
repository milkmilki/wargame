@tool
class_name StrategicHeightMaterial
extends GaeaMaterial
## Gaea 高度场单元材质。高度编码在 GaeaGrid 的 cell.y，本资源仅标识
## 该单元可由 StrategicTerrainRenderer 消费。


func _init() -> void:
	preview_color = Color(0.38, 0.48, 0.31, 1.0)


func _is_sampled() -> bool:
	return false


func _is_data() -> bool:
	return true
