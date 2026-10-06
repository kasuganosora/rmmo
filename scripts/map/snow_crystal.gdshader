shader_type canvas_item;
render_mode unshaded;

// Tiny analytic six-armed ice crystals, rotated by the particle emitter.
float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = 1.0;
	for (int i = 0; i < 6; i++) {
		float angle = float(i) * 1.04719755;
		vec2 q = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle))) * p;
		d = min(d, segment_distance(q, vec2(0.0), vec2(0.0, 0.82)));
		d = min(d, segment_distance(q, vec2(0.0, 0.43), vec2(0.2, 0.62)));
		d = min(d, segment_distance(q, vec2(0.0, 0.43), vec2(-0.2, 0.62)));
	}
	float aa = max(fwidth(d), 0.015);
	float ice = 1.0 - smoothstep(0.023, 0.023 + aa, d);
	float halo = exp(-dot(p, p) * 7.0) * 0.16;
	COLOR = vec4(COLOR.rgb, COLOR.a * max(ice, halo));
}
