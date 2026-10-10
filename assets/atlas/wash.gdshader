shader_type canvas_item;
// civ-atlas territory.ts washPixels/SYM_KEEP; AGPL-3.0-only.
uniform sampler2D edge_field : filter_linear;
uniform sampler2D symbols : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(2048.,1024.);
uniform vec2 symbol_origin=vec2(0.);
uniform float symbol_scale=1.;
uniform float view_zoom=1.;
uniform sampler2D segment_grid : filter_nearest;
uniform sampler2D segment_list : filter_nearest;
uniform sampler2D segments0 : filter_nearest;
uniform sampler2D segments1 : filter_nearest;
uniform sampler2D segments2 : filter_nearest;
uniform sampler2D segment_ends : filter_nearest;
uniform sampler2D palette : filter_nearest;
uniform sampler2D owner_ids : filter_nearest, repeat_enable;
uniform bool use_owner_palette=false;
uniform sampler2D world_fields : filter_linear,repeat_enable;
uniform vec4 segment_params=vec4(-4.,-4.,4.,4.);
vec4 flat_sample(sampler2D tex,int i) {
	ivec2 size=textureSize(tex,0); return texture(tex,(vec2(float(i%size.x),float(i/size.x))+.5)/vec2(size));
}
vec4 territory_color(sampler2D base_texture,vec2 uv) {
	if(!use_owner_palette)return texture(base_texture,uv);
	int owner=int(round(texture(owner_ids,uv).r));
	return owner>=0?flat_sample(palette,owner):vec4(0.);
}
int nearest_side(vec2 p) {
	ivec2 c=ivec2(floor((p-segment_params.xy)/segment_params.z)),size=textureSize(segment_grid,0);
	if(c.x<0 || c.y<0 || c.x>=size.x || c.y>=size.y) return -32768;
	vec2 span=texture(segment_grid,(vec2(c)+.5)/vec2(size)).rg;
	float best=segment_params.w*segment_params.w,side=0.; int hit=-1;
	for(int q=int(span.x);q<int(span.y);q++) {
		int i=int(flat_sample(segment_list,q).r); vec4 s=flat_sample(segments0,i),n=flat_sample(segments1,i),m=flat_sample(segments2,i);
		vec2 r=p-s.xy;float t=dot(r,s.zw)*m.a,sd; vec2 v;
		if(t<=0.){v=r;sd=dot(r,n.xy);} else if(t>=1.){v=r-s.zw;sd=dot(v,n.zw);}else{v=r-s.zw*t;sd=s.z*r.y-s.w*r.x;}
		float d=dot(v,v); if(d>best)continue;best=d;hit=i;side=sd;
	}
	if(hit<0)return -32768;
	vec4 m=flat_sample(segments2,hit);int owner=int(side>0.?m.r:m.g);
	for(int k=0;k<2;k++) {
		vec4 e=flat_sample(segment_ends,int(m.b)*2+k);vec2 v=p-e.xy;
		if(e.x> -1e19 && dot(v,e.zw)>0. && dot(v,v)<=segment_params.w*segment_params.w)return -32768;
	}
	return owner;
}
float land_cover(vec2 p) {
	vec2 corner=floor(p-.5),f=fract(p-.5),texsize=vec2(textureSize(world_fields,0));
	float y0=clamp(corner.y+.5,.5,texsize.y-.5),y1=clamp(corner.y+1.5,.5,texsize.y-.5);
	vec4 a=texture(world_fields,vec2(corner.x+.5,y0)/texsize),b=texture(world_fields,vec2(corner.x+1.5,y0)/texsize),c=texture(world_fields,vec2(corner.x+.5,y1)/texsize),d=texture(world_fields,vec2(corner.x+1.5,y1)/texsize);
	bool lake=a.g==2.||b.g==2.||c.g==2.||d.g==2.;
	float v0=lake?(a.g>0.?-1.:1.):(a.g>0.?min(-.001,a.r):max(0.,a.r));
	float v1=lake?(b.g>0.?-1.:1.):(b.g>0.?min(-.001,b.r):max(0.,b.r));
	float v2=lake?(c.g>0.?-1.:1.):(c.g>0.?min(-.001,c.r):max(0.,c.r));
	float v3=lake?(d.g>0.?-1.:1.):(d.g>0.?min(-.001,d.r):max(0.,d.r));
	float top=mix(v0,v1,f.x),bot=mix(v2,v3,f.x),v=mix(top,bot,f.y);
	float grad=length(vec2(mix(v1-v0,v3-v2,f.y),bot-top))/view_zoom;
	return grad>1e-12?clamp(.5+v/grad,0.,1.):(v>0.?1.:0.);
}
float hash2(ivec2 p,uint s) {
	uint h=uint(p.x)*374761393u+uint(p.y)*668265263u+s*982451653u;
	h=(h^(h>>13u))*1274126177u; h=h^(h>>16u); return float(h)/4294967296.;
}
float tiled_noise(vec2 p,uint seed,int period) {
	ivec2 i=ivec2(floor(p));vec2 f=fract(p),u=f*f*(3.-2.*f);
	ivec2 i0=(i%ivec2(period)+ivec2(period))%ivec2(period),i1=(i0+ivec2(1))%ivec2(period);
	float a=hash2(i0,seed),b=hash2(ivec2(i1.x,i0.y),seed),c=hash2(ivec2(i0.x,i1.y),seed),d=hash2(i1,seed);
	return a+(b-a)*u.x+(c-a)*u.y+(a-b-c+d)*u.x*u.y;
}
void fragment() {
	vec4 color=territory_color(TEXTURE,UV);vec2 pixel=floor(UV*map_size);
	if(view_zoom>1.35) {
		vec2 p=UV*map_size;int owner=nearest_side(p);float cover=land_cover(p);
		if(owner>=0)color=flat_sample(palette,owner);
		else if(owner!=-32768)color=vec4(0.);
		if(color.a==0. && cover>0. && owner==-32768) {
			vec2 uv=(floor(p-.5)+.5)/map_size;
			for(int dy=0;dy<=1;dy++)for(int dx=0;dx<=1;dx++){vec4 candidate=territory_color(TEXTURE,uv+vec2(float(dx),float(dy))/map_size);if(candidate.a>0.)color=candidate;}
		}
		color.a*=cover;pixel=p;
	}
	vec2 edge_size=vec2(textureSize(edge_field,0));
	vec2 p=max(vec2(0.),(pixel+.5)/2.-.5+vec2(34.,0.));
	float d=texture(edge_field,(p+.5)/edge_size).r*2.;
	float ii=min(255.,floor(d*4.));float alpha=.2+.5*exp(-ii/4./12.);
	vec2 g=mod(pixel,128.);float grain=.6*tiled_noise(g/8.,3u,16)+.4*tiled_noise(g/4.,7u,32);
	alpha*=.775+.45*grain;
	vec2 sp=UV*map_size*symbol_scale+symbol_origin;
	sp.x=mod(sp.x,2048.*symbol_scale);
	vec2 su=sp/vec2(textureSize(symbols,0));
	vec4 sym=texture(symbols,su);float lum=dot(sym.rgb,vec3(.3,.59,.11))*255.;
	float ink=clamp((125.-lum)/30.,0.,1.);float weight=mix(.85,.55,clamp((lum-165.)/40.,0.,1.));
	float give=sym.a*(ink+(1.-ink)*weight*(1.-.9*exp(-ii/4./14.)));
	COLOR=vec4(color.rgb,color.a*alpha*(1.-give));
}
