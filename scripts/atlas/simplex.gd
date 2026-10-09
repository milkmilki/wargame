extends RefCounted
## 3D simplex-noise 4.0.3 algorithm, native scalar binary64 port.
## Copyright (c) 2024 Jonas Wagner; MIT, see assets/atlas/LICENSE-simplex-noise.txt.
## Gradient method by Stefan Gustavson, optimizations by Peter Eastman.
const Maths = preload("res://scripts/atlas/math.gd")
const GRAD = [1,1,0,-1,1,0,1,-1,0,-1,-1,0,1,0,1,-1,0,1,1,0,-1,-1,0,-1,0,1,1,0,-1,1,0,1,-1,0,-1,-1]
const G3 := 1.0/6.0
var perm := PackedInt32Array()

func _init(seed_value: int) -> void:
	var rng := Maths.Stream.new(seed_value); perm.resize(512)
	for i in range(256): perm[i] = i
	for i in range(255):
		var r := i+int(rng.next()*(256-i)); var tmp := perm[i]; perm[i] = perm[r]; perm[r] = tmp
	for i in range(256,512): perm[i] = perm[i-256]

func contribution(x: float,y: float,z: float,i: int,j: int,k: int) -> float:
	var t := .6-x*x-y*y-z*z
	if t<0: return 0
	var index := (perm[i+perm[j+perm[k]]] % 12)*3; t *= t
	return t*t*(GRAD[index]*x+GRAD[index+1]*y+GRAD[index+2]*z)

func at(x: float,y: float,z: float) -> float:
	var s := (x+y+z)/3.0
	# Multiply by the exact binary64 1/3, matching upstream evaluation order.
	s = (x+y+z)*(1.0/3.0)
	var i := int(floor(x+s)); var j := int(floor(y+s)); var k := int(floor(z+s)); var t := (i+j+k)*G3
	var x0 := x-(i-t); var y0 := y-(j-t); var z0 := z-(k-t)
	var i1 := 0; var j1 := 0; var k1 := 0; var i2 := 0; var j2 := 0; var k2 := 0
	if x0>=y0:
		if y0>=z0: i1 = 1; i2 = 1; j2 = 1
		elif x0>=z0: i1 = 1; i2 = 1; k2 = 1
		else: k1 = 1; i2 = 1; k2 = 1
	else:
		if y0<z0: k1 = 1; j2 = 1; k2 = 1
		elif x0<z0: j1 = 1; j2 = 1; k2 = 1
		else: j1 = 1; i2 = 1; j2 = 1
	var ii := i&255; var jj := j&255; var kk := k&255
	var n0 := contribution(x0,y0,z0,ii,jj,kk)
	var n1 := contribution(x0-i1+G3,y0-j1+G3,z0-k1+G3,ii+i1,jj+j1,kk+k1)
	var n2 := contribution(x0-i2+2.0*G3,y0-j2+2.0*G3,z0-k2+2.0*G3,ii+i2,jj+j2,kk+k2)
	var n3 := contribution(x0-1.0+3.0*G3,y0-1.0+3.0*G3,z0-1.0+3.0*G3,ii+1,jj+1,kk+1)
	return 32.0*(n0+n1+n2+n3)

func fbm(x: float,y: float,z: float,octaves: int,persistence: float = .5) -> float:
	var value := 0.0; var amp := 1.0; var frequency := 1.0; var norm := 0.0
	for o in range(octaves):
		value += amp*at(x*frequency+o*17.3,y*frequency-o*9.1,z*frequency+o*5.7)
		norm += amp; amp *= persistence; frequency *= 2.0
	return value/norm

func ridged(x: float,y: float,z: float,octaves: int,persistence: float = .5) -> float:
	var value := 0.0; var amp := 1.0; var frequency := 1.0; var norm := 0.0; var weight := 1.0
	for o in range(octaves):
		var r := 1.0-absf(at(x*frequency+o*31.7,y*frequency+o*7.7,z*frequency-o*3.1))
		r *= r; r *= weight; weight = minf(1,r*2)
		value += amp*r; norm += amp; amp *= persistence; frequency *= 2.0
	return value/norm
