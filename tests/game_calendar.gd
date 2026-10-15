extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("CALENDAR_FAIL ",message)
func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/core/game_calendar.gd"):
		check(false,"shared year/day formatter is missing"); quit(1); return
	var calendar = load("res://scripts/core/game_calendar.gd")
	for pair in [[0,"1年1天"],[359,"1年360天"],[360,"2年1天"],[12684,"36年85天"],[-1,"未记录"]]:
		check(calendar.date(pair[0])==pair[1],"absolute date boundary %s"%pair[0])
	for pair in [[0,"0天"],[359,"359天"],[360,"1年0天"],[750,"2年30天"]]:
		check(calendar.duration(pair[0])==pair[1],"elapsed time has no calendar offset %s"%pair[0])
	var event := {"day":12684,"year":36,"text":"36年 晋伐我，反攻并兼并晋"}
	var before := event.duplicate(true)
	check(calendar.event_text(event)=="36年85天 晋伐我，反攻并兼并晋","event display uses the recorded day and preserves the defender perspective")
	check(event==before,"event formatting cannot rewrite stored chronicle data")
	check(calendar.event_text({"text":"旧记录"})=="旧记录","undated legacy text is preserved")
	check(calendar.event_text({"day":360,"text":"继位"})=="2年1天 继位","an unprefixed event receives its occurrence date")
	var member := {"title_history":[{"title":"安王","origin_nation_name":"晋国","origin_nation_id":0,"start_day":359,"end_day":360,"end_reason":"death"}]}
	var title_lines := FamilyTree.title_history_lines(member)
	check(title_lines==["安王 · 来源晋国（国0） · 1年360天授爵 · 2年1天因去世终止"],"title history formats both sides of a year boundary")
	print("GAME_CALENDAR failures=",failures); quit(1 if failures else 0)
