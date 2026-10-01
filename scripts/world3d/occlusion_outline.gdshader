shader_type canvas_item;
render_mode unshaded;
uniform sampler2D player_mask : filter_linear, repeat_disable;
uniform vec4 outline_color : source_color = vec4(1.0, 0.78, 0.25, 1.0);
uniform float width = 2.0;
void fragment() {
	vec2 step_uv = width / vec2(textureSize(player_mask, 0));
	float center = texture(player_mask, UV).a;
	float edge = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			edge = max(edge, texture(player_mask, UV + vec2(float(x), float(y)) * step_uv).a);
		}
	}
	COLOR = vec4(outline_color.rgb, outline_color.a * max(0.0, edge - center));
}
