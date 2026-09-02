class_name MapLayout
extends RefCounted
## Pure layout geometry for the 2D map and its persistent controls.

const BASE_SIDE_MARGIN := 40.0
const BASE_BOTTOM_MARGIN := 40.0
const BASE_HEADER_ONLY_TOP := 44.0
const NATION_STATS_BUTTON_WIDTH := 104.0
const ARMY_ICON_CONTROL_WIDTH := 500.0
const NATION_WINDOW_WIDTH: float = 1120.0
const NATION_WINDOW_TITLE_HEIGHT: float = 30.0
const NATION_WINDOW_HEADER_HEIGHT: float = 28.0
const NATION_WINDOW_ROW_HEIGHT: float = 46.0
const NATION_WINDOW_FOOTER_HEIGHT: float = 22.0
const NATION_WINDOW_MARGIN: float = 18.0
const NATION_TREE_INDENT: float = 14.0
const NATION_TREE_TOGGLE_SIZE: float = 14.0


static func compute_for_viewport(
	viewport_size: Vector2,
	nation_count: int
) -> Dictionary:
	var safe_size := Vector2(maxf(viewport_size.x, 1.0), maxf(viewport_size.y, 1.0))
	var display_scale := MapViewMath.visual_scale_for_viewport(safe_size)
	var side_margin := BASE_SIDE_MARGIN * display_scale
	var available_width := maxf(safe_size.x - side_margin * 2.0, 1.0)
	var count := maxi(nation_count, 1)
	var minimum_card_width := 280.0 * display_scale
	var hud_columns := clampi(
		int(floor(available_width / maxf(minimum_card_width, 1.0))),
		1,
		count
	)
	var top_margin := BASE_HEADER_ONLY_TOP * display_scale
	var bottom_margin := BASE_BOTTOM_MARGIN * display_scale
	var span := maxf(
		minf(available_width, safe_size.y - top_margin - bottom_margin),
		1.0
	)
	return {
		"cell": span / float(GameState.GRID),
		"span": span,
		"origin": Vector2((safe_size.x - span) * 0.5, top_margin),
		"display_scale": display_scale,
		"side_margin": side_margin,
		"hud_columns": hud_columns,
		"hud_card_width": available_width / float(hud_columns),
	}


static func nation_stats_button_rect(
	viewport_size: Vector2,
	display_scale: float,
	side_margin: float
) -> Rect2:
	var size := Vector2(
		NATION_STATS_BUTTON_WIDTH * display_scale,
		22.0 * display_scale
	)
	return Rect2(
		Vector2(viewport_size.x - side_margin - size.x, 8.0 * display_scale),
		size
	)


static func nation_stats_window_size(
	viewport_size: Vector2,
	display_scale: float,
	alive_nation_count: int
) -> Vector2:
	var margin := NATION_WINDOW_MARGIN * display_scale
	var width := maxf(
		minf(NATION_WINDOW_WIDTH * display_scale, viewport_size.x - margin * 2.0),
		1.0
	)
	var fixed_height := (
		NATION_WINDOW_TITLE_HEIGHT
		+ NATION_WINDOW_HEADER_HEIGHT
		+ NATION_WINDOW_FOOTER_HEIGHT
	) * display_scale
	var available_rows_height := maxf(
		viewport_size.y - margin * 2.0 - fixed_height,
		NATION_WINDOW_ROW_HEIGHT * display_scale
	)
	var capacity := maxi(
		int(floor(available_rows_height / (NATION_WINDOW_ROW_HEIGHT * display_scale))),
		1
	)
	var visible_rows := mini(maxi(alive_nation_count, 1), capacity)
	return Vector2(
		width,
		fixed_height + float(visible_rows) * NATION_WINDOW_ROW_HEIGHT * display_scale
	)


static func nation_stats_visible_row_capacity(
	window_size: Vector2,
	display_scale: float
) -> int:
	var fixed_height := (
		NATION_WINDOW_TITLE_HEIGHT
		+ NATION_WINDOW_HEADER_HEIGHT
		+ NATION_WINDOW_FOOTER_HEIGHT
	) * display_scale
	return maxi(
		int(floor(
			(window_size.y - fixed_height)
				/ (NATION_WINDOW_ROW_HEIGHT * display_scale)
		)),
		1
	)


static func nation_stats_window_rect(
	viewport_size: Vector2,
	display_scale: float,
	position: Vector2,
	alive_nation_count: int
) -> Rect2:
	var size := nation_stats_window_size(
		viewport_size,
		display_scale,
		alive_nation_count
	)
	var margin := NATION_WINDOW_MARGIN * display_scale
	var maximum := Vector2(
		maxf(viewport_size.x - size.x - margin, margin),
		maxf(viewport_size.y - size.y - margin, margin)
	)
	return Rect2(
		Vector2(
			clampf(position.x, margin, maximum.x),
			clampf(position.y, margin, maximum.y)
		),
		size
	)


static func nation_stats_title_rect(
	window_rect: Rect2,
	display_scale: float
) -> Rect2:
	return Rect2(
		window_rect.position,
		Vector2(window_rect.size.x, NATION_WINDOW_TITLE_HEIGHT * display_scale)
	)


static func nation_stats_close_rect(
	window_rect: Rect2,
	display_scale: float
) -> Rect2:
	var side := 22.0 * display_scale
	return Rect2(
		Vector2(
			window_rect.end.x - side - 4.0 * display_scale,
			window_rect.position.y + 4.0 * display_scale
		),
		Vector2(side, side)
	)


static func nation_stats_row_rect(
	window_rect: Rect2,
	display_scale: float,
	visual_index: int
) -> Rect2:
	return Rect2(
		Vector2(
			window_rect.position.x,
			window_rect.position.y
				+ (
					NATION_WINDOW_TITLE_HEIGHT
					+ NATION_WINDOW_HEADER_HEIGHT
					+ float(maxi(visual_index, 0)) * NATION_WINDOW_ROW_HEIGHT
				) * display_scale
		),
		Vector2(window_rect.size.x, NATION_WINDOW_ROW_HEIGHT * display_scale)
	)


static func nation_tree_toggle_rect(
	row_rect: Rect2,
	display_scale: float,
	depth: int
) -> Rect2:
	var side := NATION_TREE_TOGGLE_SIZE * display_scale
	return Rect2(
		Vector2(
			row_rect.position.x
				+ row_rect.size.x * 0.02
				+ float(maxi(depth, 0)) * NATION_TREE_INDENT * display_scale,
			row_rect.position.y + (row_rect.size.y - side) * 0.5
		),
		Vector2(side, side)
	)


static func army_icon_scale_control_rect(
	viewport_size: Vector2,
	display_scale: float,
	side_margin: float
) -> Rect2:
	var stats_rect := nation_stats_button_rect(
		viewport_size,
		display_scale,
		side_margin
	)
	var size := Vector2(ARMY_ICON_CONTROL_WIDTH * display_scale, 22.0 * display_scale)
	return Rect2(
		Vector2(
			stats_rect.position.x - 8.0 * display_scale - size.x,
			8.0 * display_scale
		),
		size
	)
