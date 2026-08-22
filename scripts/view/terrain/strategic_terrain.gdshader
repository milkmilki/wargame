shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D province_texture : source_color, filter_nearest;
uniform sampler2D province_boundary_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Raw linear-premultiplied RGB + coverage alpha; do not add source_color.
uniform sampler2D country_boundary_texture : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D country_color_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 height_source_origin = vec2(0.0);
uniform vec2 height_source_size = vec2(1.0);
uniform float province_strength : hint_range(0.0, 1.0) = 0.93;
uniform float province_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform float coast_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform float country_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 local_boundary_color : source_color = vec3(0.30, 0.045, 0.035);
uniform float local_boundary_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float local_boundary_core_radius_px = 0.5;
uniform float local_boundary_outer_radius_px = 1.0;
uniform float country_boundary_core_width_px = 3.0;
uniform float country_boundary_outer_width_px = 3.5;
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
	vec4 country_boundary = texture(country_boundary_texture, UV);
	vec4 coast_country = texture(country_color_texture, UV);
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
	// The 1px province line is the base. Country bands are applied last, so a
	// national border is exactly the two adjacent 3px national-color strokes.
	float province_ink = clamp(
		province_boundary.a * province_boundary_strength * hard_land
		* local_boundary_alpha, 0.0, 1.0
	);
	// Coast and political fill use the same interpolated 0m contour. Signed
	// distance plus hard_land keeps the full 3px country stroke on land only.
	// The derivative gate prevents broad, quantized 0m land plateaus from being
	// mistaken for coastline.
	float coast_gradient = fwidth(terrain_elevation);
	float coast_mesh_band = step(0.001, UV2.x);
	float coast_distance_px = max(
		terrain_elevation - ocean_height_threshold, 0.0
	) / max(coast_gradient, 0.000001);
	float coast_coverage = (
		1.0 - smoothstep(
			country_boundary_core_width_px,
			country_boundary_outer_width_px,
			coast_distance_px
		)
	) * hard_land * step(0.000001, coast_gradient) * coast_mesh_band;
	float coast_ink = clamp(
		coast_coverage * coast_boundary_strength * coast_country.a, 0.0, 1.0
	);
	float country_ink = clamp(
		country_boundary.a * country_boundary_strength * hard_land,
		0.0, 1.0
	);
	// Province coverage uses fixed ink. Country RGB is linearly premultiplied
	// before upload and unpremultiplied here; coast color comes from the nearest
	// owner field. Filtering therefore cannot reveal transparent white/black RGB.
	province_ink = clamp(province_ink, 0.0, 1.0);
	coast_ink = clamp(coast_ink, 0.0, 1.0);
	country_ink = clamp(country_ink, 0.0, 1.0);
	vec3 country_ink_color = (
		country_boundary.rgb / max(country_boundary.a, 0.00001)
	);
	final_color = mix(final_color, local_boundary_color, province_ink);
	final_color = mix(final_color, coast_country.rgb, coast_ink);
	final_color = mix(final_color, country_ink_color, country_ink);
	ALBEDO = final_color;
	ROUGHNESS = 1.0;
}
