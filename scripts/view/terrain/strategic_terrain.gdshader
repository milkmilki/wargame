shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D province_texture : source_color, filter_nearest;
uniform sampler2D political_line_texture : source_color, filter_nearest;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 height_source_origin = vec2(0.0);
uniform vec2 height_source_size = vec2(1.0);
uniform float province_strength : hint_range(0.0, 1.0) = 0.0;
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
	ivec2 line_size = textureSize(political_line_texture, 0);
	ivec2 line_pixel = clamp(
		ivec2(floor(UV * vec2(line_size))),
		ivec2(0), line_size - ivec2(1)
	);
	vec4 political_line = texelFetch(
		political_line_texture, line_pixel, 0
	);
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
	// Fill and border ink use the same categorical pixel canvas in every mode.
	final_color = mix(
		final_color, political_line.rgb, political_line.a * hard_land
	);
	// Coast ink is the modeled 0m *crossing*, not every flat vertex at 0m.
	// Screen derivatives provide a one-pixel contour only where elevation
	// actually changes across the fragment; broad 0m plains stay untouched.
	float elevation_width = fwidth(terrain_elevation);
	float contour_distance = abs(
		terrain_elevation - ocean_height_threshold
	) / max(elevation_width, 0.000001);
	float coast_band = (
		1.0 - smoothstep(0.25, 1.15, contour_distance)
	) * step(0.00001, elevation_width);
	ALBEDO = mix(
		final_color, vec3(0.075, 0.085, 0.088), coast_band
	);
	ROUGHNESS = 1.0;
}
