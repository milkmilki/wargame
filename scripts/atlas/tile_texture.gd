extends RefCounted
## Copy the resolved tile on the rendering thread. Cache only pixels, not MSAA
## attachments, temporary viewports or planning meshes; no CPU readback on RD.
class OwnedTexture extends Texture2DRD:
	var owned := RID()
	func _notification(what: int) -> void:
		if what!=NOTIFICATION_PREDELETE or not owned.is_valid(): return
		var release := owned
		RenderingServer.call_on_render_thread(func():
			var device := RenderingServer.get_rendering_device()
			if device!=null: device.free_rid(release))

class Atlas extends RefCounted:
	var size := Vector2i.ZERO
	var texture: Texture2D
	var image: Image # Compatibility renderer assembles pixels before one upload.
	func finish() -> Texture2D:
		if image!=null:
			texture=ImageTexture.create_from_image(image); image=null
		return texture

## Only the final single-sample image spans the world. One resolved, padded
## viewport at a time is copied into it without a full-world CPU readback.
static func copy_into(source: Texture2D,region: Rect2i,atlas: Atlas,position: Vector2i,publish: Callable) -> void:
	if RenderingServer.get_rendering_device()==null:
		if DisplayServer.get_name()=="headless":
			if atlas.texture==null:
				var placeholder := PlaceholderTexture2D.new(); placeholder.size=atlas.size; atlas.texture=placeholder
			publish.call(true); return
		var image := source.get_image()
		if image==null or image.is_empty(): publish.call(false); return
		if atlas.image==null: atlas.image=Image.create(atlas.size.x,atlas.size.y,false,image.get_format())
		atlas.image.blit_rect(image,region,position); publish.call(true); return
	var source_rid := source.get_rid()
	RenderingServer.call_on_render_thread(func():
		var device := RenderingServer.get_rendering_device()
		var original := RenderingServer.texture_get_rd_texture(source_rid)
		if not original.is_valid() or not device.texture_is_valid(original): publish.call_deferred(false); return
		if atlas.texture==null:
			var format := device.texture_get_format(original)
			var target := RDTextureFormat.new(); target.width=atlas.size.x; target.height=atlas.size.y; target.format=format.format
			target.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			var rid := device.texture_create(target,RDTextureView.new())
			if not rid.is_valid(): publish.call_deferred(false); return
			var texture := OwnedTexture.new(); texture.owned=rid; texture.texture_rd_rid=rid; atlas.texture=texture
		var destination: RID=atlas.texture.texture_rd_rid
		var error := device.texture_copy(original,destination,Vector3(region.position.x,region.position.y,0),Vector3(position.x,position.y,0),Vector3(region.size.x,region.size.y,1),0,0,0,0)
		publish.call_deferred(error==OK))

static func copy(source: Texture2D,region: Rect2i,publish: Callable) -> void:
	if RenderingServer.get_rendering_device()==null:
		if DisplayServer.get_name()=="headless": publish.call(source,false); return
		var image := source.get_image()
		# The headless dummy renderer has no pixels; functional tests retain its
		# viewport handle. Compatibility builds copy actual RGBA pixels here.
		if image==null or image.is_empty(): publish.call(source,false); return
		publish.call(ImageTexture.create_from_image(image.get_region(region)),true); return
	var source_rid := source.get_rid()
	RenderingServer.call_on_render_thread(func():
		var device := RenderingServer.get_rendering_device()
		var original := RenderingServer.texture_get_rd_texture(source_rid)
		var format := device.texture_get_format(original)
		var target := RDTextureFormat.new(); target.width = region.size.x; target.height = region.size.y; target.format = format.format
		target.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		var rid := device.texture_create(target,RDTextureView.new())
		var error := device.texture_copy(original,rid,Vector3(region.position.x,region.position.y,0),Vector3.ZERO,Vector3(region.size.x,region.size.y,1),0,0,0,0)
		if error!=OK:
			device.free_rid(rid); publish.call_deferred(source,false); return
		var texture := OwnedTexture.new(); texture.owned = rid; texture.texture_rd_rid = rid
		publish.call_deferred(texture,true))
