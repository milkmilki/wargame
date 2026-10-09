shader_type canvas_item;
// Native mask compositing of fantasy.ts clipped canopy shade/hatching. AGPL-3.0-only.
uniform float shade_distance=2.;
uniform float glyph_scale=1.;
uniform float view_scale=1.;
uniform vec2 view_origin=vec2(0.);
const vec3 INK=vec3(58.,45.,34.)/255.;
vec3 canopy(int k) {
	if(k==0) return vec3(150.,165.,108.)/255.;
	if(k==1) return vec3(118.,145.,90.)/255.;
	return vec3(118.,140.,104.)/255.;
}
void fragment() {
	vec4 c=texture(TEXTURE,UV); vec2 size=vec2(textureSize(TEXTURE,0));
	int kind=0;float best=100.;
	for(int k=0;k<3;k++) {float d=distance(c.rgb,canopy(k));if(d<best){kind=k;best=d;}}
	if(c.a>.99 && best<.01) {
		vec2 q=UV+vec2(shade_distance)/size;
		vec4 north=texture(TEXTURE,q);
		float exposed=1.-clamp(1.-distance(north.rgb,canopy(kind))/.012,0.,1.)*north.a;
		vec3 shaded=mix(c.rgb,INK,.10);
		float gap=2048.*view_scale/max(1.,floor(2048./(1.7*glyph_scale)+.5));
		vec2 p=UV*size-view_origin;
		float d=abs(fract((p.x+p.y)/gap+.5)-.5)*gap;
		float hatch_width=.55*glyph_scale*view_scale;
		float hatch=1.-smoothstep(hatch_width*.5-.3,hatch_width*.5+.3,d);
		shaded=mix(shaded,INK,.42*hatch);
		c.rgb=mix(c.rgb,shaded,exposed);
	}
	COLOR=c;
}
