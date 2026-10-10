shader_type canvas_item;
render_mode unshaded;
uniform float view_zoom=1.;
uniform float stroke_width=1.;
uniform float width_exponent=-.22;
uniform vec4 stroke_color:source_color=vec4(.2,.1,.05,1.);
uniform float dash_length=0.;
uniform float gap_length=0.;
uniform bool vary_pen=false;
uniform float scale_origin=1.35;
uniform float path_scale_exponent=0.;
uniform bool ripple=false;
uniform sampler2D fade_fields:filter_linear,repeat_enable;
varying vec2 point;
varying vec4 ends;
varying vec4 adjacent;
varying float arc_start;
float pen_scale(){return width_exponent<-.5?pow(max(view_zoom,.01),width_exponent):pow(max(1.,view_zoom/scale_origin),width_exponent);}
float hash_value(ivec2 p){uint h=uint(p.x)*374761393u+uint(p.y)*668265263u+23u*982451653u;h=(h^(h>>13u))*1274126177u;h^=h>>16u;return float(h)/4294967296.;}
float noise_value(vec2 p){ivec2 k=ivec2(floor(p));vec2 f=smoothstep(vec2(0.),vec2(1.),fract(p));return mix(mix(hash_value(k),hash_value(k+ivec2(1,0)),f.x),mix(hash_value(k+ivec2(0,1)),hash_value(k+ivec2(1,1)),f.x),f.y);}
void vertex(){
 ends=CUSTOM0; adjacent=CUSTOM1;arc_start=UV.x;
 if(path_scale_exponent!=0.){vec2 original=ends.zw;ends.zw=ends.xy+(ends.zw-ends.xy)*pow(max(1.,view_zoom),path_scale_exponent);if(distance(adjacent.zw,original)<1e-5)adjacent.zw=ends.zw;}
 vec2 d=normalize(ends.zw-ends.xy),n=vec2(-d.y,d.x);
 float radius=stroke_width*pen_scale()*.5+.8/max(.01,view_zoom);
 int corner=int(UV.y+.1);
 VERTEX=(corner<2?ends.xy:ends.zw)+d*(corner<2?-radius:radius)+n*(corner%2==0?-radius:radius);
 point=VERTEX;
}
float segment_distance(vec2 p,vec2 a,vec2 b){vec2 d=b-a;float q=dot(d,d);return length(p-a-d*clamp(dot(p-a,d)/max(q,1e-12),0.,1.));}
void fragment(){
 vec2 a=ends.xy,b=ends.zw,delta=b-a;float length_value=length(delta);vec2 direction=delta/max(length_value,1e-12);
 float d=segment_distance(point,a,b);
 // Canonical ownership of the overlapping round joins. Equal distances belong
 // to the earlier segment; closed paths use the same geometric tie rule.
 if(length(adjacent.xy-a)>1e-5 && segment_distance(point,adjacent.xy,a)<d-1e-5)discard;
 if(length(adjacent.zw-b)>1e-5 && segment_distance(point,b,adjacent.zw)<=d+1e-5)discard;
 float scale=pen_scale(),radius=stroke_width*scale*.5;
 float along=dot(point-a,direction),arc=arc_start+clamp(along,0.,length_value);
 if(vary_pen){float noise=noise_value((a+direction*(floor(arc/max(.001,(dash_length+gap_length)*scale))*(dash_length+gap_length)*scale-arc_start))/7.);int tier=min(2,int(floor(noise*noise*4.8)));radius*=tier==0?1.45/2.75:tier==1?2.05/2.75:1.;}
 float distance_value=d-radius;
 if(dash_length>0.){
  float dash=dash_length*scale,gap=gap_length*scale;
  float phase=mod(arc,max(.0001,dash+gap));
  float outside=phase>dash?min(phase-dash,dash+gap-phase):0.;
  distance_value=sqrt(d*d+outside*outside)-radius;
 }
 float aa=max(.35/max(view_zoom,.01),fwidth(distance_value)*.65);
 float alpha=1.-smoothstep(-aa*.5,aa*.5,distance_value);
 if(ripple)alpha*=texture(fade_fields,point/vec2(2048.,1024.)).r;
 COLOR=vec4(stroke_color.rgb,stroke_color.a*alpha);
}
