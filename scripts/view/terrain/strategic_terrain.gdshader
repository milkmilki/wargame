shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D province_id_texture : filter_nearest, repeat_disable;
uniform sampler2D province_visual_lut : source_color, filter_nearest, repeat_disable;
uniform sampler2D visual_city_id_texture : filter_nearest, repeat_disable;
uniform sampler2D visual_land_mask_texture : filter_nearest, repeat_disable;
uniform sampler2D visual_region_edge_texture : filter_linear, repeat_disable;
uniform sampler2D visual_coast_mask_texture : filter_linear, repeat_disable;
uniform sampler2D province_boundary_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D country_boundary_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D country_color_texture : source_color, filter_linear, repeat_disable;
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
uniform float country_gradient_strength : hint_range(0.0, 1.0) = 0.45;
uniform float country_gradient_radius_px = 10.0;
uniform float unified_region_fill_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float ocean_height_threshold = 0.0;
uniform float sea_floor_height = -2.2;
uniform vec3 political_land_base_color : source_color = vec3(0.82, 0.82, 0.80);
uniform vec3 shallow_sea_color : source_color = vec3(0.090, 0.310, 0.470);
uniform vec3 deep_sea_color : source_color = vec3(0.025, 0.060, 0.130);

varying float terrain_elevation;


vec4 visual_base_color_at(
	ivec2 pixel, ivec2 atlas_size, ivec2 lut_size
) {
	ivec2 safe_pixel = clamp(pixel, ivec2(0), atlas_size - ivec2(1));
	int city_id = int(floor(texelFetch(
		visual_city_id_texture, safe_pixel, 0
	).r + 0.5));
	if (city_id < 0 || city_id >= lut_size.x) {
		return vec4(0.0);
	}
	return texelFetch(province_visual_lut, ivec2(city_id, 0), 0);
}


float visual_country_gradient(
	vec4 center, ivec2 pixel, ivec2 atlas_size, ivec2 lut_size
) {
	float radius = max(country_gradient_radius_px, 1.0);
	float weight = 0.0;
	for (int offset = 1; offset <= 10; offset++) {
		if (float(offset) > radius) {
			continue;
		}
		float falloff = 1.0 - (float(offset) - 1.0) / radius;
		ivec2 delta_x = ivec2(offset, 0);
		ivec2 delta_y = ivec2(0, offset);
		vec4 neighbors[4] = {
			visual_base_color_at(pixel - delta_x, atlas_size, lut_size),
			visual_base_color_at(pixel + delta_x, atlas_size, lut_size),
			visual_base_color_at(pixel - delta_y, atlas_size, lut_size),
			visual_base_color_at(pixel + delta_y, atlas_size, lut_size)
		};
		for (int neighbor_index = 0; neighbor_index < 4; neighbor_index++) {
			float different_country = step(
				0.001, distance(center.rgb, neighbors[neighbor_index].rgb)
			) * step(0.5, neighbors[neighbor_index].a);
			weight = max(weight, different_country * falloff);
		}
	}
	return weight;
}


void vertex() {
	terrain_elevation = VERTEX.y;
}

void fragment() {
	vec4 province_boundary = texture(province_boundary_texture, UV);
	vec4 country_boundary = texture(country_boundary_texture, UV);
	vec4 coast_country = texture(country_color_texture, UV);
	vec4 gradient = coast_country;
	float terrain_land = step(ocean_height_threshold, terrain_elevation);
	float atlas_land = step(0.5, texture(visual_land_mask_texture, UV).r);
	float hard_land = mix(
		terrain_land,
		terrain_land * atlas_land,
		unified_region_fill_enabled
	);
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
		ivec2 visual_size = textureSize(visual_city_id_texture, 0);
		ivec2 visual_pixel = clamp(
			ivec2(floor(UV * vec2(visual_size))),
			ivec2(0), visual_size - ivec2(1)
		);
		if (unified_region_fill_enabled > 0.5) {
			province_id = int(floor(texelFetch(
				visual_city_id_texture, visual_pixel, 0
			).r + 0.5));
		}
		ivec2 lut_size = textureSize(province_visual_lut, 0);
		vec4 province = vec4(0.0);
		vec4 occupation = vec4(0.0);
		gradient = vec4(0.0);
		if (province_id >= 0 && province_id < lut_size.x) {
			province = texelFetch(
				province_visual_lut, ivec2(province_id, 0), 0
			);
			occupation = texelFetch(
				province_visual_lut, ivec2(province_id, 1), 0
			);
			if (lut_size.y > 2) {
				gradient = texelFetch(
					province_visual_lut, ivec2(province_id, 2), 0
				);
			}
		}
		// Geometry is the sole geography truth: strictly below the 0m contour is
		// unowned ocean; the 0m contour and everything above it are land.
		float province_alpha = step(0.5, province.a) * hard_land;
		float visual_country_edge = 0.0;
		if (
			unified_region_fill_enabled > 0.5
			&& country_fill_fade_enabled > 0.5
		) {
			float visual_edge_hint = texture(
				visual_region_edge_texture, UV
			).r;
			visual_country_edge = visual_country_gradient(
				province, visual_pixel, visual_size, lut_size
			);
			visual_country_edge *= mix(0.75, 1.0, visual_edge_hint);
		}
		float country_gradient_weight = mix(
			coast_country.a,
			visual_country_edge,
			unified_region_fill_enabled
		) * country_fill_fade_enabled;
		// Country colour is an ink layer: start from the selected political
		// land base and fade the country's boundary colour toward that base as
		// the sample moves into the interior. The final land surface stays opaque.
		// province.rgb is the owning nation's base colour. The country texture
		// carries the enhanced boundary colour and only its alpha is used as the
		// inward gradient weight, so every nation fades to its own colour.
		vec3 boundary_color = mix(
			coast_country.rgb, gradient.rgb, unified_region_fill_enabled
		);
		vec3 gradient_country_color = mix(
			province.rgb, boundary_color, country_gradient_weight
		);
		vec3 faded_country_color = mix(
			province.rgb, gradient_country_color, country_gradient_strength
		);
		bool occupation_stripe = encoded_province.b > 0.5;
		if (unified_region_fill_enabled > 0.5) {
			occupation_stripe = ((visual_pixel.x + visual_pixel.y) % 9) < 3;
		}
		if (occupation_stripe && occupation.a > 0.5) {
			faded_country_color = occupation.rgb;
		}
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
	float atlas_region_edge = texture(visual_region_edge_texture, UV).r;
	float visual_province_alpha = mix(
		province_boundary.a, atlas_region_edge, unified_region_fill_enabled
	);
	float province_alpha = visual_province_alpha * province_boundary_strength
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
	float atlas_coast = texture(visual_coast_mask_texture, UV).r;
	float coast_gate = mix(
		coast_country.a, atlas_coast, unified_region_fill_enabled
	);
	float coast_ink = clamp(
		coast_coverage * coast_boundary_strength * coast_gate, 0.0, 1.0
	);
	vec3 coast_color = mix(
		coast_country.rgb, gradient.rgb, unified_region_fill_enabled
	);
	final_color = mix(final_color, local_boundary_color, province_ink);
	final_color = mix(final_color, coast_color, coast_ink);
	final_color = mix(final_color, country_boundary.rgb, country_ink);
	ALBEDO = final_color;
	ROUGHNESS = 1.0;
}
