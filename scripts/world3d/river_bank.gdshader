shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(1.);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness = .9;
uniform float metallic = 0.;
uniform float normal_strength = 0.;
uniform vec4 rough_channel = vec4(1.,0.,0.,0.);
uniform vec4 metal_channel = vec4(1.,0.,0.,0.);
uniform vec4 ao_channel = vec4(1.,0.,0.,0.);
uniform vec3 uv_scale = vec3(1.);
uniform vec3 uv_offset = vec3(0.);
uniform float water_level = -1.5;
uniform float wet_height = .3;
varying float world_height;
void vertex() { world_height=(MODEL_MATRIX*vec4(VERTEX,1.)).y; }
void fragment() {
	vec2 uv=UV*uv_scale.xy+uv_offset.xy;
	float wet=1.-smoothstep(water_level,water_level+wet_height,world_height);
	ALBEDO=texture(albedo_tex,uv).rgb*tint.rgb*mix(1.,.64,wet);
	ROUGHNESS=dot(texture(rough_tex,uv),rough_channel)*roughness*mix(1.,.65,wet);
	METALLIC=dot(texture(metal_tex,uv),metal_channel)*metallic;
	AO=dot(texture(ao_tex,uv),ao_channel);
	NORMAL_MAP=texture(normal_tex,uv).rgb;
	NORMAL_MAP_DEPTH=normal_strength;
}
