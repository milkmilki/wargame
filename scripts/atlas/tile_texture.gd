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
