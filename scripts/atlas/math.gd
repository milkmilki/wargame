extends RefCounted
static func hash2(x: int,y: int,seed_value: int = 0) -> float:
	# JS first sums integer products in binary64, then coerces to int32.
	var h := int(float(x)*374761393.0+float(y)*668265263.0+float(seed_value)*982451653.0) & 0xffffffff
	h = ((h ^ (h >> 13))*1274126177) & 0xffffffff
	h ^= h >> 16
	return float(h)/4294967296.0

static func hash3(x: int,y: int,z: int,seed_value: int) -> float:
	var h := int(float(x)*374761393.0+float(y)*668265263.0+float(z)*1442695041.0+seed_value)&0xffffffff
	h = ((h^(h>>13))*1274126177)&0xffffffff; h ^= h>>16
	return float(h)/4294967296.0

static func value_noise(x: float,y: float,seed_value: int) -> float:
	var xi := int(floor(x)); var yi := int(floor(y)); var fx := x-xi; var fy := y-yi
	var ux := fx*fx*(3.0-2.0*fx); var uy := fy*fy*(3.0-2.0*fy)
	var a := hash2(xi,yi,seed_value); var b := hash2(xi+1,yi,seed_value)
	var c := hash2(xi,yi+1,seed_value); var d := hash2(xi+1,yi+1,seed_value)
	return a+(b-a)*ux+(c-a)*uy+(a-b-c+d)*ux*uy

static func value_noise_periodic(x: float,y: float,seed_value: int,period: int) -> float:
	var xi := int(floor(x)); var yi := int(floor(y)); var fx := x-xi; var fy := y-yi
	var ux := fx*fx*(3-2*fx); var uy := fy*fy*(3-2*fy)
	var x0 := posmod(xi,period); var x1 := (x0+1)%period
	var a := hash2(x0,yi,seed_value); var b := hash2(x1,yi,seed_value)
	var c := hash2(x0,yi+1,seed_value); var d := hash2(x1,yi+1,seed_value)
	return a+(b-a)*ux+(c-a)*uy+(a-b-c+d)*ux*uy
## Port of civ-atlas 103afd3 util.ts / civ/rand.ts. AGPL-3.0-only.
const MASK := 0xffffffff

class Stream:
	var state: int
	func _init(seed_value: int) -> void: state = seed_value & 0xffffffff
	func next() -> float:
		state = (state + 0x6d2b79f5) & 0xffffffff
		var t := ((state ^ (state >> 15)) * (1 | state)) & 0xffffffff
		t = (((t + (((t ^ (t >> 7)) * (61 | t)) & 0xffffffff)) & 0xffffffff) ^ t) & 0xffffffff
		return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0

static func sub_seed(seed_value: int, salt: String) -> int:
	var h := (seed_value ^ 0x9e3779b9) & MASK
	for i in range(salt.length()):
		h = ((h ^ salt.unicode_at(i)) * 0x85ebca6b) & MASK
		h = (h ^ (h >> 13)) & MASK
	return h

static func fmix(value: int) -> int:
	var h := value & MASK
	h = h ^ (h >> 16)
	h = (h * 0x85ebca6b) & MASK
	h = h ^ (h >> 13)
	h = (h * 0xc2b2ae35) & MASK
	return (h ^ (h >> 16)) & MASK

static func keyed(base: int, a: int = 0, b: int = 0, c: int = 0) -> float:
	var h := fmix(base ^ 0x2545f491)
	h = fmix(h ^ ((a * 0x9e3779b1) & MASK))
	h = fmix(h ^ ((b * 0x85ebca77) & MASK))
	h = fmix(h ^ ((c * 0xc2b2ae3d) & MASK))
	return float(h) / 4294967296.0

static func round24(x: float) -> float:
	if not absf(x) < 1e290: return x
	var c := x * 536870913.0
	return c - (c - x)

static func fpow(x: float, y: float) -> float: return round24(pow(x,y))
static func fexp(x: float) -> float: return round24(exp(x))
static func flog(x: float) -> float: return round24(log(x))
static func flog2(x: float) -> float: return round24(log(x)/log(2.0))
static func f32(x: float) -> float: return PackedFloat32Array([x])[0]
static func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x-a)/(b-a),0.0,1.0)
	return t*t*(3.0-2.0*t)

class Heap:
	var ids := PackedInt32Array()
	var priorities := PackedFloat64Array()
	var size := 0
	var last_priority := 0.0
	func empty() -> bool:
		return size == 0
	func clear() -> void:
		size = 0
	func push(id: int, priority: float) -> void:
		var i := size
		size += 1
		if ids.size() < size: ids.resize(maxi(64,size*2)); priorities.resize(ids.size())
		while i > 0:
			var parent := (i-1) >> 1
			if priorities[parent] <= priority: break
			ids[i] = ids[parent]; priorities[i] = priorities[parent]; i = parent
		ids[i] = id; priorities[i] = priority
	func pop() -> int:
		var result := ids[0]
		last_priority = priorities[0]
		size -= 1
		if size > 0:
			var id := ids[size]; var priority := priorities[size]; var i := 0
			while true:
				var child := 2*i+1
				if child >= size: break
				if child+1 < size and priorities[child+1] < priorities[child]: child += 1
				if priorities[child] >= priority: break
				ids[i] = ids[child]; priorities[i] = priorities[child]; i = child
			ids[i] = id; priorities[i] = priority
		return result
