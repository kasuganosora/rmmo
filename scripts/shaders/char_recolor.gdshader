shader_type canvas_item

## 烘焙整图角色的「捏脸-lite」重着色：按色相区间把皮肤/头发/服装
## 重新染成目标色相，保留原图明暗。源色相（skin_src/hair_src）写死在
## shader 里作为检测基准；滑块控制的是目标色相。
## 注：这是针对烘焙整图的近似方案。若要像素级独立换发型/眼睛，需分层美术，
## 数据模型已预留 part_id 字段承接。

uniform float skin_hue : hint_range(0.0, 1.0) = 0.06
uniform float hair_hue : hint_range(0.0, 1.0) = 0.07
uniform float cloth_hue : hint_range(0.0, 1.0) = 0.60
uniform float skin_on : hint_range(0.0, 1.0) = 1.0
uniform float hair_on : hint_range(0.0, 1.0) = 1.0
uniform float cloth_on : hint_range(0.0, 1.0) = 1.0
uniform float tol : hint_range(0.02, 0.25) = 0.09

const float SKIN_SRC := 0.06
const float HAIR_SRC := 0.07

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float hue_dist(float a, float b) {
	float d = abs(a - b);
	return min(d, 1.0 - d);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		COLOR = tex;
		return;
	}
	vec3 c = tex.rgb;
	vec3 hsv = rgb2hsv(c);
	float h = hsv.x;
	float s = hsv.y;
	float v = hsv.z;
	vec3 outc = c;
	bool matched = false;

	// 皮肤：偏亮、低-中饱和、肤色色相
	if (skin_on > 0.5 && s > 0.10 && s < 0.70 && v > 0.42 && hue_dist(h, SKIN_SRC) < tol) {
		outc = hsv2rgb(vec3(skin_hue, clamp(s, 0.25, 0.80), v));
		matched = true;
	}
	// 头发：偏暗、较饱和、相近色相
	if (!matched && hair_on > 0.5 && s > 0.18 && v <= 0.55 && hue_dist(h, HAIR_SRC) < tol) {
		outc = hsv2rgb(vec3(hair_hue, clamp(s, 0.30, 0.90), v));
		matched = true;
	}
	// 服装：其余较饱和的像素（铠甲/衣物/配饰），眼睛也会并入此档
	if (!matched && cloth_on > 0.5 && s > 0.28 && v > 0.25 && v < 0.96) {
		outc = hsv2rgb(vec3(cloth_hue, clamp(s, 0.35, 0.95), v));
		matched = true;
	}
	COLOR = vec4(outc, tex.a);
}
