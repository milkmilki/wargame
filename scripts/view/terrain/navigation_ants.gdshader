shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float dash_length = 0.32;
uniform float flow_speed = 0.12;

void fragment() {
	float phase = fract((UV.x - TIME * flow_speed) / (dash_length * 2.0));
	if (phase >= 0.5) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
}
