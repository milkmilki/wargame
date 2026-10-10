extends RefCounted
## civ-atlas 103afd3 ui/theme.css and countryPanel.css. AGPL-3.0-only.
const INK := Color("1d1d1f")
const MUTED := Color("6e6e73")
const ACCENT := Color("007aff")
const LINK := Color("0a6cdc")
const LINE := Color(.235,.235,.263,.16)
static var icons := {}
static func icon(name_value: String) -> Texture2D:
	if icons.has(name_value): return icons[name_value]
	var path := "res://assets/atlas/ui/%s.svg"%name_value
	if ResourceLoader.exists(path): icons[name_value]=load(path)
	else:
		# CLI/developer runs may precede the editor's SVG import. The same native
		# SVG decoder handles source assets; exported games use imported textures.
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(path))!=OK: return null
		icons[name_value]=ImageTexture.create_from_image(image)
	return icons[name_value]
static func box(color: Color,radius: int = 10,border: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color=color
	style.set_corner_radius_all(radius)
	if border: style.set_border_width_all(1); style.border_color=LINE
	return style
static func panel() -> StyleBoxFlat:
	var style := box(Color(.973,.973,.98,.94),14,true)
	style.shadow_color=Color(0,0,0,.16); style.shadow_size=14; style.shadow_offset=Vector2(0,8)
	style.content_margin_left=14; style.content_margin_right=14; style.content_margin_top=16; style.content_margin_bottom=16
	return style
static func create() -> Theme:
	var theme := Theme.new(); var font := SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei","Noto Sans SC","sans-serif"])
	theme.default_font=font; theme.default_font_size=14
	theme.set_color("font_color","Label",INK); theme.set_color("font_color","Button",INK)
	theme.set_color("font_hover_color","Button",INK); theme.set_color("font_pressed_color","Button",INK)
	theme.set_color("font_disabled_color","Button",MUTED)
	theme.set_stylebox("panel","PanelContainer",panel())
	var button := box(Color(.463,.463,.502,.12),8); button.content_margin_left=10; button.content_margin_right=10; button.content_margin_top=7; button.content_margin_bottom=7
	theme.set_stylebox("normal","Button",button); theme.set_stylebox("disabled","Button",button)
	theme.set_stylebox("hover","Button",box(Color(.463,.463,.502,.20),8)); theme.set_stylebox("pressed","Button",box(Color(.0,.478,1.,.12),8))
	var focus := box(Color(0,0,0,0),8); focus.set_border_width_all(2); focus.border_color=ACCENT; theme.set_stylebox("focus","Button",focus)
	for type_name in ["LineEdit","SpinBox","OptionButton"]:
		theme.set_color("font_color",type_name,INK)
		theme.set_stylebox("normal",type_name,button)
		theme.set_stylebox("focus",type_name,focus)
	theme.set_stylebox("panel","PopupMenu",panel()); theme.set_color("font_color","PopupMenu",INK)
	theme.set_constant("separation","VBoxContainer",8); theme.set_constant("separation","HBoxContainer",8)
	return theme
