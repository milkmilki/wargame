extends RefCounted
## Read-only selection against the exact labels/curves currently on screen.
const Curves = preload("res://scripts/atlas/zoom_geometry.gd")
static func empty() -> Dictionary:
	return {"kind":"","id":-1,"district_id":-1,"owner_id":-1}
static func territory(view,point: Vector2) -> Dictionary:
	var result := empty()
	if point.y<0 or point.y>=1024 or view.province_labels.size()!=2048*1024: return result
	var x := floori(fposmod(point.x,2048.)); var y := floori(point.y); var k := y*2048+x
	var district: int=view.province_labels[k]
	if view.zoom>1.35 and not view.province_index.is_empty():
		var hit := Curves.nearest(view.province_index,fposmod(point.x,2048.),point.y)
		if hit.side!=Curves.KEEP: district=hit.side
	var source: GameState=view.information_source()
	if source==null or district<0 or district>=source.cities.size(): return result
	var owner: int=source.cities[district].owner_nation
	if view.mode_control.selected==0:
		owner=view.political_labels[k]
		if view.zoom>1.35 and not view.political_index.is_empty():
			var hit := Curves.nearest(view.political_index,fposmod(point.x,2048.),point.y)
			if hit.side!=Curves.KEEP: owner=hit.side
		if owner<0: return result
		if source.cities[district].owner_nation!=owner:
			var distance := INF; district=-1
			for dy in range(-8,9):
				if y+dy<0 or y+dy>=1024: continue
				for dx in range(-8,9):
					var r: int=view.province_labels[(y+dy)*2048+posmod(x+dx,2048)]
					if r<0 or r>=source.cities.size() or source.cities[r].owner_nation!=owner: continue
					var d := float(dx*dx+dy*dy)
					if d<distance: distance=d; district=r
	if owner<0 or owner>=source.nations.size() or not source.nations[owner].alive: return result
	result.kind="city" if view.mode_control.selected==2 and district>=0 else "nation"
	result.id=district if result.kind=="city" else owner
	result.district_id=district; result.owner_id=owner
	return result
