shader_type canvas_item;
// Clip crown strokes/fills to the same native canopy union. AGPL-3.0-only.
uniform sampler2D canopy_mask : filter_linear,repeat_enable;
varying vec2 world_pos;
uniform vec2 view_origin=vec2(0.);
uniform float view_scale=1.;
void vertex(){world_pos=VERTEX;}
void fragment(){
	vec4 c=COLOR; float a=texture(canopy_mask,(world_pos*view_scale+view_origin)/vec2(textureSize(canopy_mask,0))).a;
	COLOR=vec4(c.rgb,c.a*a);
}
