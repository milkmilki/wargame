extends RefCounted
## Adapted from civ-atlas 103afd3 lineageInfo.ts (AGPL-3.0-only).
## Iterative contour compaction; parent aligns to latest reigning descendant.
const STEP := Vector2(80,224)
const BOX := Vector2(60,164)
const GENERATION_GAP := 56.0
const NAME_X := 36.0

static func name_box(member: Dictionary) -> Rect2:
	var name_text := str(member.get("tree_name",member.get("name","？")))
	return Rect2(Vector2(NAME_X-15,40),Vector2(30,name_text.length()*24+12))

static func title_steps(member: Dictionary) -> Array:
	return member.get("title_steps",[{"title":member.get("display_title","无爵"),"label":""}])

static func title_top(member: Dictionary) -> float:
	return name_box(member).end.y+16.0

static func step_height(step: Dictionary) -> float:
	return maxf(str(step.get("title","")).length()*18.0,str(step.get("label","")).length()*13.0)+28.0

static func note_top(member: Dictionary) -> float:
	var height := title_top(member)
	var steps := title_steps(member)
	for step in steps: height += step_height(step)
	# The last title needs no transition arrow; leave space before the note.
	return height-12.0 if not steps.is_empty() else height

static func node_size(member: Dictionary) -> Vector2:
	var height := note_top(member)
	if member.get("history_partial",false): height += 48.0
	return Vector2(BOX.x,maxf(BOX.y,height+8.0))
static func build(model: Dictionary) -> Dictionary:
	var members: Dictionary = model.members
	var ids: Array = members.keys(); ids.sort()
	var kids := {}; var parents := {}; var roots: Array = []
	for id in ids: kids[id]=[]
	# Break malformed cycles deterministically; absent ancestors become roots.
	for id in ids:
		var p := int(members[id].get("parent_id",-1)); var seen := {id:true}; var cursor := p
		while members.has(cursor) and not seen.has(cursor):
			seen[cursor]=true; cursor=int(members[cursor].get("parent_id",-1))
		if not members.has(p) or seen.has(cursor): p=-1
		parents[id]=p
		if p<0: roots.append(id)
		else: kids[p].append(id)
	for id in ids:
		kids[id].sort_custom(func(a,b): return int(members[a].get("birth_order",0))<int(members[b].get("birth_order",0)) if members[a].get("birth_order",0)!=members[b].get("birth_order",0) else a<b)
	var order: Array = []; var stack: Array = roots.duplicate()
	while not stack.is_empty():
		var id: int=stack.pop_back(); order.append(id); stack.append_array(kids[id])
	var contours := {}; var offsets := {}; var last := {}
	order.reverse()
	for id in order:
		var children: Array=kids[id]; var left: Array=[]; var right: Array=[]; var shifts: Array=[]
		var best := int(members[id].get("last_reign",-1)); var main := 0
		for i in range(children.size()):
			var child: int=children[i]; var c: Dictionary=contours[child]; var shift := 0.0
			for depth in range(mini(right.size(),c.left.size())): shift=maxf(shift,float(right[depth])-float(c.left[depth])+1.)
			shifts.append(shift)
			for depth in range(c.left.size()):
				if depth>=left.size(): left.append(float(c.left[depth])+shift); right.append(float(c.right[depth])+shift)
				else: left[depth]=minf(left[depth],float(c.left[depth])+shift); right[depth]=maxf(right[depth],float(c.right[depth])+shift)
			if i>0 and int(last[child])>int(last[children[main]]): main=i
			best=maxi(best,int(last[child]))
		var mid: float=shifts[main] if not shifts.is_empty() else 0.
		var lc: Array=[0.]; var rc: Array=[0.]
		for d in range(left.size()): lc.append(left[d]-mid); rc.append(right[d]-mid)
		contours[id]={"left":lc,"right":rc}; last[id]=best
		for i in range(children.size()): offsets[children[i]]=shifts[i]-mid
	# The tallest trajectory in each generation determines the next row's top.
	var depths := {}; var heights: Array[float] = []
	stack = roots.duplicate()
	while not stack.is_empty():
		var id: int = stack.pop_back()
		var depth: int = int(depths.get(parents[id],-1))+1
		depths[id] = depth
		if heights.size() <= depth: heights.append(0.0)
		heights[depth] = maxf(heights[depth],node_size(members[id]).y)
		stack.append_array(kids[id])
	var row_tops: Array[float] = [0.0]
	for height in heights: row_tops.append(row_tops.back()+height+GENERATION_GAP)
	var positions := {}; var rects := {}; var bounds := Rect2(); var initial := true; var cursor := 0.; var distant := {}
	roots.sort_custom(func(a,b): return a==model.root if a==model.root or b==model.root else a<b)
	for root in roots:
		var contour: Dictionary=contours[root]; var min_x := 0.; var max_x := 0.
		for x in contour.left: min_x=minf(min_x,x)
		for x in contour.right: max_x=maxf(max_x,x)
		stack=[[root,cursor-min_x,0]]
		while not stack.is_empty():
			var entry: Array=stack.pop_back(); var id: int=entry[0]
			var point := Vector2(float(entry[1])*STEP.x,row_tops[int(entry[2])])
			positions[id]=point; distant[id]=root!=model.root
			var rect := Rect2(point,node_size(members[id])); rects[id] = rect
			bounds=rect if initial else bounds.merge(rect); initial=false
			for child in kids[id]: stack.append([child,float(entry[1])+float(offsets[child]),int(entry[2])+1])
		cursor+=max_x-min_x+2.
	return {"positions":positions,"rects":rects,"parents":parents,"children":kids,"bounds":bounds,"distant":distant}
