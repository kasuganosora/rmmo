shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float energy=1.;
void fragment() {
    float distance=abs(UV.x-.5)*2.;
    float width=max(.10,fwidth(UV.x)*1.5);
    float core=1.-smoothstep(0.,width,distance);
    float glow=exp(-distance*4.)*.3;
    ALBEDO=(vec3(.65,.8,1.)*glow+vec3(.9,.95,1.)*core)*energy*4.;
    ALPHA=clamp(core+glow,0.,1.);
}
