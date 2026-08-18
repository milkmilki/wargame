shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 deep_color : source_color = vec3(0.055, 0.16, 0.17);
uniform vec3 shallow_color : source_color = vec3(0.12, 0.29, 0.30);
uniform vec3 paper_color : source_color = vec3(0.42, 0.37, 0.27);


float hash(vec2 point) {
	return fract(sin(dot(point, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	vec2 centered = UV - vec2(0.5);
	float broad = sin(UV.x * 44.0 + sin(UV.y * 17.0) * 1.5);
	float cross_wave = sin(UV.y * 71.0 - UV.x * 13.0);
	float wave = broad * 0.5 + cross_wave * 0.5;
	float grain = hash(floor(UV * vec2(950.0, 620.0))) - 0.5;
	float edge_light = smoothstep(0.68, 0.18, length(centered));
	vec3 water = mix(deep_color, shallow_color, edge_light * 0.32);
	water *= 1.0 + wave * 0.022 + grain * 0.030;
	water = mix(water, water * paper_color * 1.65, 0.08);
	ALBEDO = water;
	ROUGHNESS = 0.92;
}
