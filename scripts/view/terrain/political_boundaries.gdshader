shader_type spatial;
render_mode unshaded, cull_disabled, blend_mul, depth_draw_never;


void fragment() {
	// Vertex colors are neutral greys. Multiplication darkens the already
	// composited political/terrain layer like a paint-app multiply line layer.
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
