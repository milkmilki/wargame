extends RefCounted
## Presentation only: day zero is the opening date; elapsed durations have no offset.
const DAYS_PER_YEAR := RulerProfile.DAYS_PER_YEAR

static func date(day: int) -> String:
	if day<0: return "未记录"
	return "%d年%d天"%[day/DAYS_PER_YEAR+1,day%DAYS_PER_YEAR+1]

static func duration(days: int) -> String:
	days=maxi(0,days)
	if days<DAYS_PER_YEAR: return "%d天"%days
	return "%d年%d天"%[days/DAYS_PER_YEAR,days%DAYS_PER_YEAR]

static func event_text(event: Dictionary) -> String:
	var text := str(event.get("text",""))
	if int(event.get("day",-1))<0: return text
	# Older chronicles store a year prefix. Keep names and results as recorded.
	var separator := text.find(" ")
	var prefix := text.left(separator) if separator>=0 else ""
	if prefix.ends_with("年") and prefix.trim_suffix("年").is_valid_int():
		text=text.substr(separator+1)
	return "%s %s"%[date(int(event.day)),text]
