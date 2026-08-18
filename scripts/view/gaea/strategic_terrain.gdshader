shader_type spatial;
render_mode cull_back, unshaded;

uniform sampler2D province_texture : source_color, filter_linear;
uniform sampler2D height_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 height_source_origin = vec2(0.0);
uniform vec2 height_source_size = vec2(1.0);
uniform float height_scale = 7.0;
uniform float province_strength : hint_range(0.0, 1.0) = 0.62;
uniform float hillshade_strength : hint_range(0.0, 1.0) = 0.68;
uniform float detail_normal_strength = 240.0;
uniform vec3 lowland_color : source_color = vec3(0.38, 0.43, 0.28);
uniform vec3 upland_color : source_color = vec3(0.52, 0.49, 0.33);
uniform vec3 mountain_color : source_color = vec3(0.59, 0.51, 0.37);
uniform vec3 summit_color : source_color = vec3(0.74, 0.69, 0.59);
uniform vec3 hill_shadow_color : source_color = vec3(0.17, 0.15, 0.13);
uniform vec3 hill_highlight_color : source_color = vec3(0.88, 0.84, 0.75);
uniform vec3 paper_tint : source_color = vec3(0.66, 0.55, 0.39);

varying float normalized_height;


float sampled_altitude(vec2 local_uv) {
	vec2 source_uv = height_source_origin
		+ clamp(local_uv, vec2(0.0), vec2(1.0)) * height_source_size;
	vec3 encoded = texture(height_texture, source_uv).rgb;
	return 1.0 - dot(encoded, vec3(0.299, 0.587, 0.114));
}


float paper_noise(vec2 point) {
	vec2 cell = floor(point);
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}


void vertex() {
	normalized_height = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.0);
}


void fragment() {
	float source_altitude = sampled_altitude(UV);
	float altitude = mix(normalized_height, source_altitude, 0.72);
	float lower_mix = smoothstep(0.08, 0.38, altitude);
	float upper_mix = smoothstep(0.36, 0.72, altitude);
	float summit_mix = smoothstep(0.84, 0.98, altitude);
	vec3 terrain = mix(lowland_color, upland_color, lower_mix);
	terrain = mix(terrain, mountain_color, upper_mix);
	terrain = mix(terrain, summit_color, summit_mix);
	vec2 source_uv = height_source_origin + UV * height_source_size;
	vec3 natural_surface = texture(surface_texture, source_uv).rgb;
	float surface_luma = dot(
		natural_surface,
		vec3(0.299, 0.587, 0.114)
	);
	float surface_chroma = (
		max(max(natural_surface.r, natural_surface.g), natural_surface.b)
		- min(min(natural_surface.r, natural_surface.g), natural_surface.b)
	);
	float coastal_flat_fill = (
		(1.0 - smoothstep(0.035, 0.15, surface_chroma))
		* smoothstep(0.62, 0.84, surface_luma)
		* (1.0 - smoothstep(0.18, 0.38, altitude))
	);
	natural_surface = mix(
		natural_surface,
		terrain,
		coastal_flat_fill
	);
	terrain = mix(terrain, natural_surface, 0.76);

	vec2 texel = 1.0 / vec2(textureSize(height_texture, 0));
	float height_left = 1.0 - texture(
		height_texture,
		source_uv - vec2(texel.x * 2.0, 0.0)
	).r;
	float height_right = 1.0 - texture(
		height_texture,
		source_uv + vec2(texel.x * 2.0, 0.0)
	).r;
	float height_up = 1.0 - texture(
		height_texture,
		source_uv - vec2(0.0, texel.y * 2.0)
	).r;
	float height_down = 1.0 - texture(
		height_texture,
		source_uv + vec2(0.0, texel.y * 2.0)
	).r;
	vec3 detail_normal = normalize(vec3(
		(height_left - height_right) * detail_normal_strength,
		1.0,
		(height_up - height_down) * detail_normal_strength
	));
	vec3 geometry_normal = normalize(NORMAL);
	vec3 terrain_normal = normalize(mix(geometry_normal, detail_normal, 0.82));

	// Reference preset: northwest light (315 degrees), warm shadow and ivory highlight.
	vec3 light_direction = normalize(vec3(-0.58, 0.72, -0.38));
	float illumination = dot(terrain_normal, light_direction);
	float shade = smoothstep(-0.45, 0.75, illumination);
	vec3 hill_color = mix(hill_shadow_color, hill_highlight_color, shade);
	float relief = clamp(length(detail_normal.xz), 0.0, 1.0);
	float hill_mix = hillshade_strength * mix(0.24, 0.62, relief);
	terrain = mix(terrain, terrain * hill_color * 1.55, hill_mix);

	// Fine paper grain keeps broad plains from reading as flat plastic.
	float grain = paper_noise(UV * vec2(1850.0, 1120.0)) - 0.5;
	float broad_grain = paper_noise(UV * vec2(137.0, 89.0)) - 0.5;
	terrain *= 1.0 + grain * 0.045 + broad_grain * 0.035;
	terrain = mix(terrain, terrain * paper_tint * 1.32, 0.08);

	vec4 province = texture(province_texture, UV);
	float province_mix = province.a * province_strength;
	vec3 province_tint = mix(terrain * province.rgb * 1.35, province.rgb, 0.46);
	ALBEDO = mix(terrain, province_tint, province_mix);
	ROUGHNESS = 0.94;
}
