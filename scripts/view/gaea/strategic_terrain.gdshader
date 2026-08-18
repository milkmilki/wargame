shader_type spatial;
render_mode cull_back, unshaded;

uniform sampler2D province_texture : source_color, filter_linear;
uniform float height_scale = 7.0;
uniform float province_strength : hint_range(0.0, 1.0) = 0.48;
uniform vec3 lowland_color : source_color = vec3(0.23, 0.34, 0.19);
uniform vec3 upland_color : source_color = vec3(0.43, 0.43, 0.27);
uniform vec3 mountain_color : source_color = vec3(0.61, 0.58, 0.49);
uniform vec3 summit_color : source_color = vec3(0.86, 0.85, 0.78);

varying float normalized_height;


void vertex() {
	normalized_height = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.0);
}


void fragment() {
	float lower_mix = smoothstep(0.10, 0.48, normalized_height);
	float upper_mix = smoothstep(0.48, 0.82, normalized_height);
	float summit_mix = smoothstep(0.82, 1.0, normalized_height);
	vec3 terrain = mix(lowland_color, upland_color, lower_mix);
	terrain = mix(terrain, mountain_color, upper_mix);
	terrain = mix(terrain, summit_color, summit_mix);

	float slope = 1.0 - clamp(NORMAL.y, 0.0, 1.0);
	vec3 light_direction = normalize(vec3(-0.42, 0.82, -0.38));
	float directional_light = 0.74 + 0.26 * max(dot(NORMAL, light_direction), 0.0);
	terrain *= directional_light;
	terrain *= mix(1.08, 0.84, smoothstep(0.08, 0.72, slope));

	vec4 province = texture(province_texture, UV);
	float province_mix = province.a * province_strength;
	ALBEDO = mix(terrain, province.rgb, province_mix);
}
