extends RefCounted
## Opaque backing keeps the safety layer intact beneath embroidered lace.
const CODE="""shader_type spatial;
render_mode diffuse_burley;
uniform bool lace = false;
float embroidery(vec2 p) {
    vec2 q=fract(p)-0.5;
    float radius=length(q);
    float angle=atan(q.y,q.x);
    float edge=0.255+0.055*cos(angle*6.0);
    float aa=max(length(fwidth(p)),0.008);
    float petal=1.0-smoothstep(0.012,0.012+aa,abs(radius-edge));
    float center=1.0-smoothstep(0.010,0.010+aa,abs(radius-0.070));
    float stem=1.0-smoothstep(0.006,0.006+aa,abs(abs(q.x)-abs(q.y)));
    return max(max(petal,center),stem*0.55);
}
void fragment() {
    vec2 p=UV*40.0;
    float thread=embroidery(p);
    float detail=1.0-smoothstep(0.15,0.65,length(fwidth(p)));
    vec3 backing=vec3(0.83,0.82,0.80);
    ALBEDO=lace?mix(backing,vec3(0.96,0.955,0.94),thread*detail):vec3(0.86,0.845,0.82);
    ROUGHNESS=lace?mix(0.87,0.68,thread):0.92;
    SPECULAR=0.18;
    EMISSION=ALBEDO*0.08;
}
"""
static var materials:Dictionary={}
static func for_body(gender:String)->Material:
	if not materials.has(gender):
		var shader:=Shader.new();shader.code=CODE
		var material:=ShaderMaterial.new();material.shader=shader;material.set_shader_parameter("lace",gender=="female")
		materials[gender]=material
	return materials[gender]
