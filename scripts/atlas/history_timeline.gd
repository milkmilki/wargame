extends VBoxContainer
## Monthly political snapshots plus a separate live stop; no simulation state is owned here.
const Style = preload("res://scripts/atlas/information_theme.gd")
const Calendar = preload("res://scripts/core/game_calendar.gd")
var host
var date := Label.new()
var first_date := Label.new()
var live_date := Label.new()
var previous := Button.new()
var next := Button.new()
var current := Button.new()
var refresh_key: Array=[]

func setup(view) -> void:
	host=view; mouse_filter=Control.MOUSE_FILTER_STOP; mouse_force_pass_scroll_events=false
	var track := HBoxContainer.new(); add_child(track)
	var title := Label.new(); title.text="历史发展"; track.add_child(title)
	previous.text="‹"; previous.tooltip_text="上一个历史快照"; track.add_child(previous)
	previous.pressed.connect(func(): host.select_history(maxi(0,int(host.history_control.value)-1)))
	var slider: HSlider=view.history_control
	slider.min_value=0; slider.max_value=0; slider.step=1
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL; slider.custom_minimum_size=Vector2(100,28)
	slider.tooltip_text="拖动查看历史版图与外交；每30天记录一次，最右端为现在。"
	slider.value_changed.connect(func(value): host.select_history(int(value)))
	var rail := Style.box(Color(.463,.463,.502,.18),3); rail.content_margin_top=3; rail.content_margin_bottom=3
	slider.add_theme_stylebox_override("slider",rail)
	slider.add_theme_stylebox_override("grabber_area",Style.box(Style.ACCENT,3))
	slider.add_theme_stylebox_override("grabber_area_highlight",Style.box(Style.ACCENT,3))
	track.add_child(slider)
	next.text="›"; next.tooltip_text="下一个快照／返回现在"; track.add_child(next)
	next.pressed.connect(func(): host.select_history(int(host.history_control.value)+1))
	current.text="返回现在"; current.pressed.connect(view.return_to_current); track.add_child(current)
	var dates := HBoxContainer.new(); add_child(dates)
	first_date.text="开局 · "+Calendar.date(0); dates.add_child(first_date)
	date.size_flags_horizontal=Control.SIZE_EXPAND_FILL; date.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	date.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; dates.add_child(date)
	live_date.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; dates.add_child(live_date)
	for label in [first_date,live_date]:
		label.add_theme_font_size_override("font_size",12); label.add_theme_color_override("font_color",Style.MUTED)
	refresh()

func refresh() -> void:
	var ready: bool=host.state!=null and host.simulation!=null and host.view_ready and not host.generating
	var count: int=host.history.snapshot_count()
	var index := int(host.history_control.value)
	var key: Array=[ready,count,index,host.state.get_instance_id() if host.state!=null else 0,host.state.day if host.state!=null else -1,host.history_session,host.historical_view]
	if key==refresh_key: return
	refresh_key=key
	host.history_control.editable=ready and count>0
	previous.disabled=not ready or index<=0
	next.disabled=not ready or index>=count
	current.disabled=not ready or not host.history_session
	if host.history_session:
		date.text="%s · %s"%[Calendar.date(host.history.snapshot_day(index)),"历史回看" if host.historical_view else "等待当日结算"]
		date.add_theme_color_override("font_color",Style.ACCENT)
	else:
		date.text="现在" if ready else "准备地图…"
		date.add_theme_color_override("font_color",Style.MUTED)
	live_date.text="现在 · "+Calendar.date(host.state.day) if ready else "每30天记录"
