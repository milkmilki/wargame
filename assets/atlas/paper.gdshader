shader_type canvas_item;
// Port of civ-atlas fantasy.ts paintPixels, initial base layer. AGPL-3.0-only.
// Ice detail, glyph skirts and zoomed coast vectors are separate port checkpoints.
uniform sampler2D paint_fields : filter_linear, repeat_enable;
uniform sampler2D world_fields : filter_linear, repeat_enable;
uniform sampler2D distances : filter_linear, repeat_enable;
uniform sampler2D detail_fields : filter_linear, repeat_enable;
uniform float view_zoom=1.;
uniform float glyph_scale=1.;
uniform sampler2D segment_grid : filter_nearest;
uniform sampler2D segment_list : filter_nearest;
uniform sampler2D segments0 : filter_nearest;
uniform sampler2D segments1 : filter_nearest;
uniform sampler2D segments2 : filter_nearest;
uniform vec4 segment_params=vec4(-4.,-4.,4.,4.);
const vec3 PAPER = vec3(239.,226.,194.)/255.;
const vec3 PAPER_EDGE = vec3(201.,174.,124.)/255.;
const vec3 SEA = vec3(143.,171.,176.)/255.;
const vec3 SHELF = vec3(168.,194.,189.)/255.;
const vec3 DEEP = vec3(111.,143.,153.)/255.;
const vec3 INK = vec3(58.,45.,34.)/255.;
vec4 flat_sample(sampler2D tex,int i) {
	ivec2 size=textureSize(tex,0);return texture(tex,(vec2(float(i%size.x),float(i/size.x))+.5)/vec2(size));
}
vec2 ice_surface(vec2 p,vec2 size) {
	float B=texture(detail_fields,(floor(p)+.5)/size).r;
	ivec2 c=ivec2(floor((p-segment_params.xy)/segment_params.z)),gs=textureSize(segment_grid,0);
	if(c.x<0||c.y<0||c.x>=gs.x||c.y>=gs.y)return vec2(B,0.);
	vec2 span=texture(segment_grid,(vec2(c)+.5)/vec2(gs)).rg;
	float best=16.,side=0.;int hit=-1;
	for(int q=int(span.x);q<int(span.y);q++) {
		int i=int(flat_sample(segment_list,q).r);vec4 s=flat_sample(segments0,i),n=flat_sample(segments1,i),m=flat_sample(segments2,i);
		vec2 r=p-s.xy,v;float t=dot(r,s.zw)*m.a,sd;
		if(t<=0.){v=r;sd=dot(r,n.xy);}else if(t>=1.){v=r-s.zw;sd=dot(v,n.zw);}else{v=r-s.zw*t;sd=s.z*r.y-s.w*r.x;}
		float d=dot(v,v);if(d>best)continue;best=d;side=sd;hit=i;
	}
	if(hit<0)return vec2(B,0.);
	float d=sqrt(best),cover=clamp(.5+(side<0.?d:-d)*view_zoom,0.,1.);
	return vec2(cover,clamp((.75*glyph_scale-d)*view_zoom+.5,0.,1.));
}
float hash2(ivec2 p,uint s) {
	uint h=uint(p.x)*374761393u+uint(p.y)*668265263u+s*982451653u;
	h=(h^(h>>13u))*1274126177u; h=h^(h>>16u); return float(h)/4294967296.;
}
float noise_p(vec2 p,uint seed,int period) {
	ivec2 i=ivec2(floor(p)); vec2 f=fract(p); vec2 u=f*f*(3.-2.*f);
	int x0=((i.x%period)+period)%period; int x1=(x0+1)%period;
	float a=hash2(ivec2(x0,i.y),seed),b=hash2(ivec2(x1,i.y),seed);
	float c=hash2(ivec2(x0,i.y+1),seed),d=hash2(ivec2(x1,i.y+1),seed);
	return a+(b-a)*u.x+(c-a)*u.y+(a-b-c+d)*u.x*u.y;
}
void fragment() {
	vec2 size=vec2(textureSize(world_fields,0)); vec2 pixel=floor(UV*size); vec2 uv=view_zoom>1.35?vec2(UV.x,clamp(UV.y,.5/size.y,1.-.5/size.y)):(pixel+.5)/size;
	vec4 f=texture(world_fields,uv),paint=texture(paint_fields,uv),detail=texture(detail_fields,uv); vec2 dist=texture(distances,uv).rg;
	if(view_zoom>1.35) {
		vec4 nearest=texture(world_fields,(pixel+.5)/size);
		if(dist.x<=2. && dist.y<=2.)f.g=f.r>0.?0.:1.;else f.g=nearest.g;
		pixel=UV*size;
	}
	int n90=int(floor(size.x/90.+.5)),n23=int(floor(size.x/23.+.5)),n14=int(floor(size.x/14.+.5));
	float mott=.6*noise_p(vec2(pixel.x*float(n90)/size.x,pixel.y/90.),1u,n90)+.4*noise_p(vec2(pixel.x*float(n23)/size.x,pixel.y/23.),2u,n23);
	vec3 paper=mix(PAPER,PAPER_EDGE,.18*(mott-.5)); vec3 color=paper;
	if(f.g>.5 && f.g<1.5) {
		float dm=-f.r; float dep=dm<200.?max(dm,0.)/200.*.15:.15+.55*smoothstep(200.,3800.,dm)+.3*smoothstep(3800.,5600.,dm);
		vec3 sea=dep<.7?mix(SHELF,SEA,dep/.7):mix(SEA,DEEP,(dep-.7)/.3);
		color=mix(paper,sea,.52+.16*dep);
		float conc=max(0.,(detail.g*255.-1.)/254.);
		float open=1.-smoothstep(.02,.3,conc);
		color=mix(color,paper,.28*smoothstep(.05,.9,conc));
		float B=detail.r;
		vec2 ice_detail=vec2(0.);
		if(view_zoom>1.35){ice_detail=ice_surface(pixel,size);B=ice_detail.r;}
		if(view_zoom<=1.35 && detail.g>0. && pixel.y>0. && pixel.y<size.y-1.) {
			bool crossing=texture(detail_fields,uv+vec2(1.,0.)/size).r!=B || texture(detail_fields,uv-vec2(1.,0.)/size).r!=B || texture(detail_fields,uv+vec2(0.,1.)/size).r!=B || texture(detail_fields,uv-vec2(0.,1.)/size).r!=B;
			if(crossing) {
				float sum=0.,cnt=0.;
				for(int dy=-1;dy<=1;dy++) for(int dx=-1;dx<=1;dx++) {
					vec2 q=uv+vec2(float(dx),float(dy))/size;
					if(texture(world_fields,q).g==1.) {sum+=texture(detail_fields,q).r;cnt++;}
				}
				B=sum/max(cnt,1.);
			}
		}
		float hatch=dist.x<9. && int(pixel.y)%3==0?.16*(1.-dist.x/9.)*open:0.;
		float ripple=max(max(exp(-pow((dist.x-4.)/.55,2.))*.42,exp(-pow((dist.x-9.)/.55,2.))*.30),exp(-pow((dist.x-15.)/.55,2.))*.18);
		color=mix(mix(color,INK,hatch),INK,(view_zoom>1.35?0.:ripple)*open);
		if(B>0.) {
			float ice=view_zoom>1.35?B:clamp((B-.5)*1.5+.5,0.,1.);
			vec3 ic=mix(paper,vec3(238.,241.,236.)/255.,.7);
			vec2 q=uv+vec2(3.,3.)/size;
			float back=view_zoom>1.35?ice_surface(pixel+vec2(3.,3.),size).r:texture(detail_fields,q).r;
			float rim=pixel.y+3.<size.y && texture(world_fields,q).g==1.?max(0.,ice-back):0.;
			float hd=abs(mod(pixel.x+pixel.y+2.,4.)-2.)/sqrt(2.);
			float hatch_ice=clamp((.3*glyph_scale-hd)*view_zoom+.5,0.,1.);
			float a=rim*(view_zoom>1.35?.42*hatch_ice:(int(pixel.x+pixel.y)%4==0?.52:.12));
			ic=mix(ic,vec3(140.,158.,168.)/255.,a);color=mix(color,ic,ice);
			float e=4.*B*(1.-B);
			if(view_zoom<=1.35 && e>.3) color=mix(color,vec3(68.,82.,90.)/255.,.62*smoothstep(.3,.95,e)*(.4+.6*smoothstep(.1,.6,conc)));
		}
		if(view_zoom>1.35)color=mix(color,vec3(68.,82.,90.)/255.,.62*ice_detail.g*(.4+.6*smoothstep(.1,.6,conc)));
	} else if(f.g>=1.5) color=mix(paper,SEA,.55);
	else {
		float wash=.66+.22*(noise_p(vec2(pixel.x*float(n14)/size.x,pixel.y/14.),9u,n14)-.5);
		color=mix(paper,paint.rgb,wash);
		if(dist.y<5.) color*=mix(vec3(1.),vec3(.8,.78,.7),.5*(1.-dist.y/5.));
		float relief=.22*mix(.3,1.,smoothstep(150.,1200.,f.r));
		float snow=1.-smoothstep(-10.5,-7.5,f.b),s=mix(paint.a,detail.b,snow),cm=detail.a*snow;
		relief*=(1.-.75*snow-.25*cm)*(s>1.?1.-.6*snow:1.);
		if(s<1.) color=mix(color,vec3(174.,187.,195.)/255.,snow*(1.-cm)*min(.3,(1.-s)*.9));
		if(cm>0.) color=mix(color,vec3(236.,224.,193.)/255.,.9*cm);
		color*=1.+(s-1.)*relief;
	}
	if(view_zoom<=1.35 && dist.x<=2. && dist.y<=2.) {
		float gx=(texture(world_fields,uv+vec2(1.,0.)/size).r-texture(world_fields,uv-vec2(1.,0.)/size).r)/2.;
		float gy=(texture(world_fields,vec2(uv.x,min(1.-.5/size.y,uv.y+1./size.y))).r-texture(world_fields,vec2(uv.x,max(.5/size.y,uv.y-1./size.y))).r)/2.;
		float sd=abs(f.r/max(length(vec2(gx,gy)),.0001));
		float a=view_zoom>1.35?clamp((.725*glyph_scale-sd)*view_zoom+.5,0.,1.):clamp((1.15-sd)/.8,0.,1.);
		color=mix(color,INK,.95*a);
	}
	COLOR=vec4(color*(1.+.035*(hash2(ivec2(pixel),5u)-.5)),1.);
}
