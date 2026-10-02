shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
uniform int kind = 0; // rain ribbon, snow, surface ripple
uniform vec3 tint : source_color = vec3(.66, .79, .9);
uniform float brightness = 1.;
uniform float interpolation = 1.;
varying vec4 particle;
varying float flake_phase;
void vertex() {
	particle = INSTANCE_CUSTOM;
	flake_phase = float(INSTANCE_ID);
	if (kind == 1) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX[0].xyz *= length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX[1].xyz *= length(MODEL_MATRIX[1].xyz);
	}
	if (kind < 2) MODELVIEW_MATRIX[3] += VIEW_MATRIX * vec4(particle.yzw * (1.-interpolation), 0.);
}
void fragment() {
	vec2 p = UV*2.-1.;
	float alpha = 0.;
	if (kind == 0) alpha = pow(max(0.,1.-abs(p.x)), 1.3) * (1.-p.y*p.y) * .46;
	if (kind == 1) {
		float radius = length(p);
		float rays = .83 + .17*cos(atan(p.y,p.x)*6. + flake_phase);
		alpha = (1.-smoothstep(.3,.95,radius/rays))*.86;
	}
	if (kind == 2) {
		float radius = length(p);
		alpha = (1.-smoothstep(.03,.12,abs(radius-.72))) * .36;
	}
	ALBEDO = tint * brightness;
	ALPHA = alpha * particle.x;
}
