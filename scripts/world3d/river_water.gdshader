shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength = .7;
uniform float roughness = .22;
uniform float absorption = .45;
uniform vec3 shallow_color : source_color = vec3(.24,.42,.34);
uniform vec3 deep_color : source_color = vec3(.055,.16,.14);
varying vec3 world_position;
varying vec3 water_normal;
void vertex() {
	world_position=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
	water_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	float depth=texture(scene_depth,SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc=vec3(SCREEN_UV,depth)*2.-1.;
	#else
	vec3 ndc=vec3(SCREEN_UV*2.-1.,depth);
	#endif
	vec4 bottom_view=INV_PROJECTION_MATRIX*vec4(ndc,1.);
	bottom_view/=bottom_view.w;
	vec3 bottom_world=(INV_VIEW_MATRIX*bottom_view).xyz;
	float vertical_depth=max(0.,world_position.y-bottom_world.y);
	float thickness=max(0.,VERTEX.z-bottom_view.z);
	ALBEDO=mix(shallow_color,deep_color,1.-exp(-vertical_depth*.65));
	ROUGHNESS=roughness;
	vec3 ripple=texture(normal_tex,world_position.xz/4.).rgb*2.-1.;
	// Keep the horizontal X/Z ripple unchanged, but anchor it to the actual
	// longitudinal water surface instead of forcing every river to world-up.
	vec3 base_normal=normalize(water_normal);
	vec3 reference_axis=abs(base_normal.x)<.99?vec3(1.,0.,0.):vec3(0.,0.,1.);
	vec3 along=normalize(reference_axis-base_normal*dot(reference_axis,base_normal));
	vec3 across=normalize(cross(along,base_normal));
	vec3 rippled=along*ripple.x*normal_strength+base_normal*ripple.z+across*ripple.y*normal_strength;
	NORMAL=normalize((VIEW_MATRIX*vec4(rippled,0.)).xyz);
	// Fade at the real shore; deeper/oblique rays hide the bottom progressively.
	ALPHA=clamp(1.-exp(-thickness*absorption),0.,.96)*smoothstep(0.,.12,vertical_depth);
}
