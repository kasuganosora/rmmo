shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float radius = 2.0;
uniform int shape = 0; // circle, cross, line, cone
uniform vec2 facing = vec2(0.0, 1.0);
varying vec2 offset_m;
void vertex() { offset_m = VERTEX.xz; }
void fragment() {
	float distance_to_edge = length(offset_m) - radius;
	if (shape == 1) {
		distance_to_edge = max(distance_to_edge, min(abs(offset_m.x), abs(offset_m.y)) - 0.5);
	} else if (shape == 2) {
		float sideways = abs(offset_m.x * facing.y - offset_m.y * facing.x);
		distance_to_edge = max(distance_to_edge, max(-dot(offset_m, facing), sideways - 0.5));
	} else if (shape == 3) {
		distance_to_edge = max(distance_to_edge, length(offset_m) * 0.5 - dot(offset_m, facing));
	}
	if (distance_to_edge > 0.0) { discard; }
	ALBEDO = vec3(1.0, 0.29, 0.06);
	ALPHA = mix(0.15, 0.9, smoothstep(-0.06, -0.015, distance_to_edge));
}
