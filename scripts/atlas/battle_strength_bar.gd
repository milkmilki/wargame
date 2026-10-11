extends RefCounted
## Presentation only: field participants and separate city defense reserves,
## never maintenance capacity or a claim that guards join a city field round.
const FONT = preload("res://assets/atlas/lxgw-wenkai-gb-500.ttf")
const WIDTH := 210.
const HEIGHT := 14.
const COLORS = [Color("984843"),Color("c35e56"),Color("6654b5")]

static func summary(battle: Battle) -> Dictionary:
	# Pure blockade/assault has an empty side_b between rounds. Its guard Army
	# is temporary; false side_b_defends_city does not mean the city is empty.
	var defending := battle.kind==Battle.Kind.SIEGE and (battle.side_b_defends_city or not battle.uses_field_combat_rules())
	var first: Array[Army]=battle.side_b if defending else battle.side_a
	var second: Array[Army]=battle.side_a if defending else battle.side_b
	var counts: Array[int]=[0,0,0]
	var has_virtual_guard:=false
	for army in first:
		if army.is_city_garrison:has_virtual_guard=true
		counts[0 if army.is_city_garrison else 1]+=maxi(0,army.size)
	if defending and battle.city!=null and not has_virtual_guard:
		counts[0]=maxi(0,battle.city.garrison_manpower)
	for army in second: counts[2]+=maxi(0,army.size)
	var total: int=counts[0]+counts[1]+counts[2]
	var fractions: Array[float]=[0.,0.,0.]
	if total>0:
		for i in range(3): fractions[i]=float(counts[i])/total
	return {"counts":counts,"fractions":fractions,"total":total,
		"labels":["守军","守方","攻方"] if defending else ["守军","甲方","乙方"]}

static func draw(canvas: Node2D,point: Vector2,pen: float,row: Dictionary) -> void:
	if row.total<=0: return
	var start:=point+Vector2(-WIDTH*.5,-32.)*pen
	var bar:=Rect2(start,Vector2(WIDTH,HEIGHT)*pen)
	canvas.draw_rect(bar.grow(2.*pen),Color8(52,34,22,245))
	var x:=start.x
	var text: PackedStringArray=[]
	for i in range(3):
		var width: float=WIDTH*row.fractions[i]*pen
		if row.counts[i]>0:
			canvas.draw_rect(Rect2(Vector2(x,start.y),Vector2(width,HEIGHT*pen)),COLORS[i])
			text.append("%s %d"%[row.labels[i],row.counts[i]])
		x+=width
	# Labels are outside the segments so a tiny garrison retains its true width.
	# Drawing under inverse zoom keeps the entire bar and text readable on screen.
	canvas.draw_set_transform(point,0.,Vector2.ONE*pen)
	var label: String="  ·  ".join(text)
	var px:=11
	var text_width:=FONT.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	canvas.draw_string_outline(FONT,Vector2(-text_width*.5,-38.),label,HORIZONTAL_ALIGNMENT_LEFT,-1,px,3,Color8(246,238,216,245))
	canvas.draw_string(FONT,Vector2(-text_width*.5,-38.),label,HORIZONTAL_ALIGNMENT_LEFT,-1,px,Color8(52,34,22))
