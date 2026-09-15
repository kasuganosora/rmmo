shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D next_tex : source_color, filter_nearest, repeat_disable;
uniform float mix_t : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 from = texture(TEXTURE, UV);
	vec4 to = texture(next_tex, UV);
	COLOR = mix(from, to, clamp(mix_t, 0.0, 1.0));
}
