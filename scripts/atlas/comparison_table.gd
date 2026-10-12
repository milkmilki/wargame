extends VBoxContainer
## Two value columns share row height and width, including wrapped morale text.
const Style = preload("res://scripts/atlas/information_theme.gd")
const COLORS = [Color("984843"),Color("6654b5")]
var cells: Array=[]
var headers: Array[Label]=[]
func _init(group: Dictionary) -> void:
	add_theme_constant_override("separation",0)
	var heading:=make_line("指标")
	for index in range(2):
		var label:=value_label(index); heading.add_child(label); headers.append(label)
	for row in group.rows:
		var separator:=ColorRect.new(); separator.color=Style.LINE; separator.custom_minimum_size.y=1
		separator.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(separator)
		var line:=make_line(row.label); var nodes: Array[Label]=[]
		for index in range(2):
			var label:=value_label(index); line.add_child(label); nodes.append(label)
		cells.append({"nodes":nodes})
	configure(group)
func make_line(caption: String) -> HBoxContainer:
	var margin:=MarginContainer.new()
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,12)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,9)
	add_child(margin)
	var line:=HBoxContainer.new(); line.add_theme_constant_override("separation",8); margin.add_child(line)
	var key:=Label.new(); key.text=caption; key.custom_minimum_size.x=112
	key.add_theme_font_size_override("font_size",13); key.add_theme_color_override("font_color",Style.MUTED)
	key.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; line.add_child(key)
	return line
func value_label(index: int) -> Label:
	var label:=Label.new(); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.add_theme_font_size_override("font_size",13)
	label.add_theme_color_override("font_color",COLORS[index]); return label
func configure(group: Dictionary) -> void:
	for index in range(2): headers[index].text=group.columns[index]
	for row_index in range(cells.size()):
		for index in range(2):
			var label: Label=cells[row_index].nodes[index]
			label.text=group.rows[row_index].cells[index]
			label.tooltip_text="%s · %s：%s"%[group.columns[index],group.rows[row_index].label,label.text]
