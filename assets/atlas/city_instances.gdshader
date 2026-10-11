shader_type canvas_item;
render_mode unshaded;
varying vec3 flag_color;
varying vec4 vertex_color;
uniform float hovered_city = -1.0;
uniform float hover_amount = 0.0;
uniform float previous_city = -1.0;
uniform float previous_amount = 0.0;
void vertex(){
 float weight = 0.0;
 if(abs(INSTANCE_CUSTOM.a-hovered_city)<0.1) weight=hover_amount;
 if(abs(INSTANCE_CUSTOM.a-previous_city)<0.1) weight=max(weight,previous_amount);
 VERTEX*=1.0+0.15*weight;
 flag_color=INSTANCE_CUSTOM.rgb;vertex_color=COLOR;
}
void fragment(){
 vec4 c=vertex_color;
 if(c.r>.99 && c.g<.01 && c.b>.99)c.rgb=flag_color*.85;
 COLOR=c;
}
