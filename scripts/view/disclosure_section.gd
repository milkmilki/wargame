class_name DisclosureSection
extends VBoxContainer
## Presentation-only disclosure; the owner decides how long preferences live.

signal expanded_changed(value: bool)

var expanded := true
var header: Button
var body: VBoxContainer
var _title := ""


func _init() -> void:
	add_theme_constant_override("separation", 3)
	header = Button.new()
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_color_override("font_color", MapRenderer.INK_COLOR)
	header.add_theme_color_override("font_hover_color", MapRenderer.INK_COLOR)
	header.add_theme_color_override("font_focus_color", MapRenderer.INK_COLOR)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(MapRenderer.INK_COLOR, 0.08)
	normal.set_content_margin_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(MapRenderer.INK_COLOR, 0.15)
	header.add_theme_stylebox_override("normal", normal)
	header.add_theme_stylebox_override("hover", hover)
	header.add_theme_stylebox_override("pressed", hover)
	header.pressed.connect(func() -> void: set_expanded(not expanded))
	add_child(header)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	add_child(body)


func set_title(value: String) -> void:
	_title = value
	_sync_header()


func set_expanded(value: bool) -> void:
	if expanded == value:
		return
	expanded = value
	body.visible = value
	_sync_header()
	expanded_changed.emit(value)


func _sync_header() -> void:
	header.text = ("▼ " if expanded else "▶ ") + _title
	header.tooltip_text = ("收起" if expanded else "展开") + _title
