shader_type canvas_item;
render_mode unshaded;
uniform sampler2D older:filter_linear;
uniform sampler2D newer:filter_linear;
uniform float blend=0.;
void fragment(){
 vec4 a=texture(older,UV),b=texture(newer,UV);
 float alpha=mix(a.a,b.a,blend);
 vec3 premultiplied=mix(a.rgb*a.a,b.rgb*b.a,blend);
 COLOR=vec4(alpha>1e-6?premultiplied/alpha:vec3(0.),alpha);
}
