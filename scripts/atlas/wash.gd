extends RefCounted
## civ-atlas territory.ts edgeField at full working resolution. AGPL-3.0-only.
static func edge_field(labels: PackedInt32Array,w: int,h: int) -> ImageTexture:
	return texture(edge_data(labels,w,h))

static func texture(row: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(row.w,row.h,false,row.format,row.bytes))

static func edge_data(labels: PackedInt32Array,w: int,h: int) -> Dictionary:
	var gw0 := int(ceil(w/2.0)); var gh := int(ceil(h/2.0)); var pad := 34; var gw := gw0+pad*2
	var lab := PackedInt32Array(); lab.resize(gw*gh)
	var dist := PackedFloat32Array(); dist.resize(gw*gh)
	for y in range(gh):
		for x in range(gw): lab[y*gw+x] = labels[mini(h-1,y*2+1)*w+mini(w-1,posmod(x-pad,gw0)*2+1)]
	for y in range(gh):
		for x in range(gw):
			var k := y*gw+x; var l := lab[k]; var source := false
			if l != -2:
				for q in [k-1 if x>0 else k,k+1 if x<gw-1 else k,k-gw if y>0 else k,k+gw if y<gh-1 else k]:
					if lab[q] != l and lab[q] != -2: source = true; break
			dist[k] = 0.5 if source else 1e6
	for y in range(gh):
		for x in range(gw):
			var k := y*gw+x; var v := float(dist[k])
			if x>0: v = minf(v,dist[k-1]+1)
			if y>0:
				v = minf(v,dist[k-gw]+1)
				if x>0: v = minf(v,dist[k-gw-1]+sqrt(2.0))
				if x<gw-1: v = minf(v,dist[k-gw+1]+sqrt(2.0))
			dist[k] = v
	for y in range(gh-1,-1,-1):
		for x in range(gw-1,-1,-1):
			var k := y*gw+x; var v := float(dist[k])
			if x<gw-1: v = minf(v,dist[k+1]+1)
			if y<gh-1:
				v = minf(v,dist[k+gw]+1)
				if x<gw-1: v = minf(v,dist[k+gw+1]+sqrt(2.0))
				if x>0: v = minf(v,dist[k+gw-1]+sqrt(2.0))
			dist[k] = v
	return {"w":gw,"h":gh,"format":Image.FORMAT_RF,"bytes":dist.to_byte_array()}

static func color_texture(labels: PackedInt32Array,w: int,h: int,colors: Array) -> ImageTexture:
	return texture(color_data(labels,w,h,colors))

static func color_data(labels: PackedInt32Array,w: int,h: int,colors: Array) -> Dictionary:
	var bytes := PackedByteArray(); bytes.resize(w*h*4)
	for k in range(labels.size()):
		if labels[k]<0: continue
		var color: Color = colors[labels[k]]
		bytes[4*k] = color.r8; bytes[4*k+1] = color.g8; bytes[4*k+2] = color.b8; bytes[4*k+3] = 255
	return {"w":w,"h":h,"format":Image.FORMAT_RGBA8,"bytes":bytes}
