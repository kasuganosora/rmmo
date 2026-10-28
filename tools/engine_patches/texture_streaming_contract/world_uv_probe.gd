extends "camera_probe.gd"
## Models the terrain shader's world-coordinate sampling (no mesh UV use).
## First reproduces missing automatic feedback, then supplies the upstream
## STREAMING_LOD contract. Does not modify the production terrain shader.

const WORLD_SHADER:="""shader_type spatial;
render_mode unshaded;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 sampled_uv=world_position.xy/2.0+vec2(0.5);
	ALBEDO=texture(source_texture,sampled_uv).rgb;
	// FEEDBACK
}
"""
const WORLD_FEEDBACK:="""
	vec2 dx=dFdx(sampled_uv),dy=dFdy(sampled_uv);
	float dx_sq=dot(dx,dx),dy_sq=dot(dy,dy);
	float footprint_sq=max(min(dx_sq,dy_sq),max(dx_sq,dy_sq)/256.0);
	STREAMING_LOD=0.5*log2(max(footprint_sq,1e-30))+12.0;
"""

func run()->void:
	create_timer(60).timeout.connect(func():quit(2))
	Engine.max_fps=60
	if source.is_empty() or output.is_empty():push_error("--source and --output required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	report.engine=Engine.get_version_info();report.source=source;report.source_sha256=FileAccess.get_sha256(source)
	report.forced_lod=false;report.flush_used=false;report.scope="world-coordinate shader feedback reproduction, not production map acceptance"
	check(ClassDB.class_exists("StreamedTexture2D") and Engine.has_singleton("TextureStreaming"),"streaming API exists")
	if failed:finish();return
	streaming=Engine.get_singleton("TextureStreaming")
	report.memory_before=streaming.call("get_memory_budget_bytes_used")
	var image:=Image.load_from_file(source);image.convert(Image.FORMAT_RGBA8);image.generate_mipmaps()
	var path:=output.path_join("source_pixels.stex");write_stex(image,path)
	var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	check(texture.call("load",path)==OK,"load uncompressed source mip chain")
	var small:=sample(texture,"initial")
	var scene:=Node3D.new();root.add_child(scene)
	var quad:=QuadMesh.new();quad.size=Vector2(2,2)
	var mesh:=MeshInstance3D.new();mesh.mesh=quad;scene.add_child(mesh)
	var material:=ShaderMaterial.new();var shader:=Shader.new();shader.code=WORLD_SHADER
	material.shader=shader;material.set_shader_parameter("source_texture",texture);mesh.material_override=material
	var camera:=Camera3D.new();scene.add_child(camera);camera.position.z=0.5;camera.current=true
	await create_timer(5).timeout
	var missing:=sample(texture,"world_uv_without_feedback")
	report.baseline_missing_feedback_reproduced=missing.get_width()==small.get_width()
	check(report.baseline_missing_feedback_reproduced,"world UV without STREAMING_LOD stays coarse even at near camera")
	shader.code=WORLD_SHADER.replace("// FEEDBACK",WORLD_FEEDBACK)
	check(await wait_for_bytes(image.get_data().size(),image.get_data().size(),15),"explicit world UV derivatives request full resolution")
	var fixed:=sample(texture,"world_uv_explicit_feedback")
	check(fixed.get_width()==image.get_width() and fixed.get_data()==image.get_data(),"full uploaded mip bytes match source")
	mesh.material_override=null;material.set_shader_parameter("source_texture",null)
	material=null;shader=null;texture=null;scene.queue_free()
	check(await wait_for_bytes(int(report.memory_before),int(report.memory_before),10),"final release returns accounting to baseline")
	report.memory_after=streaming.call("get_memory_budget_bytes_used")
	check(FileAccess.get_sha256(source)==report.source_sha256,"source input unchanged")
	finish()
