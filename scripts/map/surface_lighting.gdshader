shader_type canvas_item;
render_mode blend_mix;
uniform sampler2D normal_tex : hint_normal, filter_nearest, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D emission_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D meadow_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D river_tex : source_color, filter_linear, repeat_enable;
uniform bool terrain_enabled = false;
uniform vec2 world_origin = vec2(0.0);
uniform float night_factor = 0.0;
uniform vec2 chunk_pixels = vec2(768.0);
uniform float padding = 192.0;
uniform vec2 sun_direction = vec2(0.72, 0.69);
uniform float normal_strength = 1.0;
uniform float shadow_strength = 0.26;
uniform float shadow_length = 112.0;
uniform bool receive_shadows = true;
uniform float animation_speed = 1.0;
uniform float preview_time = -1.0;
varying vec4 item_tint;
// Mirrored, texel-centred sampling joins identical edge texels. Mixing
// different periods hides the reflected motif without introducing tile seams.
vec2 mirror_uv(vec2 uv) {
	return clamp(abs(fract(uv*.5)*2.0-1.0),vec2(.5/192.0),vec2(1.0-.5/192.0));
}
vec3 meadow_color(vec2 world_px) {
	// Continuous world-space distortion breaks the reflected rows without
	// introducing a new grid of independently randomized tile boundaries.
	world_px+=vec2(sin(world_px.y*.009+sin(world_px.x*.004))*18.0,
		sin(world_px.x*.011+sin(world_px.y*.007))*21.0);
	vec3 a=texture(meadow_tex,mirror_uv(world_px/192.0)).rgb;
	vec3 b=texture(meadow_tex,mirror_uv(world_px.yx/288.0+vec2(.37,.61))).rgb;
	return mix(a,b,.32);
}
void vertex() { item_tint = COLOR; }
void fragment() {
	float t = preview_time >= 0.0 ? preview_time : TIME * animation_speed;
	vec2 hp = (UV * chunk_pixels + vec2(padding)) / (chunk_pixels + vec2(padding * 2.0));
	vec4 surface = texture(height_tex, hp);
	vec2 uv = UV;
	float water = step(0.6, surface.g);
	vec2 ripple = vec2(sin(t*3.3 + surface.b*39.0),cos(t*2.8 + surface.b*31.0));
	vec2 displaced = uv + ripple * TEXTURE_PIXEL_SIZE * water * 0.85;
	vec2 dhp = (displaced * chunk_pixels + vec2(padding)) / (chunk_pixels + vec2(padding*2.0));
	if (texture(height_tex, dhp).g > 0.6 && water > 0.5) { uv = displaced; }
	vec4 albedo = texture(TEXTURE, uv);
	vec2 world_px=world_origin+UV*chunk_pixels;
	float grass_amount=0.0;
	float river=step(.22,surface.g)*(1.0-step(.5,surface.g));
	if (terrain_enabled && surface.r<.01 && surface.g<.1) {
		vec2 d=vec2(6.0)/(chunk_pixels+vec2(padding*2.0));
		float grass=surface.b*.4;
		grass+=(texture(height_tex,hp+vec2(d.x,0)).b+texture(height_tex,hp-vec2(d.x,0)).b+texture(height_tex,hp+vec2(0,d.y)).b+texture(height_tex,hp-vec2(0,d.y)).b)*.15;
		float fleck=fract(sin(dot(floor(world_px/2.0),vec2(12.9898,78.233)))*43758.5453);
		grass=smoothstep(.04,.96,grass+(fleck-.5)*.17);
		vec3 meadow=meadow_color(world_px);
		float patch=sin(world_px.x*.004+sin(world_px.y*.009))*sin(world_px.y*.006);
		meadow*=1.0+patch*.09;
		albedo.rgb=mix(albedo.rgb,meadow,grass);
		grass_amount=grass;
	}
	if (terrain_enabled && river>.5) {
		vec2 flow=world_px/192.0+vec2(.012,-.006)*t;
		flow+=vec2(sin(world_px.y*.017+t*.7),cos(world_px.x*.014-t*.8))*.009;
		albedo.rgb=texture(river_tex,mirror_uv(flow)).rgb;
		float shimmer=sin(world_px.y*.11+sin(world_px.x*.027-t)*2.0-t*1.6);
		albedo.rgb+=vec3(.015,.033,.034)*max(0.0,shimmer);
	}
	vec3 n = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	n.xy *= normal_strength;
	if (terrain_enabled && grass_amount>.01) {
		vec3 lum=vec3(.2126,.7152,.0722);
		float dx=dot(meadow_color(world_px-vec2(2,0))-meadow_color(world_px+vec2(2,0)),lum);
		float dy=dot(meadow_color(world_px+vec2(0,2))-meadow_color(world_px-vec2(0,2)),lum);
		n=mix(n,normalize(vec3(dx*.8,dy*.8,1.0)),grass_amount);
	}
	if (water > 0.5) { n.xy += ripple * 0.12; }
	if (terrain_enabled && river>.5) {n=normalize(vec3(sin(world_px.y*.08+t)*.12,cos(world_px.x*.06-t)*.12,1.0));}
	n = normalize(n);
	NORMAL_MAP = n * 0.5 + 0.5;
	vec3 light_dir = normalize(vec3(-sun_direction.x,sun_direction.y,0.8));
	float relief = (dot(n,light_dir) - light_dir.z) * 0.65;
	float shade = 0.0;
	if (receive_shadows && surface.r < 0.01) {
		vec2 ray = normalize(sun_direction);
		for (int i=1; i<=64; i++) {
			float distance_px = float(i) * shadow_length / 64.0;
			vec2 sample_uv = hp - ray * distance_px / (chunk_pixels + vec2(padding*2.0));
			vec4 caster = texture(height_tex, sample_uv);
			float hit = smoothstep(distance_px*1.25, distance_px*1.25+12.0, caster.r*400.0);
			shade = max(shade, hit * caster.a * (1.0-distance_px/shadow_length*0.22));
		}
	}
	vec3 rgb = albedo.rgb * (1.0 + relief);
	rgb = mix(rgb, rgb * vec3(0.60,0.67,0.80), shade * shadow_strength * 2.2 * (1.0-night_factor*.85));
	float foam = pow(max(0.0,sin(surface.b*45.0-t*4.4)),14.0)*water;
	rgb += vec3(0.11,0.16,0.18)*foam;
	vec4 emission=texture(emission_tex,UV);
	COLOR = vec4(rgb * item_tint.rgb + emission.rgb*emission.a*night_factor*.65,albedo.a*item_tint.a);
}
