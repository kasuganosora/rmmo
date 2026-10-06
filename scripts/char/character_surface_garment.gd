extends Node3D
## A garment shares the body's control-position texture; UV seams share one anchor.
## Surface following is deliberately separate from the pending free-cloth solver.
const Art=preload("res://scripts/asset/art_paths.gd")
const CODE="""shader_type spatial;
render_mode cull_disabled;
uniform sampler2D body_positions : filter_nearest;
uniform sampler2D body_normals : filter_nearest;
uniform sampler2D anchors : filter_nearest;
uniform sampler2D cloth_positions : filter_nearest;
uniform sampler2D cloth_normals : filter_nearest;
uniform bool simulate=false;
uniform bool candidate_simulate=false;
uniform sampler2D candidate_lookup : filter_nearest;
uniform sampler2D candidate_positions : filter_nearest;
uniform sampler2D candidate_normals : filter_nearest;
uniform sampler2D diffuse_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D alpha_map : filter_linear_mipmap_anisotropic;
uniform sampler2D gloss_map : filter_linear_mipmap_anisotropic;
uniform sampler2D specular_map : filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_diffuse=false;
uniform bool has_alpha=false;
uniform bool has_gloss=false;
uniform bool has_specular=false;
uniform bool lined_lace=false;
uniform float alpha_adjust=0.0;
uniform bool material_hidden=false;
vec3 fetch_point(sampler2D map,int index) {
    int width=textureSize(map,0).x;
    return texelFetch(map,ivec2(index%width,index/width),0).xyz;
}
void vertex() {
    int id=int(UV2.x);
    vec3 ids=fetch_point(anchors,id*2);
    vec3 offset=fetch_point(anchors,id*2+1);
    vec3 a=fetch_point(body_positions,int(ids.x));
    vec3 b=fetch_point(body_positions,int(ids.y));
    vec3 c=fetch_point(body_positions,int(ids.z));
    vec3 normal=-normalize(cross(b-a,c-a));
    vec3 tangent=(a+b+c)/3.0-a;
    mat3 frame=mat3(tangent,cross(tangent,normal),normal);
    VERTEX=a+frame*offset;
    NORMAL=normalize(transpose(inverse(frame))*NORMAL);
    if(simulate){VERTEX=fetch_point(cloth_positions,id);NORMAL=fetch_point(cloth_normals,id);}
    if(candidate_simulate){int particle=int(fetch_point(candidate_lookup,id).x);VERTEX=fetch_point(candidate_positions,particle);NORMAL=fetch_point(candidate_normals,particle);}
}
void fragment() {
    vec4 color=has_diffuse?texture(diffuse_map,UV):tint;
    ALBEDO=color.rgb;
    ROUGHNESS=has_gloss?mix(0.9,0.3,texture(gloss_map,UV).r):0.65;
    SPECULAR=has_specular?0.4*texture(specular_map,UV).r:0.25;
    float coverage=clamp((has_alpha?texture(alpha_map,UV).r:1.0)+alpha_adjust,0.0,1.0);
    if(material_hidden){discard;}
    if(lined_lace){
        // A fabric lining keeps the cup covered while the original lace map
        // supplies the thread pattern; scalloped border surfaces remain cutout.
        ALBEDO*=mix(0.82,1.0,coverage);
        ROUGHNESS=mix(0.82,0.62,coverage);
    }else if(coverage<0.5){discard;}
    if(color.a<0.5){discard;}
    if(!FRONT_FACING){NORMAL=-NORMAL;}
}
"""
static var textures:Dictionary={}
var garment_id:String
var body:Node3D
var data:Dictionary
var binding:Dictionary
var rest_points:=PackedVector3Array()
var mesh_instance:MeshInstance3D
var triangle_count:=0
var cloth:RefCounted
var cloth_enabled:=true
func enable_cloth()->bool:
	if not cloth_enabled:return false
	if cloth!=null:return true
	cloth=preload("res://scripts/char/garment_cloth_gpu.gd").new()
	if not cloth.initialize(Art.path("characters/equipment/surface_bound/"+garment_id),rest_points.size()):cloth=null;return false
	cloth.step(body,true,0)
	for i in mesh_instance.mesh.get_surface_count():
		var material:ShaderMaterial=mesh_instance.mesh.surface_get_material(i)
		material.set_shader_parameter("cloth_positions",cloth.position_texture)
		material.set_shader_parameter("cloth_normals",cloth.normal_texture)
		material.set_shader_parameter("simulate",true)
	return true
func disable_cloth()->void:
	if cloth==null:return
	for i in mesh_instance.mesh.get_surface_count():mesh_instance.mesh.surface_get_material(i).set_shader_parameter("simulate",false)
	cloth.close();cloth=null
func _exit_tree()->void:
	if cloth:cloth.close();cloth=null

static func surface_frame(a:Vector3,b:Vector3,c:Vector3)->Transform3D:
	var normal:Vector3=-(b-a).cross(c-a).normalized()
	var tangent:Vector3=(a+b+c)/3.0-a
	return Transform3D(Basis(tangent,tangent.cross(normal),normal),a)

func initialize(target:Node3D,id:String)->bool:
	var folder:String=Art.path("characters/equipment/surface_bound/"+id)
	if not FileAccess.file_exists(folder+"/binding.json"):push_error("Missing garment binding: "+id);return false
	binding=JSON.parse_string(FileAccess.get_file_as_string(folder+"/binding.json"))
	if binding.version!=3 or binding.body_vertex_count!=target.rest_points.size():return false
	cloth_enabled=bool(binding.get("cloth_enabled",true))
	var body_path:String=Art.path("characters/base/female_base_v2/female_display_topology.json")
	if FileAccess.get_sha256(body_path)!=binding.body_sha256:push_error("Garment/body topology mismatch");return false
	var source:String=Art.path(binding.source_relative)
	if FileAccess.get_sha256(source+"/clothing_data.json")!=binding.source_sha256:push_error("Garment source changed; rebuild binding");return false
	data=JSON.parse_string(FileAccess.get_file_as_string(source+"/clothing_data.json"))
	garment_id=id;body=target
	for p:Array in data.vertices:rest_points.append(Vector3(p[0],p[1],p[2]))
	if binding.anchors.size()!=rest_points.size():return false
	var normals:=PackedVector3Array();normals.resize(rest_points.size())
	for face:Dictionary in data.faces:
		var p:Array=face.vertices
		for j in range(1,p.size()-1):
			var normal:Vector3=-(rest_points[p[j]]-rest_points[p[0]]).cross(rest_points[p[j+1]]-rest_points[p[0]])
			for vertex:int in [p[0],p[j],p[j+1]]:normals[vertex]+=normal
	for i in normals.size():
		var anchor:Array=binding.anchors[i]
		var frame:=surface_frame(body.rest_points[anchor[0]],body.rest_points[anchor[1]],body.rest_points[anchor[2]])
		normals[i]=frame.basis.transposed()*normals[i].normalized()
	var height:int=ceili(float(rest_points.size()*2)/512)
	var texture:=ImageTexture.create_from_image(Image.create_from_data(512,height,false,Image.FORMAT_RGBAF,FileAccess.get_file_as_bytes(folder+"/anchors.rgba32f")))
	var settings:Array=JSON.parse_string(FileAccess.get_file_as_string(folder+"/material_settings.json"))
	var mesh:=ArrayMesh.new()
	for material_index in data.materials.size():
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count:=0
		for f in data.faces.size():
			var face:Dictionary=data.faces[f]
			if int(face.material)!=material_index:continue
			for j in range(1,face.vertices.size()-1):
				for corner:int in [0,j,j+1]:
					var index:int=face.vertices[corner];var uv:Array=data.uv[data.uv_faces[f].vertices[corner]]
					st.set_normal(normals[index]);st.set_uv(Vector2(uv[0],1.0-uv[1]));st.set_uv2(Vector2(index,0));st.add_vertex(rest_points[index])
				count+=1
		if count==0:continue
		triangle_count+=count;st.index();st.commit(mesh)
		var config:Dictionary=settings[material_index]
		var material:=ShaderMaterial.new();var shader:=Shader.new();shader.code=CODE;material.shader=shader
		material.resource_name=data.materials[material_index]
		material.set_shader_parameter("body_positions",body.positions_texture);material.set_shader_parameter("anchors",texture)
		material.set_shader_parameter("body_normals",body.normals_texture)
		var color:Dictionary=config.get("Diffuse Color",{"h":0,"s":0,"v":0.8})
		material.set_shader_parameter("tint",Color.from_hsv(float(color.h),float(color.s),float(color.v)))
		material.set_shader_parameter("lined_lace",bool(config.get("lined_lace",false)))
		material.set_shader_parameter("alpha_adjust",float(config.get("Alpha Adjust",0.0)))
		material.set_shader_parameter("material_hidden",str(config.get("hideMaterial","false")).to_lower()=="true")
		for pair in [["diffuse","customTexture_MainTex"],["alpha","customTexture_AlphaTex"],["gloss","customTexture_GlossTex"],["specular","customTexture_SpecTex"]]:
			var filename:String=config.get(pair[1],"")
			if filename.is_empty():continue
			var path:String=source+"/"+filename
			if not textures.has(path):
				var image:=Image.load_from_file(path)
				if image==null:return false
				image.generate_mipmaps();textures[path]=ImageTexture.create_from_image(image)
			material.set_shader_parameter(pair[0]+"_map",textures[path]);material.set_shader_parameter("has_"+pair[0],true)
		mesh.surface_set_material(mesh.get_surface_count()-1,material)
	mesh_instance=MeshInstance3D.new();mesh_instance.mesh=mesh
	mesh_instance.custom_aabb=AABB(Vector3(-3,-3,-3),Vector3(6,6,6));add_child(mesh_instance)
	return true

func evaluate(points:PackedVector3Array)->PackedVector3Array:
	var result:=PackedVector3Array();result.resize(rest_points.size())
	for i in result.size():
		var a:Array=binding.anchors[i]
		result[i]=surface_frame(points[a[0]],points[a[1]],points[a[2]])*Vector3(a[3],a[4],a[5])
	return result

func strain(points:PackedVector3Array)->Dictionary:
	var maximum:=1.0;var stretched:=0;var usable:=0
	for edge:Array in binding.edges:
		if edge[2]<0.0005:continue
		var ratio:float=points[edge[0]].distance_to(points[edge[1]])/edge[2]
		maximum=maxf(maximum,ratio);usable+=1
		if ratio>1.5:stretched+=1
	return {"maximum":maximum,"over_50_percent":stretched,"edges":usable}
