shader_type canvas_item;
uniform sampler2D fade_fields : filter_linear, repeat_enable;
varying vec2 atlas_point;
void vertex(){atlas_point=VERTEX;}
void fragment(){COLOR.a*=texture(fade_fields,vec2(fract(atlas_point.x/2048.),clamp(atlas_point.y/1024.,.5/1024.,1.-.5/1024.))).r;}
