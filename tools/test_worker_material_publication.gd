extends SceneTree
## GPU contract for private worker construction before first material publication.
## Use the private-desktop runner; pixel readback is validation, never a benchmark.
const Presented=preload("res://scripts/util/frame_presentation.gd")
const CODE="shader_type spatial; render_mode unshaded,cull_disabled; uniform vec4 test_color:source_color=vec4(1.,0.,0.,1.); void fragment(){ ALBEDO=test_color.rgb; }"
var failures:Array=[]
var checks:=0
var output:=""
var stage:Node3D
var visual:MeshInstance3D
var packed:Dictionary
var colors:Array=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func build(shared:Shader=null,standard:bool=false)->Dictionary:
	var material:Material
	var shader:Shader=shared
	if standard:
		var value:=StandardMaterial3D.new();value.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;value.albedo_color=Color.RED;material=value
	else:
		if shader==null:shader=Shader.new();shader.code=CODE
		var value:=ShaderMaterial.new();value.shader=shader;value.set_shader_parameter("test_color",Color.RED);material=value
	var surface:=packed.duplicate();surface.material=material
	var mesh:=ArrayMesh.new();mesh.set("_surfaces",[surface])
	return {"mesh":mesh,"material":material,"shader":shader,"thread":OS.get_thread_caller_id()}

func worker_build(shared:Shader=null,standard:bool=false)->Dictionary:
	var worker:=Thread.new()
	var error:=worker.start(build.bind(shared,standard))
	check(error==OK,"private material worker starts")
	if error!=OK:return {}
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	check(result.thread!=OS.get_main_thread_id(),"native material and mesh constructed off main thread")
	return result

func pixel(expected:Color,label:String)->void:
	await Presented.drawn()
	var image:=root.get_texture().get_image()
	var actual:=image.get_pixel(image.get_width()/2,image.get_height()/2)
	colors.append({"label":label,"actual":[actual.r,actual.g,actual.b],"expected":[expected.r,expected.g,expected.b]})
	check(absf(actual.r-expected.r)<.08 and absf(actual.g-expected.g)<.08 and absf(actual.b-expected.b)<.08,label)

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/") or DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(256,256);root.content_scale_size=root.size
	stage=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,3);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3;stage.add_child(camera);camera.current=true
	visual=MeshInstance3D.new();stage.add_child(visual)
	var quad:=QuadMesh.new();quad.size=Vector2(2,2)
	packed=RenderingServer.call("mesh_prepare_surface_from_arrays",Mesh.PRIMITIVE_TRIANGLES,quad.surface_get_arrays(0),[],{},0)
	var packet:=await worker_build()
	visual.mesh=packet.mesh
	check(visual.mesh.surface_get_material(0)==packet.material,"exact worker material reaches first mesh publication")
	await pixel(Color.RED,"first rendered frame includes initial worker parameters")
	packet.material.set_shader_parameter("test_color",Color.GREEN)
	await pixel(Color.GREEN,"next frame includes live uniform edit")
	packet.shader.code=CODE.replace("test_color.rgb","vec3(0.,0.,1.)")
	await pixel(Color.BLUE,"live shader replacement remains complete on first affected draw")
	var shared:Shader=packet.shader
	var other:=await worker_build(shared)
	check(other.shader==shared and other.material!=packet.material,"shared shader preserves distinct material ownership")
	visual.mesh=other.mesh
	await pixel(Color.BLUE,"shared compiled shader publishes correct first frame")
	var unused:=await worker_build()
	var unused_mesh:WeakRef=weakref(unused.mesh);var unused_material:WeakRef=weakref(unused.material)
	unused={}
	check(unused_mesh.get_ref()==null and unused_material.get_ref()==null,"cancelled unpublished mesh and material owners release")
	await pixel(Color.BLUE,"cancelled private publication does not disturb live material")
	visual.mesh=null;packet={};other={};shared=null
	var returned:=await worker_build(null,true)
	visual.mesh=returned.mesh
	await pixel(Color.RED,"rebuilt standard material renders after prior owners retire")
	returned.material.albedo_color=Color.GREEN
	await pixel(Color.GREEN,"standard material parameter edit remains immediate")
	stage.free();packet={};other={};returned={}
	await process_frame
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"colors":colors},"\t"))
	quit(0 if failures.is_empty() else 1)
