shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D atlas_tex : source_color, filter_nearest;
uniform vec2 atlas_pixel_size = vec2(1.0, 1.0);
uniform vec2 region_origin_px = vec2(0.0, 0.0);
uniform float region_side_px = 128.0;
uniform vec4 fill_color = vec4(0.08, 0.10, 0.09, 1.0);

void fragment() {
	vec2 local = UV * region_side_px;
	float r = region_side_px * 0.5;
	vec2 d = local - vec2(r, r);
	float dist = length(d);
	float mask = 1.0 - smoothstep(r - 0.75, r + 0.25, dist);
	if (mask <= 0.001) {
		discard;
	}
	vec2 atlas_px = region_origin_px + local;
	vec4 col = fill_color;
	if (atlas_px.x >= 0.0 && atlas_px.y >= 0.0
			&& atlas_px.x < atlas_pixel_size.x && atlas_px.y < atlas_pixel_size.y) {
		vec2 uv = (atlas_px + vec2(0.5)) / max(atlas_pixel_size, vec2(1.0));
		col = texture(atlas_tex, uv);
		if (col.a < 0.01) {
			col = fill_color;
		}
	}
	COLOR = vec4(col.rgb, col.a * mask);
}
