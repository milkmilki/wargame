extends PanelContainer
## Small, stable-ID country browser sharing the native inspector theme.
signal selected(id: int)
const Style = preload("res://scripts/atlas/information_theme.gd")
const Diplomacy = preload("res://scripts/atlas/diplomacy_view.gd")
var source_provider: Callable
var observer_provider: Callable
var search := LineEdit.new()
var list := VBoxContainer.new()
var empty_label := Label.new()
var entries := {}
var content_key := -1
var elapsed := 0.
var refresh_count := 0
func _init():
	theme=Style.create(); mouse_force_pass_scroll_events=false
	var body := VBoxContainer.new(); add_child(body)
	var header := HBoxContainer.new(); body.add_child(header)
	var title := Label.new(); title.text="国家"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	var close := Button.new(); close.text="×"; close.pressed.connect(hide); header.add_child(close)
	search.placeholder_text="搜索国家名称"; search.text_changed.connect(func(_text): refresh()); body.add_child(search)
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.mouse_force_pass_scroll_events=false; body.add_child(scroll)
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	empty_label.text="没有符合条件的存续国家"; empty_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; list.add_child(empty_label)
	visible=false
func refresh() -> void:
	if not visible or not source_provider.is_valid(): return
	var state: GameState=source_provider.call(); var observer: int=observer_provider.call()
	var rows := Diplomacy.rows(state,observer,search.text); var key := hash(rows)
	if key==content_key: return
	content_key=key; refresh_count+=1
	for button in entries.values(): button.hide()
	for row in rows:
		if not entries.has(row.id):
			var button := Button.new(); button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			button.pressed.connect(func(): selected.emit(row.id); hide())
			entries[row.id]=button; list.add_child(button)
		var control: Button=entries[row.id]
		control.text="%s · %s\n首都：%s · 治所 %d"%[row.name,row.relation,row.capital,row.count]
		control.tooltip_text=control.text; control.show()
		list.move_child(control,list.get_child_count()-1)
	empty_label.visible=rows.is_empty()
func open() -> void:
	show(); refresh()
func _process(delta: float) -> void:
	if not visible: return
	elapsed+=delta
	if elapsed>=.5: elapsed=0.; refresh()
