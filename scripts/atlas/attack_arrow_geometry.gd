extends RefCounted
## Native port of OL Plot AttackArrow + its quadratic B-spline helpers.
## Copyright (c) 2017 sakitam-fdd, MIT; see assets/atlas/LICENSE-ol-plot.txt.
## Upstream c919e60b4edeaeca53c08f9552f793b2ae9537f0.

static func third(a: Vector2, b: Vector2, angle: float, length: float, clockwise: bool) -> Vector2:
	var azimuth := (a - b).angle()
	var alpha := azimuth + angle if clockwise else azimuth - angle
	return b + Vector2(cos(alpha), sin(alpha)) * length

static func spline(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2: return points
	var out := PackedVector2Array([points[0]])
	for i in range(points.size() - 2):
		# Upstream samples t in 0.05 increments (the floating loop excludes 1).
		for step in range(20):
			var t := step * .05
			out.append(points[i] * pow(t - 1., 2.) / 2. + points[i+1] * (-2.*t*t + 2.*t + 1.) / 2. + points[i+2] * t*t / 2.)
	out.append(points[-1])
	return out

static func polygon(axis: PackedVector2Array, tail_width: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in axis:
		if not point.is_finite(): return PackedVector2Array()
		var converted := Vector2(point.x, -point.y) # OL geometry uses y-up.
		if points.is_empty() or converted.distance_squared_to(points[-1]) > 1e-8: points.append(converted)
	if points.size() < 2 or not is_finite(tail_width) or tail_width <= 0.: return PackedVector2Array()
	var length := 0.
	for i in range(1, points.size()): length += points[i-1].distance_to(points[i])
	if length < .001: return PackedVector2Array()
	var normal := Vector2(-(points[1]-points[0]).y, (points[1]-points[0]).x).normalized()
	var left := points[0] + normal * tail_width / 2.
	var right := points[0] - normal * tail_width / 2.
	# Select the same left/right ordering as upstream's isClockWise.
	if (points[1].y-left.y)*(right.x-left.x) > (right.y-left.y)*(points[1].x-left.x):
		var swap := left; left = right; right = swap
	var head_height := minf(pow(length, .99) * .18, tail_width * .8)
	var head_width := head_height * .3
	var neck_width := head_height * .15
	head_height = minf(head_height, points[-1].distance_to(points[-2]))
	var head_end := third(points[-2], points[-1], 0., head_height, true)
	var neck_end := third(points[-2], points[-1], 0., head_height * .85, true)
	var head := PackedVector2Array([
		third(points[-1], neck_end, PI/2., neck_width, false),
		third(points[-1], head_end, PI/2., head_width, false), points[-1],
		third(points[-1], head_end, PI/2., head_width, true),
		third(points[-1], neck_end, PI/2., neck_width, true)])
	var left_body := PackedVector2Array([left]); var right_body := PackedVector2Array([right])
	var width_difference := (tail_width - head[0].distance_to(head[-1])) / 2.
	var travelled := 0.
	for i in range(1, points.size()-1):
		var angle := fposmod((points[i]-points[i-1]).angle() - (points[i]-points[i+1]).angle(), TAU) / 2.
		travelled += points[i-1].distance_to(points[i])
		var sin_angle := sin(angle)
		var safe_sin := .0001 if absf(sin_angle) < .0001 else sin_angle
		var width := (tail_width/2. - travelled/length * width_difference) / safe_sin
		left_body.append(third(points[i-1], points[i], PI-angle, width, true))
		right_body.append(third(points[i-1], points[i], angle, width, false))
	left_body.append(head[0]); right_body.append(head[-1])
	var ring := spline(left_body); ring.append_array(head)
	var reverse := spline(right_body); reverse.reverse(); ring.append_array(reverse)
	var result := PackedVector2Array()
	for point in ring:
		point.y = -point.y
		# Godot triangulation expects an open ring with no duplicate neck points.
		if result.is_empty() or point.distance_squared_to(result[-1]) > 1e-8: result.append(point)
	if result.size() > 1 and result[0].distance_squared_to(result[-1]) < 1e-8: result.remove_at(result.size()-1)
	return result
