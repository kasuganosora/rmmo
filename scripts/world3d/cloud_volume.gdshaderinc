// Adapted from Godot's MIT sky_shaders demo (density height gradients, noise
// remapping, Beer extinction and HG scattering). See docs/licenses/Godot-clouds-MIT.txt.
// Original cloud method: Schneider/Vos, SIGGRAPH 2015. World/time integration,
// bounded sampling and compositing below are specific to RMMO.
uniform sampler3D cloud_base_noise : filter_linear, repeat_enable;
uniform sampler3D cloud_detail_noise : filter_linear, repeat_enable;
uniform vec3 cloud_seed_offset = vec3(0.);
uniform int cloud_quality = 1;
uniform float cloud_altitude = 1500.;
uniform float cloud_thickness = 450.;
uniform float cloud_scale = 1800.;
uniform float cirrus_amount = .22;
uniform float cloud_storm = 0.;
uniform vec4 cloud_flash = vec4(0.);

float cloud_density_at(vec3 p, bool detail) {
	if (cloud_cover<=.001) return 0.;
	float h = (p.y-cloud_altitude)/cloud_thickness;
	if (h<=0. || h>=1.) return 0.;
	// Positive world wind translates the density field towards positive world axes.
	vec3 q = vec3(p.x-drift.x/.0006,p.y,p.z-drift.y/.0006)/cloud_scale + cloud_seed_offset;
	float weather = textureLod(cloud_base_noise,vec3(q.x*.37,.37,q.z*.37),0.).r;
	// This atlas is biased towards 0.9, so coverage must be calibrated to its
	// distribution rather than interpreted as raw density (which makes a solid lid).
	float regional_threshold = .925-cloud_cover*.20;
	float regional = smoothstep(regional_threshold-.025,regional_threshold+.025,weather);
	float coverage = .08+.25*cloud_cover;
	vec4 n = textureLod(cloud_base_noise,q,0.);
	float cellular = dot(n.gba,vec3(.625,.25,.125));
	float shape = (n.r + 1.-cellular)/(2.-cellular);
	// Flat base, rounded crown; storms fill more of the upper layer.
	float profile = smoothstep(.0,.09,h)*(1.-smoothstep(mix(.48,.72,cloud_storm),1.,h));
	shape = clamp((shape*profile-(1.-coverage))/coverage,0.,1.);
	if (detail && shape>0.) {
		vec3 high = textureLod(cloud_detail_noise,q*6. + vec3(h*.17,0.,0.),0.).rgb;
		float erosion = dot(high,vec3(.625,.25,.125));
		erosion = mix(erosion,1.-erosion,clamp(h*4.,0.,1.))*.18;
		shape = max(0.,(shape-erosion)/(1.-erosion));
	}
	return shape*regional;
}

float cloud_phase(float mu, float g) {
	return .07957747*(1.-g*g)/pow(max(.01,1.+g*g-2.*g*mu),1.5);
}

vec4 march_clouds(vec3 origin, vec3 ray, bool reflection) {
	if (abs(ray.y)<.0001) return vec4(0.);
	float a = (cloud_altitude-origin.y)/ray.y;
	float b = (cloud_altitude+cloud_thickness-origin.y)/ray.y;
	float near_t = max(0.,min(a,b));
	float far_t = min(22000.,max(a,b));
	if (far_t<=near_t) return vec4(0.);
	int steps = reflection ? 12 : (cloud_quality==2 ? 80 : (cloud_quality==1 ? 48 : 20));
	int light_steps = reflection ? 2 : (cloud_quality==2 ? 5 : (cloud_quality==1 ? 3 : 1));
	float step_size = (far_t-near_t)/float(steps);
	float extinction = mix(.009,.017,cloud_storm);
	// Sun and moon can be exactly opposite: interpolating their directions would
	// normalize a zero vector at twilight and make the cloud lighting jump.
	vec3 solar_dir = normalize(sun_direction);
	vec3 lunar_dir = normalize(moon_direction);
	float solar_phase = max(cloud_phase(dot(ray,solar_dir),.55),cloud_phase(dot(ray,solar_dir),-.2));
	float lunar_phase = max(cloud_phase(dot(ray,lunar_dir),.55),cloud_phase(dot(ray,lunar_dir),-.2));
	vec3 ambient = mix(mix(horizon,zenith,.45)*.60,vec3(.0018,.0027,.005),night_amount);
	vec3 radiance = vec3(0.);
	float transmittance = 1.;
	// Deterministic angular dither breaks horizontal slice bands without frame-time
	// noise. No TIME or per-client random state; fixed views remain pixel-stable.
	float offset = mix(.15,.85,hash(ray.xz*8192.));
	for (int i=0;i<80;i++) {
		if (i>=steps || transmittance<.015) break;
		vec3 p = origin+ray*(near_t+(float(i)+offset)*step_size);
		float density = cloud_density_at(p,!reflection);
		if (density<.001) continue;
		float h = clamp((p.y-cloud_altitude)/cloud_thickness,0.,1.);
		float solar_depth = 0.;
		float lunar_depth = 0.;
		float light_stride = cloud_thickness/float(light_steps);
		for (int j=0;j<5;j++) {
			if (j>=light_steps) break;
			float distance_to_light = (float(j)+.5)*light_stride;
			if (night_amount<1.) solar_depth += cloud_density_at(p+solar_dir*distance_to_light,false)*light_stride;
			if (night_amount>0.) lunar_depth += cloud_density_at(p+lunar_dir*distance_to_light,false)*light_stride;
		}
		// Broad multiple-scattering approximation keeps deep clouds readable.
		float solar_scatter = exp(-solar_depth*extinction)+.22*exp(-solar_depth*extinction*.22);
		float lunar_scatter = exp(-lunar_depth*extinction)+.22*exp(-lunar_depth*extinction*.22);
		vec3 lighting = ambient*mix(.50,1.35,h);
		lighting += sun_tint*daylight*(1.-night_amount)*solar_scatter*(.55+solar_phase*2.5);
		lighting += vec3(.006,.008,.012)*night_amount*smoothstep(0.,.25,lunar_dir.y)*lunar_scatter*(.35+lunar_phase*2.5);
		vec2 flash_delta = (p.xz-cloud_flash.xz)/900.;
		lighting += vec3(.65,.78,1.)*cloud_flash.w*4.*exp(-dot(flash_delta,flash_delta)*2.);
		float opacity = 1.-exp(-density*extinction*step_size);
		radiance += transmittance*opacity*lighting;
		transmittance *= 1.-opacity;
	}
	// Atmospheric perspective suppresses long, undersampled horizon paths.
	float distance_fade = (1.-smoothstep(7000.,22000.,near_t))*smoothstep(.025,.18,abs(ray.y));
	float opacity = (1.-transmittance)*distance_fade;
	radiance = mix(radiance,horizon*(1.-transmittance),smoothstep(2500.,18000.,near_t)*.75)*distance_fade;
	return vec4(radiance,opacity);
}

vec4 thin_clouds(vec3 origin, vec3 ray) {
	if (ray.y<=.015 || cirrus_amount<=0.) return vec4(0.);
	float t = (cloud_altitude+cloud_thickness+2500.-origin.y)/ray.y;
	if (t<=0.) return vec4(0.);
	vec2 p = ((origin.xz+ray.xz*t-drift/.0006*.65)/cloud_scale + cloud_seed_offset.xz*7.)*.45;
	vec2 bend = vec2(fbm(p*.35),fbm(p*.35+vec2(21.,4.)))*2.;
	float wisps = fbm(p*vec2(.85,1.8)+bend);
	float patch = smoothstep(.40,.68,fbm(p*.15+vec2(4.,10.)));
	float opacity = smoothstep(.48,.72,wisps)*patch*cirrus_amount*.4*smoothstep(.025,.18,ray.y);
	vec3 tint = mix(mix(vec3(.82,.88,.96),sun_tint,dusk_amount*.7),vec3(.006,.0085,.013),night_amount);
	return vec4(tint*opacity,opacity);
}
