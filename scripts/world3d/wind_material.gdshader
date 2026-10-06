shader_type spatial;
render_mode cull_back;
uniform vec4 tint : source_color = vec4(1.);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 uv_scale = vec3(1.);
uniform vec3 uv_offset = vec3(0.);
uniform bool vertex_color = false;
uniform float roughness = 1.;
uniform float metallic = 0.;
uniform float specular = .5;
uniform vec4 rough_channel = vec4(1.,0.,0.,0.);
uniform vec4 metal_channel = vec4(1.,0.,0.,0.);
uniform vec4 ao_channel = vec4(1.,0.,0.,0.);
uniform bool normal_enabled = false;
uniform float normal_scale = 1.;
uniform bool ao_enabled = false;
uniform float ao_light = 0.;
uniform vec3 emission : source_color = vec3(0.);
uniform float emission_energy = 1.;
uniform bool emission_multiply = false;
uniform bool emission_texture_present = false;
uniform bool backlight_enabled = false;
uniform vec3 backlight : source_color = vec3(0.);
uniform sampler2D backlight_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float alpha_cut = .5;
uniform vec3 wind_velocity = vec3(0.);
uniform float wind_time = 0.;
uniform float amplitude = .35;
uniform float stiffness = .5;
uniform bool cloth = false;
uniform vec3 anchor_axis = vec3(0.,1.,0.);
uniform float anchor_min = 0.;
uniform float anchor_span = 1.;
uniform bool anchor_reverse = false;

vec3 bend(vec3 point, vec3 local_force, vec3 local_flutter, float phase, float speed) {
	float u = clamp((dot(point,anchor_axis)-anchor_min)/anchor_span,0.,1.);
	if (anchor_reverse) u = 1.-u;
	float weight = pow(u, mix(1.4,3.8,stiffness));
	float wave = sin(wind_time*mix(2.,4.5,float(cloth)) - u*7. + phase);
	float flutter = sin(wind_time*8. - u*13. + phase*1.7);
	float gain = amplitude * clamp(speed/12.,0.,1.5) * (1.-stiffness*.65) * weight;
	return gain * (local_force*(.68+.16*wave) + local_flutter*(wave*(.12+float(cloth)*.5)+flutter*.06*u));
}
void vertex() {
	UV = UV*uv_scale.xy + uv_offset.xy;
	float speed = length(wind_velocity);
	if (speed > .0001) {
		vec3 direction = wind_velocity/speed;
		mat3 inv_model = inverse(mat3(MODEL_MATRIX));
		vec3 local_force = inv_model*direction;
		vec3 local_flutter = inv_model*(vec3(-direction.z, .12, direction.x));
		float phase = dot(MODEL_MATRIX[3].xyz,vec3(.37,.13,.29));
		vec3 d = bend(VERTEX,local_force,local_flutter,phase,speed);
		float e = .005;
		// bend depends only on the authored X/Y anchor coordinate. The Jacobian
		// is I + slope * axis^T; its rank-one inverse preserves bent lighting
		// without three samples and a general matrix inverse per vertex.
		vec3 slope = (bend(VERTEX+anchor_axis*e,local_force,local_flutter,phase,speed)-d)/e;
		float det = 1. + dot(anchor_axis,slope);
		if (abs(det) > .0001) NORMAL = normalize(NORMAL-anchor_axis*dot(slope,NORMAL)/det);
		if (length(TANGENT) > .001) TANGENT = normalize(TANGENT+slope*dot(anchor_axis,TANGENT));
		if (length(BINORMAL) > .001) BINORMAL = normalize(BINORMAL+slope*dot(anchor_axis,BINORMAL));
		VERTEX += d;
	}
}
void fragment() {
	vec4 base = texture(albedo_tex,UV)*tint;
	if (vertex_color) base *= COLOR;
	ALBEDO = base.rgb;
	ROUGHNESS = roughness*dot(texture(rough_tex,UV),rough_channel);
	METALLIC = metallic*dot(texture(metal_tex,UV),metal_channel);
	SPECULAR = specular;
	if (normal_enabled) { NORMAL_MAP = texture(normal_tex,UV).rgb; NORMAL_MAP_DEPTH = normal_scale; }
	if (ao_enabled) { AO = dot(texture(ao_tex,UV),ao_channel); AO_LIGHT_AFFECT = ao_light; }
	vec3 glow = texture(emission_tex,UV).rgb;
	EMISSION = (emission_texture_present ? (emission_multiply ? emission*glow : emission+glow) : emission) * emission_energy;
	// BACKLIGHT_INSERT
	// ALPHA_INSERT
}
