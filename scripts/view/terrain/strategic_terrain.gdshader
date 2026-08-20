shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D province_texture : source_color, filter_linear;
uniform sampler2D height_texture : filter_nearest;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 height_source_origin = vec2(0.0);
uniform vec2 height_source_size = vec2(1.0);
uniform float land_alpha_threshold : hint_range(0.0, 1.0) = 0.2;
uniform float province_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 unclaimed_political_color : source_color = vec3(0.035, 0.090, 0.190);
uniform vec3 shallow_sea_color : source_color = vec3(0.090, 0.310, 0.470);
uniform vec3 deep_sea_color : source_color = vec3(0.025, 0.060, 0.130);

void fragment() {
	vec2 source_uv = height_source_origin + UV * height_source_size;
	vec3 satellite_surface = texture(surface_texture, source_uv).rgb;
	vec4 province = texture(province_texture, UV);
	ivec2 height_size = textureSize(height_texture, 0);
	ivec2 height_pixel = clamp(
		ivec2(floor(source_uv * vec2(height_size))),
		ivec2(0), height_size - ivec2(1)
	);
	float center_height = texelFetch(height_texture, height_pixel, 0).a;
	float signed_height = (center_height <= land_alpha_threshold)
		? mix(-1.0, 0.0, clamp((center_height * 255.0 - 1.0) / 127.0, 0.0, 1.0))
		: clamp((center_height * 255.0 - 129.0) / 126.0, 0.0, 1.0);
	float hard_land = step(land_alpha_threshold + 0.5 / 255.0, center_height);
	float province_alpha = province.a * hard_land;
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
	float unclaimed_mix = (1.0 - province_alpha) * province_strength;
	final_color = mix(
		final_color,
		max(final_color, unclaimed_surface * 0.78),
		unclaimed_mix
	);
	ALBEDO = final_color;
	ROUGHNESS = 1.0;
}
