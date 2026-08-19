shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;


void fragment() {
	// Diplomatic border colors are literal opaque inks, not multiply tints.
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
