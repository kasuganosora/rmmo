extends RefCounted
## Original base UV materials. No replacement geometry or face recolouring.
const Art=preload("res://scripts/asset/art_paths.gd")
static var textures:Dictionary={}
const EYE_MASK="""shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled;
uniform sampler2D alpha_map : filter_linear_mipmap_anisotropic;
uniform float opacity = 0.0;
uniform float alpha_adjust = 0.0;
uniform float overlay_enabled = 1.0;
void fragment(){
 // Original AlphaMask FORWARD writes black RGB and texture A * Color A.
 ALBEDO=vec3(0.0);
 ALPHA=clamp(texture(alpha_map,UV).a*opacity+alpha_adjust,0.0,1.0)*overlay_enabled;
}
"""
const EYE_GLASS="""shader_type spatial;
render_mode blend_add, depth_draw_never, shadows_disabled;
uniform float overlay_enabled = 1.0;
uniform float surface_roughness = 0.1;
uniform float specular_strength = 0.5;
void fragment(){
 // Source glass uses premultiplied blending with zero diffuse opacity:
 // keep the iris visible and add only light/environment specular response.
 ALBEDO=vec3(0.0);
 ALPHA=overlay_enabled;
 ROUGHNESS=surface_roughness;
 SPECULAR=specular_strength;
}
"""
const TEAR="""shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform vec4 tint : source_color;
uniform float alpha_adjust = 0.0;
uniform float overlay_enabled = 1.0;
uniform float surface_roughness = 0.25;
void fragment(){
 ALBEDO=tint.rgb;
 ALPHA=clamp(tint.a+alpha_adjust,0.0,1.0)*overlay_enabled;
 ROUGHNESS=surface_roughness;
 SPECULAR=0.5;
}
"""
const LASH="""shader_type spatial;
render_mode cull_disabled, alpha_to_coverage;
uniform sampler2D alpha_map : filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color;
uniform float cutoff = 0.3;
void fragment(){
 ALBEDO=tint.rgb;
 ALPHA=texture(alpha_map,UV).a;
 ALPHA_SCISSOR_THRESHOLD=cutoff;
 ALPHA_ANTIALIASING_EDGE=cutoff;
 ALPHA_TEXTURE_COORDINATE=UV*vec2(textureSize(alpha_map,0));
 ROUGHNESS=1.0;
 SPECULAR=0.0;
}
"""
const MOUTH="""shader_type spatial;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D specular_map : filter_linear_mipmap_anisotropic;
uniform sampler2D packed_normal_map : filter_linear_mipmap_anisotropic;
uniform bool use_normal_map = false;
uniform float normal_depth = 1.0;
uniform vec4 tint : source_color;
uniform float surface_roughness = 0.35;
void fragment(){
 ALBEDO=texture(albedo_map,UV).rgb*tint.rgb;
 ROUGHNESS=surface_roughness;
 SPECULAR=texture(specular_map,UV).r*0.5;
 if(use_normal_map){
  // Original Unity DXT5nm stores tangent X in A and tangent Y in G.
  vec2 xy=texture(packed_normal_map,UV).ag*2.0-1.0;
  vec3 mapped=vec3(xy*normal_depth,sqrt(max(1.0-dot(xy,xy),0.0)));
  // Rest tangents are invalid after original per-axis skin deformation.
  vec3 dp1=dFdx(VERTEX),dp2=dFdy(VERTEX);
  vec2 uv1=dFdx(UV),uv2=dFdy(UV);
  vec3 perpendicular2=cross(dp2,NORMAL),perpendicular1=cross(NORMAL,dp1);
  vec3 tangent=perpendicular2*uv1.x+perpendicular1*uv2.x;
  vec3 bitangent=perpendicular2*uv1.y+perpendicular1*uv2.y;
  float inverse_scale=inversesqrt(max(max(dot(tangent,tangent),dot(bitangent,bitangent)),0.000000000001));
  NORMAL=normalize(tangent*inverse_scale*mapped.x+bitangent*inverse_scale*mapped.y+NORMAL*mapped.z);
 }
}
"""
static func texture(file:String)->Texture2D:
 var path:String=Art.path("characters/materials/face_native_01/"+file)
 var modified:=FileAccess.get_modified_time(path)
 if not textures.has(path) or textures[path].modified!=modified:
  var image:=Image.load_from_file(path)
  if image==null or image.is_empty():push_error("Missing native face texture: "+path);return null
  image.generate_mipmaps()
  textures[path]={"modified":modified,"texture":ImageTexture.create_from_image(image)}
 return textures[path].texture

static func create_materials()->Dictionary:
 var manifest_path:String=Art.path("characters/materials/face_native_01/manifest.json")
 var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
 if not manifest is Dictionary:push_error("Missing native face material manifest");return {}
 var result:Dictionary={}
 for name:String in ["Eyelashes","Gums","Tongue","Teeth","InnerMouth","Cornea","EyeReflection","Tear"]:
  var source:Dictionary=manifest.materials[name]
  # Guard the known semantic split: Cornea is a dark alpha mask, not glass.
  if name=="Cornea" and source.get("shader",{}).get("name","")!="Custom/Subsurface/AlphaMask":
   push_error("Native cornea shader provenance mismatch; repackage verified source");return {}
  var colors:Dictionary={};var floats:Dictionary={}
  for pair:Array in source.properties.m_Colors:colors[pair[0]]=pair[1]
  for pair:Array in source.properties.m_Floats:floats[pair[0]]=pair[1]
  var mat:=ShaderMaterial.new();var shader:=Shader.new()
  shader.code={"Eyelashes":LASH,"Cornea":EYE_MASK,"EyeReflection":EYE_GLASS,"Tear":TEAR}.get(name,MOUTH);mat.shader=shader
  mat.resource_name="face_native_01_"+name;mat.set_meta("native_face_surface",name)
  var color:Dictionary=colors._Color
  if name not in ["Cornea","EyeReflection"]:mat.set_shader_parameter("tint",Color(color.r,color.g,color.b,color.a))
  if name=="Eyelashes":
   var alpha:=texture(source.textures._AlphaTex.file)
   if alpha==null:return {}
   mat.set_shader_parameter("alpha_map",alpha)
   mat.set_shader_parameter("cutoff",floats._Cutoff)
  elif name=="Cornea":
   var mask:=texture(source.textures._MainTex.file)
   if mask==null:return {}
   mat.set_shader_parameter("alpha_map",mask)
   mat.set_shader_parameter("opacity",color.a)
   mat.set_shader_parameter("alpha_adjust",floats._AlphaAdjust)
   mat.render_priority=0
  elif name=="EyeReflection":
   # Native exponent -> approximate GGX width. This is renderer adaptation,
   # not a claim that Godot reproduces Marmoset IBL/exposure exactly.
   mat.set_shader_parameter("surface_roughness",sqrt(2.0/(2.0*pow(2.0,float(floats._Shininess))+2.0)))
   mat.set_shader_parameter("specular_strength",clampf(float(colors._SpecColor.r)*float(floats._SpecInt),0.0,1.0))
   mat.render_priority=1
  elif name=="Tear":
   mat.set_shader_parameter("alpha_adjust",floats._AlphaAdjust)
   mat.render_priority=2
  else:
   var albedo:=texture(source.textures._MainTex.file)
   var specular:=texture(source.textures._SpecTex.file)
   if albedo==null or specular==null:return {}
   mat.set_shader_parameter("albedo_map",albedo)
   mat.set_shader_parameter("specular_map",specular)
   # Approximate PBR wetness; Unity exponent is not Godot roughness.
   mat.set_shader_parameter("surface_roughness",0.28 if name=="Teeth" else 0.4)
   if source.textures.has("_BumpMap"):
    var packed_normal:=texture(source.textures._BumpMap.file)
    if packed_normal==null:return {}
    mat.set_shader_parameter("packed_normal_map",packed_normal)
    mat.set_shader_parameter("use_normal_map",true)
    mat.set_shader_parameter("normal_depth",floats._DiffuseBumpiness)
  result[name]=mat
 return result
