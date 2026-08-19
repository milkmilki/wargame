shader_type spatial;
render_mode cull_back, unshaded;

uniform sampler2D province_texture : source_color, filter_linear;
uniform sampler2D height_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 height_source_origin = vec2(0.0);
uniform vec2 height_source_size = vec2(1.0);
uniform float height_scale = 7.0;
uniform float land_alpha_threshold : hint_range(0.0, 1.0) = 0.2;
uniform float province_strength : hint_range(0.0, 1.0) = 0.0;
uniform float elevation_shadow_strength : hint_range(0.0, 1.0) = 0.62;
uniform float hillshade_strength : hint_range(0.0, 1.0) = 0.68;
uniform float detail_normal_strength = 240.0;
uniform vec3 lowland_color : source_color = vec3(0.38, 0.43, 0.28);
uniform vec3 upland_color : source_color = vec3(0.52, 0.49, 0.33);
uniform vec3 mountain_color : source_color = vec3(0.59, 0.51, 0.37);
uniform vec3 summit_color : source_color = vec3(0.74, 0.69, 0.59);
uniform vec3 hill_shadow_color : source_color = vec3(0.17, 0.15, 0.13);
uniform vec3 hill_highlight_color : source_color = vec3(0.88, 0.84, 0.75);
uniform vec3 paper_tint : source_color = vec3(0.66, 0.55, 0.39);
uniform vec3 unclaimed_political_color : source_color = vec3(0.035, 0.090, 0.190);
uniform vec3 shallow_sea_color : source_color = vec3(0.090, 0.310, 0.470);
uniform vec3 deep_sea_color : source_color = vec3(0.025, 0.060, 0.130);

varying float normalized_height;


void vertex() {
	normalized_height = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.0);
}


void fragment() {
	vec2 source_uv = height_source_origin + UV * height_source_size;
	vec3 satellite_surface = texture(surface_texture, source_uv).rgb;
	vec4 province = texture(province_texture, UV);
	float center_height = texture(height_texture, source_uv).a;
	float signed_height = (center_height <= land_alpha_threshold)
		? mix(-1.0, 0.0, clamp((center_height * 255.0 - 1.0) / 127.0, 0.0, 1.0))
		: clamp((center_height * 255.0 - 129.0) / 126.0, 0.0, 1.0);
	float hard_land = step(land_alpha_threshold + 0.5 / 255.0, center_height);
	float province_alpha = province.a * hard_land;
	float province_mix = province_alpha * province_strength;
	float sea_depth = max(-signed_height, 0.0);
	// Signed sea depth is normalized to 8000m. Continental shelf stays light;
	// at roughly 3000m (0.375) the color settles into deep navy.
	float deep_sea_mix = smoothstep(0.06, 0.375, sea_depth);
	vec3 sea_political_color = mix(
		shallow_sea_color, deep_sea_color, deep_sea_mix
	);
	vec3 unclaimed_surface = mix(
		sea_political_color, unclaimed_political_color, hard_land
	);
	vec3 political_surface = mix(
		unclaimed_surface, province.rgb, province_alpha
	);
	// Province strength is the opacity of the complete political layer, not
	// only claimed land. At 100%, no satellite RGB survives anywhere.
	vec3 final_color = mix(
		satellite_surface, political_surface, province_strength
	);
	// Height-only multiply layer above political color. Alpha is the packed DEM;
	// neighboring samples produce directional slope shade without leaking any
	// satellite RGB back through a 100% opaque political map.
	vec2 height_texel = 1.0 / vec2(textureSize(height_texture, 0));
	float height_left = texture(height_texture, source_uv - vec2(height_texel.x, 0.0)).a;
	float height_right = texture(height_texture, source_uv + vec2(height_texel.x, 0.0)).a;
	float height_up = texture(height_texture, source_uv - vec2(0.0, height_texel.y)).a;
	float height_down = texture(height_texture, source_uv + vec2(0.0, height_texel.y)).a;
	vec3 elevation_normal = normalize(vec3(
		(height_left - height_right) * detail_normal_strength,
		1.0,
		(height_up - height_down) * detail_normal_strength
	));
	vec3 elevation_light = normalize(vec3(-0.52, 0.76, -0.39));
	float flat_light = elevation_light.y;
	float slope_delta = dot(elevation_normal, elevation_light) - flat_light;
	float height_shadow = clamp(
		0.91 + slope_delta * 0.96 - signed_height * 0.18,
		0.42, 1.0
	);
	float relief_mix = province_strength * elevation_shadow_strength;
	final_color = mix(final_color, final_color * height_shadow, relief_mix);
	float unclaimed_mix = (1.0 - province_alpha) * province_strength;
	final_color = mix(
		final_color,
		max(final_color, unclaimed_surface * 0.78),
		unclaimed_mix
	);
	ALBEDO = final_color;
	ROUGHNESS = 0.94;
}
