extends RefCounted
## civ-atlas util.ts tileableFbm, gradient tiles, independent from simplex. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
static func build(seed_value: int,size: int,cells: int,octaves: int,persistence: float = .5) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(size*size); var rng := Maths.Stream.new(seed_value)
	var ux := PackedFloat32Array(); ux.resize(256); var uy := ux.duplicate()
	for i in range(256): ux[i] = cos(float(i)/256*PI*2); uy[i] = sin(float(i)/256*PI*2)
	var amp := 1.0
	for octave in range(octaves):
		var c := cells*(1<<octave); var gx := PackedFloat32Array(); gx.resize(c*c); var gy := gx.duplicate()
		for i in range(c*c):
			var index := int(rng.next()*256); gx[i] = ux[index]; gy[i] = uy[index]
		var ox := rng.next()*c; var oy := rng.next()*c; var frequency := float(c)/size
		for y in range(size):
			var v := y*frequency+oy; var vi := int(v); var ty := v-vi; var sy := ty*ty*ty*(ty*(ty*6-15)+10)
			var y0 := vi-c if vi>=c else vi; var row0 := y0*c; var row1 := ((y0+1)%c)*c
			for x in range(size):
				var u := x*frequency+ox; var ui := int(u); var tx := u-ui; var sx := tx*tx*tx*(tx*(tx*6-15)+10)
				var x0 := ui-c if ui>=c else ui; var x1 := (x0+1)%c
				var n00 := gx[row0+x0]*tx+gy[row0+x0]*ty; var n10 := gx[row0+x1]*(tx-1)+gy[row0+x1]*ty
				var n01 := gx[row1+x0]*tx+gy[row1+x0]*(ty-1); var n11 := gx[row1+x1]*(tx-1)+gy[row1+x1]*(ty-1)
				var a0 := n00+(n10-n00)*sx; var a1 := n01+(n11-n01)*sx
				out[y*size+x] += amp*(a0+(a1-a0)*sy)
		amp *= persistence
	var sum_value := 0.0; var sum2 := 0.0
	for value in out: sum_value += value; sum2 += value*value
	var mean := sum_value/out.size(); var inv := 1.0/sqrt(maxf(1e-12,sum2/out.size()-mean*mean))
	for i in range(out.size()): out[i] = (out[i]-mean)*inv
	return out
