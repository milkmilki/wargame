extends VBoxContainer
## Reusable live-ruler controls. The simulation remains the mutation authority.
signal changed(nation_id: int, archetype: int, traits: Array[String])
signal pause_requested
var nation_id: int = -1
var archetype := OptionButton.new()
var traits: Array[OptionButton] = []
var editable := false
class PauseInput extends Node:
	var editor
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode==KEY_SPACE:
			if event.pressed and not event.echo: editor.pause_requested.emit()
			get_viewport().set_input_as_handled()
func _init() -> void:
	add_theme_constant_override("separation",8)
	for id in RulerProfile.ARCHETYPE_IDS: archetype.add_item(RulerProfile.archetype_name(id),id)
	add_control("君主类型",archetype)
	archetype.item_selected.connect(func(_index): emit_change())
	for slot in range(RulerProfile.MAX_TRAITS):
		var control := OptionButton.new(); control.add_item("无附加特质")
		control.set_item_metadata(0,"")
		for id in RulerProfile.TRAIT_IDS:
			control.add_item(RulerProfile.trait_name(id));control.set_item_metadata(control.item_count-1,id)
		traits.append(control);add_control("特质%d"%(slot+1),control)
		control.item_selected.connect(func(_index): emit_change())
func add_control(label_value: String, control: OptionButton) -> void:
	var line := HBoxContainer.new();add_child(line)
	var label := Label.new();label.text=label_value;label.add_theme_font_size_override("font_size",13);line.add_child(label)
	control.size_flags_horizontal=Control.SIZE_EXPAND_FILL;control.custom_minimum_size.x=160
	control.tooltip_text="选择后立即生效；不改变君主姓名和任期。";line.add_child(control)
	var input := PauseInput.new();input.editor=self;control.get_popup().add_child(input)
func selected_traits() -> Array[String]:
	var selected: Array[String]=[]
	for control in traits:
		var id: String=control.get_item_metadata(control.selected)
		if not id.is_empty(): selected.append(id)
	return selected
func configure(value: Dictionary) -> void:
	var current:=selected_traits();current.sort()
	var wanted: Array[String]=[];wanted.assign(value.traits);wanted.sort()
	# Keep a user's slot order when the simulation normalizes the same trait set.
	if nation_id!=value.id or current!=wanted:
		for slot in range(traits.size()):
			traits[slot].select(1+RulerProfile.TRAIT_IDS.find(wanted[slot]) if slot<wanted.size() else 0)
	nation_id=value.id;editable=not value.get("disabled",false)
	archetype.select(archetype.get_item_index(value.archetype));archetype.disabled=not editable
	for slot in range(traits.size()):
		var control:=traits[slot];control.disabled=not editable
		var other: String=traits[1-slot].get_item_metadata(traits[1-slot].selected)
		for index in range(RulerProfile.TRAIT_IDS.size()):
			var id: String=RulerProfile.TRAIT_IDS[index]
			var conflict:=id==other or (id==RulerProfile.TRAIT_CENTRALIZER and other==RulerProfile.TRAIT_FEUDALIST) or (id==RulerProfile.TRAIT_FEUDALIST and other==RulerProfile.TRAIT_CENTRALIZER)
			control.set_item_disabled(index+1,conflict)
		if not editable: control.get_popup().hide()
	if not editable: archetype.get_popup().hide()
func emit_change() -> void:
	if editable: changed.emit(nation_id,archetype.get_selected_id(),selected_traits())
