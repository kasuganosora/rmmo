shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform sampler2D shelter_height : filter_nearest, repeat_disable;
uniform vec2 shelter_origin;
uniform float shelter_span=48.;
uniform float wetness=0.;
uniform float puddles=0.;
uniform float wet_time=0.;
uniform float rain=0.;
uniform vec4 tint:source_color=vec4(1.);
uniform sampler2D albedo_tex:source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 uv_scale=vec3(1.);
uniform vec3 uv_offset=vec3(0.);
uniform float base_roughness=.8;
varying vec3 world_position;
varying vec3 world_normal;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.-2.*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    vec2 uv=(world_position.xz-shelter_origin)/shelter_span;
    if (min(uv.x,uv.y)<0. || max(uv.x,uv.y)>1.) discard;
    float roof=texture(shelter_height,uv).r;
    // Point sampling in world-aligned cells; roof collision survives visual cutaway.
    float exposure=step(roof-.12,world_position.y)*step(-90000.,roof);
    float facing=smoothstep(.12,.75,world_normal.y);
    float wet=wetness*exposure*facing;
    if (wet<.005) discard;
    float patch=smoothstep(.43,.68,noise(world_position.xz*.32));
    vec2 cell=vec2(1./32.,0.);
    float neighbours=(texture(shelter_height,uv+cell).r+texture(shelter_height,uv-cell).r+texture(shelter_height,uv+cell.yx).r+texture(shelter_height,uv-cell.yx).r)*.25;
    float depression=smoothstep(.03,.25,neighbours-roof);
    patch=mix(patch,1.,depression);
    float pool=puddles*patch*smoothstep(.92,.995,world_normal.y);
    vec2 tile=floor(world_position.xz*1.7);
    vec2 ripple=fract(world_position.xz*1.7)-.5;
    float phase=fract(wet_time*.7+hash(tile));
    float rings=sin(length(ripple)*65.-phase*20.)*(1.-phase)*rain*pool;
    ALBEDO=(texture(albedo_tex,UV*uv_scale.xy+uv_offset.xy)*tint).rgb*mix(.57,.32,pool);
    ROUGHNESS=mix(min(base_roughness,.32),.065,pool);
    SPECULAR=.65;
    NORMAL=normalize(NORMAL+vec3(ripple.x,ripple.y,0.)*rings*.12);
    ALPHA=wet*mix(.50,.85,pool);
}
