extends VBoxContainer
## Pending generation settings; applying them starts a new world.
const Mask = preload("res://scripts/atlas/settlement_mask.gd")
var host
var military := false
var enabled := CheckButton.new()
var fields := {}
var apply_button := Button.new()
var notice := Label.new()

func setup(view) -> void:
	host=view; military=view.has_method("can_rebuild")
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	enabled.text="限制城市生成范围"; add_child(enabled)
	for keys in [["south","north"],["west","east"]]:
		var row := HBoxContainer.new(); add_child(row)
		for key in keys:
			var label := Label.new(); label.text={"south":"南界","north":"北界","west":"西界","east":"东界"}[key]; row.add_child(label)
			var input := SpinBox.new(); input.min_value=-90. if key in ["south","north"] else -180.; input.max_value=-input.min_value
			input.step=1.; input.suffix="°"; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			fields[key]=input; row.add_child(input)
	apply_button.text="应用范围并重新开局"; add_child(apply_button); apply_button.pressed.connect(apply_settings)
	notice.text="北纬、东经为正；南纬、西经为负。\n范围外适宜度为0，不生成城市。应用会重新开局。"
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; notice.add_theme_font_size_override("font_size",12); add_child(notice)
	sync()

func sync() -> void:
	var settings: Dictionary=Mask.EURASIA.duplicate(); settings.enabled=false
	settings.merge(host.settlement_mask,true)
	enabled.set_pressed_no_signal(settings.enabled)
	for key in fields: fields[key].set_value_no_signal(settings[key])

func blocked() -> bool:
	return host.generating or (military and (host.historical_view or (host.simulation!=null and host.simulation.runtime_day_in_progress())))

func _process(_delta: float) -> void:
	if host==null: return
	var busy := blocked()
	apply_button.disabled=busy; enabled.disabled=busy
	for input in fields.values(): input.editable=not busy and enabled.button_pressed

func apply_settings() -> void:
	if blocked() or (military and not host.can_rebuild()): return
	var settings := {"enabled":enabled.button_pressed,"version":Mask.VERSION}
	for key in fields: settings[key]=fields[key].value
	var error := Mask.validate(settings)
	if not error.is_empty(): host.status.text=error; return
	if military and host.simulation!=null: host.simulation.paused=true
	host.settlement_mask=Mask.normalize(settings)
	await host.load_native(int(host.seed_control.value))
	# Failed generation leaves the previous world and its policy intact.
	if not host.data.is_empty(): host.sync_settlement_mask()
