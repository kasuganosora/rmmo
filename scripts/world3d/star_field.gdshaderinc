// Version 2: deterministic equal-area, density-weighted procedural stars.
// Research and approximation limits: docs/world3d_starfield.md.
uniform int star_seed = 0;
uniform float star_time = 0.;
const float STAR_GRID = 128.;
const float STAR_SIGMA = .00050;

float star_hash(ivec2 cell, uint salt) {
	uint h = uint(cell.x)*0x8da6b343u ^ uint(cell.y)*0xd8163841u ^ uint(star_seed) ^ salt;
	h = (h ^ (h >> 16u))*0x7feb352du;
	h = (h ^ (h >> 15u))*0x846ca68bu;
	h = h ^ (h >> 16u);
	return float(h & 0x00ffffffu)/16777216.;
}

float star_noise(vec2 p) {
	ivec2 cell = ivec2(floor(p)); vec2 f = fract(p); f = f*f*(3.-2.*f);
	return mix(mix(star_hash(cell,311u),star_hash(cell+ivec2(1,0),311u),f.x),
		mix(star_hash(cell+ivec2(0,1),311u),star_hash(cell+ivec2(1),311u),f.x),f.y);
}

// Scaled Lambert azimuthal equal-area: disk radius 1 covers 2 PI steradians.
// dOmega = 2 du dv, unlike the previous stereographic sampling density.
vec2 star_project(vec3 direction) { return direction.xz/sqrt(1.+max(direction.y,0.)); }
vec3 star_unproject(vec2 p) {
	float r2 = dot(p,p);
	return vec3(p.x*sqrt(max(0.,2.-r2)),1.-r2,p.y*sqrt(max(0.,2.-r2)));
}

// Disk + bulge + patchy foreground dust, shared by resolved stars and faint glow.
// Authored statistical approximation, not a fit to Gaia or a real star catalogue.
vec3 star_galaxy(vec3 direction) {
	float latitude = dot(direction,normalize(vec3(.18,.45,.875)));
	float disk = exp(-pow(latitude/.14,2.));
	float bulge = exp(-(1.-dot(direction,normalize(vec3(-.32,.83,-.36))))/.075);
	vec2 p = direction.xz*9.+direction.y*vec2(5.7,-4.2);
	float patch = .65*star_noise(p)+.35*star_noise(p*2.1+17.);
	float lane = latitude+.022*sin(dot(direction,vec3(11.,3.,-5.)));
	float dust = exp(-pow(lane/.043,2.))*smoothstep(.28,.73,patch)*.85;
	return vec3(disk,bulge,dust);
}

float star_density(vec3 direction) {
	vec3 galaxy = star_galaxy(direction);
	return .028 + (.105*galaxy.x*(.55+.45*galaxy.y)+.035*galaxy.y)*(1.-galaxy.z);
}

// XY = subcell position, Z = apparent magnitude, W = colour index. Z < 0 is empty.
vec4 star_candidate(ivec2 cell) {
	float selection = star_hash(cell,0u);
	if (selection >= .168) return vec4(0.,0.,-1.,0.);
	vec2 point = vec2(star_hash(cell,13u),star_hash(cell,71u));
	vec2 p = (vec2(cell)+point)/STAR_GRID;
	if (dot(p,p) >= 1.) return vec4(0.,0.,-1.,0.);
	vec3 direction = star_unproject(p);
	if (selection >= star_density(direction)) return vec4(0.,0.,-1.,0.);
	// Inverse CDF N(m) ~ 10^(0.32m), authored over m=0.3..6.8; many faint stars.
	float magnitude = log(mix(pow(10.,.32*.3),pow(10.,.32*6.8),star_hash(cell,19u)))/log(10.)/.32;
	return vec4(point,magnitude,star_hash(cell,41u));
}

float star_flux(float magnitude) { return pow(10.,-.4*magnitude); }

float star_psf(float distance2, float pixel_variance) {
	// Gaussian footprint sigma ~= .55 pixels prevents subpixel energy pulsing.
	float variance = STAR_SIGMA*STAR_SIGMA + 3.6*pixel_variance;
	return exp(-.5*distance2/variance)*(STAR_SIGMA*STAR_SIGMA/variance);
}

vec3 star_radiance(vec3 direction, float pixel_variance) {
	vec2 uv = star_project(direction)*STAR_GRID;
	ivec2 cell = ivec2(floor(uv));
	vec3 result = vec3(0.);
	// Equal-area map has minimum angular scale 1 radian per disk unit at horizon.
	// Expand the support at low resolution; normal views visit only 3 x 3 cells.
	int radius = clamp(int(ceil(3.*sqrt(STAR_SIGMA*STAR_SIGMA+3.6*pixel_variance)*STAR_GRID)),1,4);
	for (int y=-radius;y<=radius;y++) {
		for (int x=-radius;x<=radius;x++) {
			ivec2 key = cell+ivec2(x,y);
			vec4 star = star_candidate(key);
			if (star.z < 0.) continue;
			vec3 position = star_unproject((vec2(key)+star.xy)/STAR_GRID);
			vec3 offset = direction-position;
			float distance2 = dot(offset,offset);
			// Wider pixel footprint, normalized to preserve integrated stellar flux.
			float psf = star_psf(distance2,pixel_variance);
			float phase = star_hash(key,59u);
			float scintillation = .018+.065*pow(1.-position.y,2.);
			float twinkle = 1.+scintillation*sin(star_time*mix(.7,1.8,phase)+phase*137.);
			vec3 tint = mix(vec3(1.,.79,.58),vec3(.70,.83,1.),star.w);
			tint /= dot(tint,vec3(.2126,.7152,.0722));
			float airmass = min(12.,1./max(position.y,.05));
			float extinction = exp(-.12*(airmass-1.));
			result += tint*star_flux(star.z)*65.*psf*twinkle*extinction;
		}
	}
	return result;
}

vec3 star_galaxy_glow(vec3 direction) {
	vec3 galaxy = star_galaxy(direction);
	float detail = .55+.45*star_noise(direction.xz*23.+direction.y*vec2(5.7,-4.2));
	return vec3(.020,.026,.041)*(galaxy.x*.45+galaxy.y*.8)*(1.-galaxy.z)*detail;
}
