shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D province_id_texture : filter_nearest, repeat_disable;
uniform sampler2D province_visual_lut : source_color, filter_nearest, repeat_disable;
uniform sampler2D province_boundary_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D country_boundary_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D country_color_texture : source_color, filter_nearest, repeat_disable;
uniform float province_strength : hint_range(0.0, 1.0) = 0.93;
uniform float province_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform float coast_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform float country_boundary_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 local_boundary_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float local_boundary_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float local_boundary_core_radius_px = 0.5;
uniform float local_boundary_outer_radius_px = 0.5;
uniform float country_boundary_core_width_px = 3.0;
uniform float country_boundary_outer_width_px = 3.0;
uniform float country_fill_fade_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float ocean_height_threshold = 0.0;
uniform float sea_floor_height = -2.2;
uniform vec3 political_land_base_color : source_color = vec3(0.82, 0.82, 0.80);
uniform vec3 shallow_sea_color : source_color = vec3(0.090, 0.310, 0.470);
uniform vec3 deep_sea_color : source_color = vec3(0.025, 0.060, 0.130);

varying float terrain_elevation;


void vertex() {
	terrain_elevation = VERTEX.y;
}

void fragment() {
	vec4 province_boundary = texture(province_boundary_texture, UV);
	vec4 country_boundary = texture(country_boundary_texture, UV);
	vec4 coast_country = texture(country_color_texture, UV);
	float hard_land = step(ocean_height_threshold, terrain_elevation);
	float sea_depth = clamp(
		(ocean_height_threshold - terrain_elevation)
		/ max(ocean_height_threshold - sea_floor_height, 0.001),
		0.0, 1.0
	);
	float deep_sea_mix = smoothstep(0.06, 0.375, sea_depth);
	vec3 sea_color = mix(shallow_sea_color, deep_sea_color, deep_sea_mix);
	vec3 white_low_poly_base = political_land_base_color;
	vec3 final_color;
	if (province_strength <= 0.000001) {
		// The terrain option is a white terrain mode; elevation and lighting
		// provide relief without any satellite color texture.
		final_color = mix(sea_color, white_low_poly_base, hard_land);
	} else {
		ivec2 province_size = textureSize(province_id_texture, 0);
		ivec2 province_pixel = clamp(
			ivec2(floor(UV * vec2(province_size))),
			ivec2(0), province_size - ivec2(1)
		);
		vec4 encoded_province = texelFetch(
			province_id_texture, province_pixel, 0
		);
		int province_code = int(floor(encoded_province.r * 255.0 + 0.5))
			| (int(floor(encoded_province.g * 255.0 + 0.5)) << 8);
		int province_id = province_code - 1;
		ivec2 lut_size = textureSize(province_visual_lut, 0);
		vec4 province = vec4(0.0);
		if (province_id >= 0 && province_id < lut_size.x) {
			province = texelFetch(
				province_visual_lut, ivec2(province_id, 0), 0
			);
			vec4 occupation = texelFetch(
				province_visual_lut, ivec2(province_id, 1), 0
			);
			if (encoded_province.b > 0.5 && occupation.a > 0.5) {
				province = occupation;
			}
		}
		// Geometry is the sole geography truth: strictly below the 0m contour is
		// unowned ocean; the 0m contour and everything above it are land.
		float province_alpha = step(0.5, province.a) * hard_land;
		float country_fill_opacity = mix(
			1.0, coast_country.a, country_fill_fade_enabled
		);
		vec3 faded_country_color = mix(
			white_low_poly_base, province.rgb, country_fill_opacity
		);
		vec3 political_land = mix(
			white_low_poly_base, faded_country_color, province_alpha
		);
		vec3 political_target = mix(
			sea_color, political_land, hard_land
		);
		final_color = mix(
			white_low_poly_base, political_target, province_strength
		);
	}
	// Boundary textures are authored as hard solid strokes. Country borders and
	// the mesh-derived 0m coast have independent LOD controls.
	float province_alpha = province_boundary.a * province_boundary_strength
		* hard_land * local_boundary_alpha;
	float country_alpha = country_boundary.a
		* country_boundary_strength
		* hard_land;
	float province_aa = max(fwidth(province_alpha), 0.00001);
	float country_aa = max(fwidth(country_alpha), 0.00001);
	float province_ink = smoothstep(
		0.5 - province_aa, 0.5 + province_aa, province_alpha
	);
	float country_ink = smoothstep(
		0.5 - country_aa, 0.5 + country_aa, country_alpha
	);
	// Coastline follows the exact interpolated terrain 0m crossing. UV2 confines
	// the derivative band to cells that really cross land/sea, so flat lowland
	// cannot be mistaken for coast. Keep it independent from country_strength:
	// the visual gate and map LOD intentionally toggle either layer alone.
	float coast_gradient = fwidth(terrain_elevation);
	// UV2 is interpolated across triangles. Reject tiny interpolation tails so
	// the coastal marker cannot bleed into unrelated inland fragments.
	float coast_mesh_band = step(0.05, UV2.x);
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
	final_color = mix(final_color, local_boundary_color, province_ink);
	final_color = mix(final_color, coast_country.rgb, coast_ink);
	final_color = mix(final_color, country_boundary.rgb, country_ink);
	ALBEDO = final_color;
	ROUGHNESS = 1.0;
}
