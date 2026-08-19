shader_type canvas_item;
render_mode unshaded;

uniform vec3 warm_tint : source_color = vec3(0.60, 0.53, 0.41);
uniform vec3 edge_tint : source_color = vec3(0.12, 0.09, 0.055);
uniform float warm_alpha : hint_range(0.0, 0.2) = 0.045;
uniform float vignette_strength : hint_range(0.0, 0.3) = 0.10;
uniform float grain_strength : hint_range(0.0, 0.08) = 0.018;


float hash(vec2 point) {
	return fract(sin(dot(point, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(1.0, 0.72);
	float vignette = smoothstep(0.32, 0.69, length(centered));
	float grain = hash(floor(FRAGCOORD.xy * 0.72)) - 0.5;
	float dark_grain = max(-grain, 0.0) * grain_strength;
	float light_grain = max(grain, 0.0) * grain_strength * 0.55;
	vec3 color = mix(warm_tint, edge_tint, vignette * 0.78 + dark_grain);
	color = mix(color, vec3(0.92, 0.86, 0.72), light_grain);
	float alpha = warm_alpha + vignette * vignette_strength + abs(grain) * grain_strength;
	COLOR = vec4(color, alpha);
}
