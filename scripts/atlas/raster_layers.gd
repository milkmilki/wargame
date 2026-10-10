extends Node
## Immutable terrain pictures in world coordinates. Camera motion never paints
## paper, ocean depth, grain or terrain shading again. Ink remains vector sharp.
const WORLD := Vector2i(2048,1024)
const DETAIL := 4.
var layers: Array = []
var scheduler: Node
var sprites: Array = []
var current := -1
var cache_key := ""
var build_count := 0

func setup(source: Texture2D,material: ShaderMaterial,service: Node) -> void:
	scheduler=service; cache_key="paper:%d"%get_instance_id()
	for detail in [1.,DETAIL]:
		var view := SubViewport.new(); view.disable_3d=true
		view.size=Vector2i(Vector2(WORLD)*detail)
		view.render_target_update_mode=SubViewport.UPDATE_ONCE
		add_child(view)
		var picture := Sprite2D.new(); picture.centered=false; picture.texture=source
		picture.scale=Vector2.ONE*detail
		picture.material=material.duplicate()
		picture.material.set_shader_parameter("view_zoom",detail)
		picture.material.set_shader_parameter("glyph_scale",pow(maxf(1.,detail/1.35),-.22))
		view.add_child(picture); layers.append(view); build_count+=1
	scheduler.remember(cache_key,null,(WORLD.x*WORLD.y*4)*(1+int(DETAIL*DETAIL)),true)

func bind(picture: Sprite2D) -> void:
	sprites.append(picture)
	picture.material=null; picture.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	apply(picture,maxi(0,current))

func apply(picture: Sprite2D,index: int) -> void:
	picture.texture=layers[index].get_texture()
	picture.scale=Vector2.ONE/(1. if index==0 else DETAIL)

func set_zoom(value: float) -> void:
	var next := 0 if value<=1.35 else 1
	if current==next: return
	current=next
	for picture in sprites: apply(picture,current)

func _exit_tree() -> void:
	if is_instance_valid(scheduler): scheduler.forget(cache_key)
