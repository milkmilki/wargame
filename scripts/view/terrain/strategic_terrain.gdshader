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


void vertex() {
	normalized_height = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.0);
}


void fragment() {
	vec2 source_uv = height_source_origin + UV * height_source_size;
	vec3 satellite_surface = texture(surface_texture, source_uv).rgb;
	vec4 province = texture(province_texture, UV);
	float province_mix = province.a * province_strength;
	vec3 final_color = mix(
		satellite_surface,
		province.rgb,
		province_mix
	);
	ALBEDO = final_color;
	ROUGHNESS = 0.94;
}
