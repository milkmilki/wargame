shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D height_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 height_source_origin = vec2(0.0);
uniform vec2 height_source_size = vec2(1.0);
uniform vec3 deep_color : source_color = vec3(0.025, 0.13, 0.20);
uniform vec3 shallow_color : source_color = vec3(0.13, 0.43, 0.49);
uniform vec3 wave_color : source_color = vec3(0.38, 0.67, 0.68);
uniform vec3 paper_color : source_color = vec3(0.42, 0.37, 0.27);


float hash(vec2 point) {
	return fract(sin(dot(point, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	vec2 centered = UV - vec2(0.5);
	vec2 source_uv = height_source_origin + UV * height_source_size;
	vec2 texel = 1.0 / vec2(textureSize(height_texture, 0));
	float center_land = texture(height_texture, source_uv).a;
	float near_land = center_land;
	for (int ring = 1; ring <= 4; ring++) {
		vec2 radius = texel * float(ring * 5);
		near_land = max(near_land, texture(height_texture, source_uv + vec2(radius.x, 0.0)).a);
		near_land = max(near_land, texture(height_texture, source_uv - vec2(radius.x, 0.0)).a);
		near_land = max(near_land, texture(height_texture, source_uv + vec2(0.0, radius.y)).a);
		near_land = max(near_land, texture(height_texture, source_uv - vec2(0.0, radius.y)).a);
	}
	float coast = smoothstep(0.06, 0.82, near_land) * (1.0 - smoothstep(0.18, 0.72, center_land));
	float broad = sin(UV.x * 47.0 + UV.y * 13.0);
	float cross_wave = sin(UV.y * 61.0 - UV.x * 11.0);
	float wave = broad * 0.55 + cross_wave * 0.45;
	float fine_a = sin(UV.x * 230.0 + UV.y * 37.0);
	float fine_b = sin(UV.y * 187.0 - UV.x * 29.0);
	float grain = hash(floor(UV * vec2(950.0, 620.0))) - 0.5;
	float edge_light = smoothstep(0.72, 0.12, length(centered));
	vec3 water = mix(deep_color, shallow_color, coast * 0.82 + edge_light * 0.08);
	float wave_crest = (
		pow(max(fine_a, 0.0), 14.0) * 0.032
		+ pow(max(fine_b, 0.0), 16.0) * 0.018
		+ coast * 0.16
	);
	water = mix(water, wave_color, wave_crest);
	water *= 1.0 + wave * 0.024 + grain * 0.018;
	water = mix(water, water * paper_color * 1.55, 0.055);
	ALBEDO = water;
	ROUGHNESS = 0.92;
}
