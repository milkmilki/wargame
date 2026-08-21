shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D province_texture : source_color, filter_nearest;
uniform sampler2D province_boundary_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D coast_boundary_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D diplomatic_boundary_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 height_source_origin = vec2(0.0);
uniform vec2 height_source_size = vec2(1.0);
uniform float province_strength : hint_range(0.0, 1.0) = 0.0;
uniform float province_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform float coast_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform float diplomatic_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform float ocean_height_threshold = 0.0;
uniform float sea_floor_height = -2.2;
uniform vec3 political_land_base_color : source_color = vec3(0.82, 0.82, 0.80);
uniform vec3 unclaimed_political_color : source_color = vec3(0.035, 0.090, 0.190);
uniform vec3 shallow_sea_color : source_color = vec3(0.090, 0.310, 0.470);
uniform vec3 deep_sea_color : source_color = vec3(0.025, 0.060, 0.130);

varying float terrain_elevation;


void vertex() {
	terrain_elevation = VERTEX.y;
}

void fragment() {
	vec2 source_uv = height_source_origin + UV * height_source_size;
	vec4 province_boundary = texture(province_boundary_texture, UV);
	vec4 coast_boundary = texture(coast_boundary_texture, UV);
	vec4 diplomatic_boundary = texture(diplomatic_boundary_texture, UV);
	float hard_land = step(ocean_height_threshold, terrain_elevation);
	vec3 final_color;
	if (province_strength <= 0.000001) {
		// Terrain mode is the only mode that samples satellite RGB.
		final_color = texture(surface_texture, source_uv).rgb;
	} else {
		ivec2 province_size = textureSize(province_texture, 0);
		ivec2 province_pixel = clamp(
			ivec2(floor(UV * vec2(province_size))),
			ivec2(0), province_size - ivec2(1)
		);
		vec4 province = texelFetch(province_texture, province_pixel, 0);
		// Geometry is the sole geography truth: strictly below the 0m contour is
		// unowned ocean; the 0m contour and everything above it are land.
		float province_alpha = step(0.5, province.a) * hard_land;
		float sea_depth = clamp(
			(ocean_height_threshold - terrain_elevation)
			/ max(ocean_height_threshold - sea_floor_height, 0.001),
			0.0, 1.0
		);
		float deep_sea_mix = smoothstep(0.06, 0.375, sea_depth);
		vec3 sea_political_color = mix(
			shallow_sea_color, deep_sea_color, deep_sea_mix
		);
		vec3 white_low_poly_base = political_land_base_color;
		vec3 political_land = mix(
			unclaimed_political_color, province.rgb, province_alpha
		);
		vec3 political_target = mix(
			sea_political_color, political_land, hard_land
		);
		final_color = mix(
			white_low_poly_base, political_target, province_strength
		);
	}
	// EU4-style hierarchy: soft local province ink fades at overview, while
	// coastline and diplomatic borders remain readable. Diplomatic coverage is
	// applied last so a national border never becomes a doubled province line.
	float province_ink = (
		province_boundary.a * province_boundary_strength * hard_land
		* (1.0 - smoothstep(0.01, 0.18, diplomatic_boundary.a))
	);
	float coast_ink = coast_boundary.a * coast_boundary_strength;
	// Ink is multiplicative: it can only darken the underlying paper/terrain,
	// never turn a red or blue province edge into a light gray lit ribbon.
	final_color *= 1.0 - province_ink * 0.76;
	final_color *= 1.0 - coast_ink * 0.76;
	float diplomatic_ink = (
		diplomatic_boundary.a * diplomatic_boundary_strength * hard_land
	);
	// Diplomatic RGB remains semantic (neutral/allied/enemy/suzerainty), but
	// like real ink it tints and darkens the underlying map instead of replacing
	// lit terrain with a bright flat ribbon. This preserves the red/blue cue
	// without recreating the former gray fringe at the coverage feather.
	vec3 diplomatic_tint = mix(
		vec3(0.14),
		clamp(diplomatic_boundary.rgb * 1.45, vec3(0.10), vec3(0.62)),
		0.42
	);
	final_color = mix(
		final_color, final_color * diplomatic_tint, diplomatic_ink
	);
	ALBEDO = final_color;
	ROUGHNESS = 1.0;
}
