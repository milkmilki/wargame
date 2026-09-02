class_name MapViewMath
extends RefCounted
## Pure viewport transform rules used by the 2D strategic map.

const MAP_ZOOM_MIN: float = 1.0
const MAP_ZOOM_MAX: float = 4.0
const MAP_ZOOM_WHEEL_FACTOR: float = 1.2
const VISUAL_SCALE_COMPACT: float = 0.80
const VISUAL_SCALE_STANDARD: float = 1.00
const VISUAL_SCALE_LARGE: float = 1.25
const VISUAL_SCALE_XL: float = 1.50


static func magnify_zoom_multiplier(factor: float) -> float:
	return clampf(factor, 0.5, 2.0)


static func wheel_zoom_multiplier(button_index: int, factor: float) -> float:
	var direction := (
		1.0
		if button_index == MOUSE_BUTTON_WHEEL_UP
		else -1.0
	)
	return pow(
		MAP_ZOOM_WHEEL_FACTOR,
		direction * maxf(factor, 0.05)
	)


static func clamp_map_pan(
	pan: Vector2,
	zoom: float,
	base_map_size: Vector2
) -> Vector2:
	var clamped_zoom := maxf(zoom, MAP_ZOOM_MIN)
	var limit := base_map_size * (clamped_zoom - MAP_ZOOM_MIN) * 0.5
	return Vector2(
		clampf(pan.x, -limit.x, limit.x),
		clampf(pan.y, -limit.y, limit.y)
	)


static func map_view_origin(
	base_origin: Vector2,
	base_map_size: Vector2,
	zoom: float,
	pan: Vector2
) -> Vector2:
	var zoomed_size := base_map_size * zoom
	return (
		base_origin
		+ (base_map_size - zoomed_size) * 0.5
		+ clamp_map_pan(pan, zoom, base_map_size)
	)


static func map_pan_for_zoom_anchor(
	base_origin: Vector2,
	base_map_size: Vector2,
	old_zoom: float,
	old_pan: Vector2,
	new_zoom: float,
	anchor: Vector2
) -> Vector2:
	var old_size := base_map_size * old_zoom
	var old_origin := map_view_origin(
		base_origin,
		base_map_size,
		old_zoom,
		old_pan
	)
	var normalized_anchor := Vector2(
		(anchor.x - old_origin.x) / maxf(old_size.x, 0.0001),
		(anchor.y - old_origin.y) / maxf(old_size.y, 0.0001)
	)
	var new_size := base_map_size * new_zoom
	var centered_origin := base_origin + (base_map_size - new_size) * 0.5
	var desired_pan := anchor - centered_origin - normalized_anchor * new_size
	return clamp_map_pan(desired_pan, new_zoom, base_map_size)


static func visual_scale_for_viewport(viewport_size: Vector2) -> float:
	var short_side := minf(viewport_size.x, viewport_size.y)
	if short_side < 600.0:
		return VISUAL_SCALE_COMPACT
	if short_side < 900.0:
		return VISUAL_SCALE_STANDARD
	if short_side < 1400.0:
		return VISUAL_SCALE_LARGE
	return VISUAL_SCALE_XL
