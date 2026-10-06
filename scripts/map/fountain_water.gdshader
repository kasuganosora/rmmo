shader_type canvas_item;
render_mode unshaded;
uniform float preview_time = -1.0;
uniform float animation_speed = 1.0;
varying vec4 item_tint;
void vertex() { item_tint=COLOR; }
void fragment() {
	float t=preview_time>=0.0?preview_time:TIME*animation_speed;
	vec2 p=floor(UV*vec2(48.0,64.0));
	float alpha=0.0;
	for(int i=0;i<3;i++) {
		float phase=fract(t*0.85+float(i)*0.333);
		float spread=(phase-.5)*32.0;
		float y=34.0-23.0*sin(phase*3.14159);
		vec2 drop=vec2(24.0+spread,y);
		alpha=max(alpha,1.0-smoothstep(0.8,2.0,length(p-drop)));
	}
	float jet=abs(p.x-24.0-sin(p.y*.33-t*5.0)*1.1);
	alpha=max(alpha,(1.0-smoothstep(.5,1.5,jet))*step(18.0,p.y)*step(p.y,34.0)*.75);
	COLOR=vec4(mix(vec3(.37,.69,.80),vec3(.83,.96,1.0),alpha),alpha*.78)*item_tint;
}
