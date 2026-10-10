extends RefCounted
## Native raster helpers from civ-atlas render/common.ts. AGPL-3.0-only.
const PAINT = ["a9c1c0","9fbcc0","eef0ea","ebe6d8","cfc9ad","9fae8a","d9cfae","e6d3a4","d8d09a","b3bd8b","9fb488","ecd5a0","dccd92","bcc38a","9db482","b2bd98"]
const Maths = preload("res://scripts/atlas/math.gd")

static func habitat_texture(data: Dictionary,raster: Dictionary) -> ImageTexture:
	return upload(habitat_data(data,raster))

static func habitat_data(data: Dictionary,raster: Dictionary) -> Dictionary:
	var w: int = raster.w; var h: int = raster.h; var n := w*h
	var num := PackedFloat32Array(); num.resize(n); var den := num.duplicate()
	for k in range(n):
		var cell: int = raster.cell[k]
		if data.regions.of[cell]>=0: num[k] = data.environment.suitability[cell]; den[k] = 1
	for array in [num,den]: blur(array,w,h,3); blur(array,w,h,3)
	for k in range(n): num[k] = num[k]/den[k] if den[k]>.02 else 0
	var stops: Array = [[246,222,170],[232,170,105],[206,96,52],[150,42,24]]; var lut := PackedByteArray(); lut.resize(256*4)
	for i in range(256):
		var t := i/255.0; var f := t*3; var at := mini(2,floori(f)); var u := f-at
		for c in range(3): lut[i*4+c] = roundi(stops[at][c]+(stops[at+1][c]-stops[at][c])*u)
		lut[i*4+3] = roundi(255*(.12+.56*pow(t,.85)))
	var bytes := PackedByteArray(); bytes.resize(n*4)
	for k in range(n):
		if raster.water[k]!=0: continue
		var s := float(num[k])
		if s<=.05: continue
		var li := mini(255,roundi(s/28*255)); var fade := 1.0 if s>=1 else (s-.05)/.95
		for c in range(3): bytes[k*4+c] = lut[li*4+c]
		bytes[k*4+3] = roundi(lut[li*4+3]*fade)
	return {"w":w,"h":h,"format":Image.FORMAT_RGBA8,"bytes":bytes}

static func ice_field(raster: Dictionary) -> Dictionary:
	var w: int = raster.w; var h: int = raster.h; var gw := ceili(w/8.0); var gh := ceili(h/8.0)
	var mask := PackedByteArray(); mask.resize(w*h); var near := mask.duplicate()
	var grid := PackedFloat32Array(); grid.resize(gw*gh)
	for y in range(h):
		for x in range(w):
			var k := y*w+x
			if raster.biome[k]==2: mask[k] = 1; grid[(y/8)*gw+x/8] += 1
	blur(grid,gw,gh,2)
	for y in range(h):
		var fy := clampf((y+.5)/8-.5,0,gh-1); var gy := int(floor(fy)); var ty := fy-gy
		for x in range(w):
			if grid[(y/8)*gw+x/8]<1e-3: continue
			var fx := (x+.5)/8-.5; var gx := int(floor(fx)); var tx := Maths.f32(fx-gx)
			var a := posmod(gx,gw); var b := posmod(gx+1,gw); var row0 := gy*gw; var row1 := mini(gh-1,gy+1)*gw
			var v := ((grid[row0+a]*(1-tx)+grid[row0+b]*tx)*(1-ty)+(grid[row1+a]*(1-tx)+grid[row1+b]*tx)*ty)/64
			near[y*w+x] = 1+int(floor(minf(1,v)*254+.5))
	return {"mask":mask,"near":near}

static func glyph_skirts(data: Dictionary,glyphs: Array,w: int,h: int) -> PackedByteArray:
	var out := PackedByteArray(); out.resize(w*h)
	for g in glyphs:
		if int(g.kind) not in [0,1] or g.z>1 or data.environment.temperature[g.cell]>-2: continue
		var co := cos(float(g.a)); var hw: float = g.s*(1+g.c*(.18*co*co-.14*(1-co*co))) if g.kind==0 else g.s
		var depth: float = g.s*(.75 if g.kind==0 else .55)
		for shift in [-w,0,w]:
			var gx: float = g.x+shift
			for y in range(maxi(0,floori(g.y-g.s*.25)),mini(h-1,ceili(g.y+depth))+1):
				var t: float = (y+.5-g.y)/depth; var wy := 1.0 if t<=0 else 1-Maths.smoothstep(0,1,t)
				for x in range(maxi(0,floori(gx-hw)),mini(w-1,ceili(gx+hw))+1):
					var u := absf(x+.5-gx)/hw
					if u<1: out[y*w+x] = maxi(out[y*w+x],int(floor(255*wy*Maths.smoothstep(1,.55,u)+.5)))
	return out

static func edt_pass(f: PackedFloat64Array,g: PackedFloat64Array,v: PackedInt32Array,z: PackedFloat64Array,length: int) -> void:
	var k := 0; v[0] = 0; z[0] = -1e20; z[1] = 1e20
	for q in range(1,length):
		var s := (f[q]+q*q-f[v[k]]-v[k]*v[k])/(2.0*q-2.0*v[k])
		while s <= z[k]:
			k -= 1; s = (f[q]+q*q-f[v[k]]-v[k]*v[k])/(2.0*q-2.0*v[k])
		k += 1; v[k] = q; z[k] = s; z[k+1] = 1e20
	k = 0
	for q in range(length):
		while z[k+1] < q: k += 1
		g[q] = (q-v[k])*(q-v[k])+f[v[k]]

static func distance_to(mask: PackedByteArray,w: int,h: int) -> PackedFloat32Array:
	var d := PackedFloat64Array(); d.resize(w*h)
	for i in range(d.size()): d[i] = 0.0 if mask[i] else 1e20
	var n := maxi(2*w,h)
	var f := PackedFloat64Array(); f.resize(n); var g := f.duplicate()
	var v := PackedInt32Array(); v.resize(n); var z := PackedFloat64Array(); z.resize(n+1)
	for x in range(w):
		for y in range(h): f[y] = d[y*w+x]
		edt_pass(f,g,v,z,h)
		for y in range(h): d[y*w+x] = g[y]
	var half := w >> 1
	for y in range(h):
		for q in range(2*w): f[q] = d[y*w+posmod(q-half,w)]
		edt_pass(f,g,v,z,2*w)
		for x in range(w): d[y*w+x] = g[x+half]
	var out := PackedFloat32Array(); out.resize(w*h)
	for i in range(out.size()): out[i] = sqrt(d[i])
	return out

static func blur(src: PackedFloat32Array,w: int,h: int,radius: int,stretch: PackedFloat32Array = PackedFloat32Array()) -> void:
	var tmp := PackedFloat32Array(); tmp.resize(w*h)
	for y in range(h):
		var rx := mini((w-1)>>1,radius if stretch.is_empty() else int(floor(radius*stretch[y]+.5)))
		var inv := 1.0/(2*rx+1)
		var acc := 0.0; var row := y*w
		for x in range(-rx,rx+1): acc += src[row+posmod(x,w)]
		for x in range(w):
			tmp[row+x] = acc*inv
			acc += src[row+posmod(x+rx+1,w)]-src[row+posmod(x-rx,w)]
	var inv := 1.0/(2*radius+1)
	for x in range(w):
		var acc := 0.0
		for y in range(-radius,radius+1): acc += tmp[clampi(y,0,h-1)*w+x]
		for y in range(h):
			src[y*w+x] = acc*inv
			acc += tmp[mini(h-1,y+radius+1)*w+x]-tmp[maxi(0,y-radius)*w+x]

static func textures(raster: Dictionary,data: Dictionary = {},glyphs: Array = []) -> Dictionary:
	return upload_all(texture_data(raster,data,glyphs))

static func texture_data(raster: Dictionary,data: Dictionary = {},glyphs: Array = [],prepared_ice: Dictionary = {}) -> Dictionary:
	var w: int = raster.w; var h: int = raster.h; var n := w*h
	var land := PackedByteArray(); land.resize(n); var sea := land.duplicate()
	var rgb: Array = []
	for _i in range(3):
		var channel := PackedFloat32Array(); channel.resize(n); rgb.append(channel)
	var palette: Array = []; for value in PAINT: palette.append(Color.html(value))
	for k in range(n):
		land[k] = 0 if raster.water[k] == 1 else 1; sea[k] = 1-land[k]
		var color: Color = palette[raster.biome[k]]
		rgb[0][k] = color.r*255.0; rgb[1][k] = color.g*255.0; rgb[2][k] = color.b*255.0
	for channel in rgb: blur(channel,w,h,3)
	var dl := distance_to(land,w,h); var ds := distance_to(sea,w,h)
	var paint := PackedFloat32Array(); paint.resize(n*4)
	var field := PackedFloat32Array(); field.resize(n*4)
	var distance := PackedFloat32Array(); distance.resize(n*2)
	var shade := PackedFloat32Array(); shade.resize(n)
	var ll := sqrt(3.69); var lx := -1.0/ll; var ly := lx; var lz := 1.3/ll
	for y in range(h):
		var zx := 0.008/maxf(sin((y+0.5)/h*PI),0.01)
		for x in range(w):
			var k := y*w+x
			var f := 1.0 if raster.water[k] == 0 else 0.0
			var dx: float = (raster.elev[y*w+posmod(x+1,w)]-raster.elev[y*w+posmod(x-1,w)])/2.0*zx*f
			var dy: float = (raster.elev[mini(h-1,y+1)*w+x]-raster.elev[maxi(0,y-1)*w+x])/2.0*0.008*f
			for c in range(3): paint[4*k+c] = rgb[c][k]/255.0
			paint[4*k+3] = (-dx*lx-dy*ly+lz)/sqrt(dx*dx+dy*dy+1.0)/lz
			shade[k] = paint[4*k+3]
			field[4*k] = raster.elev[k]; field[4*k+1] = raster.water[k]
			field[4*k+2] = raster.temp[k]; field[4*k+3] = raster.ice[k]
			distance[2*k] = dl[k]; distance[2*k+1] = ds[k]
	blur(shade,w,h,3)
	var ice := ice_field(raster) if prepared_ice.is_empty() else prepared_ice; var skirts := glyph_skirts(data,glyphs,w,h) if not data.is_empty() else PackedByteArray()
	var detail := PackedFloat32Array(); detail.resize(n*4)
	for k in range(n):
		detail[4*k] = ice.mask[k]; detail[4*k+1] = ice.near[k]/255.0; detail[4*k+2] = shade[k]
		detail[4*k+3] = 0 if skirts.is_empty() else skirts[k]/255.0
	return {"paint":float_data(paint,w,h,Image.FORMAT_RGBAF),"field":float_data(field,w,h,Image.FORMAT_RGBAF),"distance":float_data(distance,w,h,Image.FORMAT_RGF),"detail":float_data(detail,w,h,Image.FORMAT_RGBAF)}

static func float_texture(values: PackedFloat32Array,w: int,h: int,format_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(w,h,false,format_value,values.to_byte_array()))

static func float_data(values: PackedFloat32Array,w: int,h: int,format_value: int) -> Dictionary:
	return {"w":w,"h":h,"format":format_value,"bytes":values.to_byte_array()}
static func upload(row: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(row.w,row.h,false,row.format,row.bytes))
static func upload_all(rows: Dictionary) -> Dictionary:
	var result := {}
	for key in rows: result[key]=upload(rows[key])
	return result
