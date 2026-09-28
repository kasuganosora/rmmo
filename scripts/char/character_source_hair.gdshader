shader_type spatial;
render_mode cull_disabled;
uniform vec4 hair_color : source_color;
uniform vec4 hair_color2 : source_color;
uniform vec4 hair_color3 : source_color;
uniform sampler2D color_mask : filter_linear_mipmap;
uniform bool has_mask = false;
uniform sampler2D gloss_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D ramp_map : filter_linear, repeat_disable;
uniform sampler2D detail_mask : filter_linear_mipmap;
uniform bool has_detail = false;
uniform bool gloss_enabled = true;
uniform float specular_height = 0.99;
uniform float shadow_extend = 0.3;
uniform float rim_width = 0.2;
uniform float rim_strength = 0.5;
uniform vec4 ambient_shadow = vec4(0.019,0.027,0.039,0.26);
uniform vec3 source_key_direction = vec3(0.0,0.0,1.0);
uniform bool source_key_enabled = false;
uniform vec4 shadow_color : source_color = vec4(0.83,0.86,0.94,1.0);
varying vec2 source_gloss_uv;
varying vec2 detail_channels;
varying float backface_factor;
vec3 overlay(vec3 a,vec3 b) {
    return mix(2.0*a*b,vec3(1.0)-2.0*(vec3(1.0)-a)*(vec3(1.0)-b),step(vec3(0.5),b));
}
vec3 source_rim_color(vec3 rgb) {
    vec4 k=vec4(0.0,-1.0/3.0,2.0/3.0,-1.0);
    vec4 p=mix(vec4(rgb.bg,k.wz),vec4(rgb.gb,k.xy),step(rgb.b,rgb.g));
    vec4 q=mix(vec4(p.xyw,rgb.r),vec4(rgb.r,p.yzx),step(p.x,rgb.r));
    float d=q.x-min(q.w,q.y);
    float hue=abs(q.z+(q.w-q.y)/(6.0*d+0.0000001));
    vec3 wave=abs(vec3(1.0)-2.0*fract(vec3(hue)+vec3(0.0,-1.0/3.0,1.0/3.0)));
    return clamp(wave*3.0-vec3(1.0),vec3(0.0),vec3(1.0))*0.33+vec3(0.33);
}
void fragment() {
    vec3 mask = has_mask ? texture(color_mask,UV).rgb : vec3(0.0);
    ALBEDO = mix(mix(mix(vec3(1.0),hair_color.rgb,mask.r),hair_color2.rgb,mask.g),hair_color3.rgb,mask.b);
    // Imported V and bitangent are flipped; reconstruct source view-dependent offset.
    source_gloss_uv = UV2;
    source_gloss_uv.y -= (specular_height-1.0)*dot(-normalize(BINORMAL),VIEW);
    detail_channels = has_detail ? texture(detail_mask,UV).gb : vec2(0.0);
    ROUGHNESS=0.48;
    SPECULAR=0.0;
    backface_factor=FRONT_FACING ? 1.0 : 0.66;
    if (!FRONT_FACING) NORMAL=-NORMAL;
}
void light() {
    float ndl=dot(NORMAL,LIGHT);
    // Unity FORWARDBASE applies the toon base/rim once. Additional studio lights
    // contribute diffuse lighting, not duplicate the base and every rim highlight.
    vec3 key_view=normalize(mat3(VIEW_MATRIX)*source_key_direction);
    if (!source_key_enabled || !LIGHT_IS_DIRECTIONAL || dot(key_view,LIGHT)<0.99999) {
        DIFFUSE_LIGHT += max(ndl,0.0)*ATTENUATION*LIGHT_COLOR/3.14159265;
    } else {
    float ramp=texture(ramp_map,vec2(ndl,ndl)).r;
    float unmasked=1.0-detail_channels.x;
    vec3 ambient_tint=ambient_shadow.a+(1.0-ambient_shadow.a)*ambient_shadow.rgb;
    vec3 shade=clamp(overlay(ambient_tint,shadow_color.rgb),vec3(0.0),vec3(1.0));
    float band=0.0;
    float band_delta=0.0;
    if (gloss_enabled) {
        vec2 shifted=source_gloss_uv+vec2(ndl*0.005,0.0);
        band=texture(gloss_map,shifted).r;
        // Source's +.008 V sample becomes -.008 after V conversion.
        band_delta=0.5*(texture(gloss_map,shifted-vec2(0.0,0.008)).r-band);
    }
    vec3 gloss_shade=mix(vec3(1.0),shade,band_delta);
    vec3 diffuse_tint=gloss_shade*mix(shade,vec3(1.0),ramp*unmasked);
    float shade_gate=max(max(ramp,unmasked),1.0-shadow_extend);
    vec3 final_tint=mix(shade,vec3(1.0),shade_gate)*backface_factor;
    float facing=max(dot(NORMAL,VIEW),0.0);
    float rim=clamp(pow(1.0-facing,rim_width*9.0+1.0)*5.0-1.5,0.0,1.0);
    vec3 rim_color=min(source_rim_color(ambient_shadow.rgb)*rim,vec3(0.5));
    vec3 highlights=vec3(band*(ramp*0.5+0.5))+rim_color*unmasked*rim_strength*(1.0-detail_channels.y);
    // Godot multiplies DIFFUSE_LIGHT by ALBEDO afterwards. Do not square pigment.
    // The source ramp already encodes diffuse response; no extra Lambert factor.
    DIFFUSE_LIGHT += diffuse_tint*final_tint*ATTENUATION*LIGHT_COLOR/3.14159265;
    SPECULAR_LIGHT += highlights*final_tint*ATTENUATION*LIGHT_COLOR/3.14159265;
    }
}
