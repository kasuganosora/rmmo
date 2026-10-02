shader_type sky;
render_mode use_half_res_pass;
uniform vec3 zenith : source_color = vec3(.25, .48, .72);
uniform vec3 horizon : source_color = vec3(.64, .74, .82);
uniform vec3 cloud_tint : source_color = vec3(.9, .92, .94);
uniform vec3 sun_tint : source_color = vec3(1., .91, .75);
uniform vec3 sun_direction = vec3(.3, .7, .2);
uniform vec3 moon_direction = vec3(-.3, .7, -.2);
uniform float cloud_cover = .18;
uniform float daylight = 1.;
uniform float night_amount = 0.;
uniform float dusk_amount = 0.;
uniform float star_intensity = 1.;
#include "res://scripts/world3d/star_field.gdshaderinc"
uniform vec3 meteor_heads[8];
uniform vec3 meteor_tails[8];
uniform float meteor_energies[8];
uniform float meteor_kinds[8];
uniform float meteor_brightness[8];
uniform vec2 drift = vec2(0.);
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * .1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f*f*(3.-2.*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1)), f.x), f.y);
}
float fbm(vec2 p) {
	float n = 0., a = .55;
	for (int i=0; i<5; i++) { n += noise(p)*a; p = mat2(vec2(.8,.6),vec2(-.6,.8))*p*2.03; a *= .48; }
	return n;
}
#include "res://scripts/world3d/cloud_volume.gdshaderinc"
void sky() {
	if (AT_HALF_RES_PASS) {
		vec4 volume = cloud_quality>=0 && !AT_CUBEMAP_PASS ? march_clouds(POSITION,EYEDIR,false) : vec4(0.);
		COLOR = volume.rgb; ALPHA = volume.a;
	} else {
	float height = max(EYEDIR.y, 0.);
	vec3 base = mix(horizon, zenith, pow(height, .55));
	float sun = max(dot(EYEDIR, normalize(sun_direction)), 0.);
	float sunset_glow = pow(sun,6.) * exp(-height*3.) * dusk_amount;
	base += vec3(.28,.095,.025)*sunset_glow;
	base += sun_tint * (pow(sun, 80.)*.14 + smoothstep(.9995,.99985,sun)*1.8) * daylight * (1.-night_amount);
	// Celestial details stay fixed in world directions; only cloud coordinates drift.
	float horizon_fade = smoothstep(.02,.22,height);
	if (night_amount > 0. && EYEDIR.y > 0.) {
		vec3 dx = dFdx(EYEDIR), dy = dFdy(EYEDIR);
		float pixel_variance = (dot(dx,dx)+dot(dy,dy))/24.;
		// Unresolved point sources alias in the tiny diffuse reflection cubemap.
		vec3 field = star_galaxy_glow(EYEDIR);
		if (!AT_CUBEMAP_PASS) field += star_radiance(EYEDIR,pixel_variance);
		base += field*star_intensity*horizon_fade;
		// Keep short streaks out of the slowly updated reflection cubemap.
		if (!AT_CUBEMAP_PASS) {
			for (int i=0;i<8;i++) {
				float energy = meteor_energies[i]*meteor_brightness[i];
				if (energy <= .001) continue;
				float fire = meteor_kinds[i];
				vec3 segment = meteor_heads[i]-meteor_tails[i];
				float along = clamp(dot(EYEDIR-meteor_tails[i],segment)/max(dot(segment,segment),.000001),0.,1.);
				float distance = length(EYEDIR-normalize(meteor_tails[i]+segment*along));
				float width = mix(1.,2.3,fire);
				float trail = (1.-smoothstep(.00045*width,.0018*width,distance))*pow(along,1.8);
				float glow = (1.-smoothstep(.001,.006*width,distance))*pow(along,3.)*mix(.22,.6,fire);
				float head_glow = (1.-smoothstep(.001,.014,length(EYEDIR-meteor_heads[i])))*fire;
				vec3 tint = mix(vec3(.65,.8,1.),vec3(1.,.42,.12),fire);
				base += (tint*(trail+glow)+vec3(1.,.83,.53)*head_glow)*energy*3.*horizon_fade;
			}
		}
	}
	float moon = smoothstep(.99952,.9997,max(dot(EYEDIR,normalize(moon_direction)),0.));
	base += vec3(.48,.61,.86) * moon * night_amount;
	vec4 thin = thin_clouds(POSITION,EYEDIR);
	base = base*(1.-thin.a)+thin.rgb;
	vec4 volume;
	if (cloud_quality>=0) {
		volume = AT_CUBEMAP_PASS ? march_clouds(POSITION,EYEDIR,true) : HALF_RES_COLOR;
	} else {
		// Cheap layer fallback also uses world coordinates and the server seed.
		float t = max(0.,(cloud_altitude-POSITION.y)/max(.03,EYEDIR.y));
		vec2 uv = (POSITION.xz+EYEDIR.xz*t-drift/.0006)/cloud_scale*2.+cloud_seed_offset.xz*7.;
		vec2 warp = vec2(fbm(uv*.6),fbm(uv*.6+vec2(17.1,9.2)));
		float n = fbm(uv+warp*1.6);
		float opacity = smoothstep(.71-cloud_cover*.54,.91-cloud_cover*.4,n)*smoothstep(0.,.13,height)*.94;
		vec3 shade = cloud_tint*mix(.63,1.,smoothstep(.15,.9,fbm(uv*.72+warp)));
		shade = mix(shade,vec3(.78,.40,.24),dusk_amount*(.25+.4*pow(sun,3.)));
		volume = vec4(shade*opacity,opacity);
	}
	COLOR = base*(1.-volume.a)+volume.rgb;
	COLOR = mix(horizon*.72, COLOR, smoothstep(-.2, .015, EYEDIR.y));
	}
}
