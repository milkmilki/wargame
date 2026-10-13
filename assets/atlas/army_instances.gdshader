shader_type canvas_item;
render_mode unshaded;
uniform float view_zoom=1.;
void vertex() { VERTEX /= max(.1,view_zoom); }
void fragment() {
	float radius=length((UV-.5)*12.);
	float coverage=1.-smoothstep(5.15,5.5,radius);
	vec3 color=mix(COLOR.rgb,vec3(.13,.07,.04),smoothstep(3.55,3.8,radius));
	COLOR=vec4(color,COLOR.a*coverage);
}
