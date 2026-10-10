shader_type canvas_item;
render_mode unshaded;
varying vec3 flag_color;
varying vec4 vertex_color;
void vertex(){flag_color=INSTANCE_CUSTOM.rgb;vertex_color=COLOR;}
void fragment(){
 vec4 c=vertex_color;
 if(c.r>.99 && c.g<.01 && c.b>.99)c.rgb=flag_color*.85;
 COLOR=c;
}
