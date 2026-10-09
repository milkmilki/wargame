extends RefCounted
## Original hand-drawn house, tower and castle paths. AGPL-3.0-only.
const CASTLE = [[-4.4,2.6],[-4.4,-3.4],[-3.8,-3.4],[-3.8,-4.2],[-3.2,-4.2],[-3.2,-3.4],[-2.6,-3.4],[-2.6,-4.2],[-2.,-4.2],[-2.,-1.],[-1.3,-1.],[-1.3,-4.6],[-.65,-4.6],[-.65,-5.3],[0.,-5.3],[0.,-4.6],[.65,-4.6],[.65,-5.3],[1.3,-5.3],[1.3,-1.],[2.,-1.],[2.,-4.2],[2.6,-4.2],[2.6,-3.4],[3.2,-3.4],[3.2,-4.2],[3.8,-4.2],[3.8,-3.4],[4.4,-3.4],[4.4,2.6]]
static func polygon(flat: Array,c: Vector2,u: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in flat: points.append(c+Vector2(p[0],p[1])*u)
	points.append(points[0]); return points
static func house(c: Vector2,u: float) -> PackedVector2Array:
	return polygon([[-1.9,-.4],[0.,-2.3],[1.9,-.4],[1.5,-.4],[1.5,1.7],[-1.5,1.7],[-1.5,-.4]],c,u)
static func tower(c: Vector2,u: float) -> PackedVector2Array:
	return polygon([[-.9,1.8],[-.9,-2.4],[0.,-4.2],[.9,-2.4],[.9,1.8]],c,u)
static func shape(canvas: Node2D,p: PackedVector2Array,width: float) -> void:
	canvas.draw_colored_polygon(p,Color8(246,238,216,247)); canvas.draw_polyline(p,Color8(52,34,22,242),width,true)
static func draw(canvas: Node2D,c: Vector2,s: float,kind: int,color: Color) -> void:
	var ink := Color8(52,34,22,242)
	canvas.draw_circle(c+Vector2(0,.2*s),[1.5,2.6,3.7,4.5,5.6][kind]*s,Color8(244,234,210,158))
	match kind:
		0: canvas.draw_circle(c,.95*s,ink)
		1: shape(canvas,house(c+Vector2(0,.3*s),.95*s),.62*s)
		2:
			shape(canvas,house(c+Vector2(0,-.3*s),.9*s),.62*s)
			for dx in [-1.9,1.9]: shape(canvas,house(c+Vector2(dx,.9)*s,.78*s),.62*s)
		3:
			shape(canvas,tower(c+Vector2(0,.2*s),.95*s),.62*s)
			shape(canvas,house(c+Vector2(-1.6,.2)*s,.72*s),.62*s); shape(canvas,house(c+Vector2(1.7,.4)*s,.72*s),.62*s)
			for dx in [-2.6,2.6]: shape(canvas,house(c+Vector2(dx,1.4)*s,.78*s),.62*s)
		4:
			var u := s*1.05; shape(canvas,polygon(CASTLE,c,u),.62*s)
			var door := PackedVector2Array([c+Vector2(-.8,2.6)*u,c+Vector2(-.8,1.2)*u])
			for i in range(17): door.append(c+Vector2(cos(PI+i*PI/16)*.8,1.2+sin(PI+i*PI/16)*.8)*u)
			door.append(c+Vector2(.8,2.6)*u); canvas.draw_colored_polygon(door,ink)
			canvas.draw_line(c+Vector2(.33,-5.3)*u,c+Vector2(.33,-8.2)*u,ink,.5*s,true)
			var flag := polygon([[.33,-8.2],[2.9,-7.5],[.33,-6.7]],c,u)
			canvas.draw_colored_polygon(flag,Color(color.r*.85,color.g*.85,color.b*.85)); canvas.draw_polyline(flag,ink,.4*s,true)
