extends SceneTree
## Actual RiverMaterials -> GroundBatchGeometry integration in an isolated copy.
const River=preload("res://scripts/world3d/river_materials.gd")
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Variants=preload("res://scripts/world3d/streaming_surface_shader.gd")
var checks:=0
var failures:Array[String]=[]
var output:=""
var legacy:=false
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9)
		elif arg=="--legacy-shader":legacy=true
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func capture()->Image:
	for i:int in 8:await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	Engine.max_fps=60
	# Exact-pixel comparisons require a fixed projection. The full project has
	# TAA enabled: successive jitter phases differ even with unchanged geometry.
	root.use_taa=false
	root.size=Vector2i(1280,960)
	root.mode=Window.MODE_WINDOWED
	check(not output.is_empty(),"external result path")
	check(Variants.enabled() if Engine.get_version_info().minor>=8 else not Variants.enabled(),"engine selects supported shader path")
	var definition:={"name":"fixture","color":[.3,.5,.2,1.],"roughness":.9,"tile_size":[2.,2.],"normal_strength":0.}
	var record:={"kind":"box","size":[2.,1.,2.],"terrain_mesh":{"version":1,"columns":1,"rows":1,"floor":-1.,"heights":[0.,0.,0.,0.],"holes":[false]},"terrain_material":definition}
	var original:=var_to_bytes(record)
	var material:=River.terrain(record)
	check(material.shader==Variants.terrain(),"normal material construction selects the shared streaming shader")
	if legacy:material.shader=Variants.TERRAIN
	var parameters:Dictionary={}
	for row:Dictionary in material.shader.get_shader_uniform_list():parameters[row.name]=material.get_shader_parameter(row.name)
	var key:=Geometry.material_key(material)
	check(not key.is_empty(),"actual batch key accepts streaming terrain")
	var equivalent:=material.duplicate() as ShaderMaterial
	var parameter_changes:Array=[]
	for row:Dictionary in material.shader.get_shader_uniform_list():
		var actual:Variant=equivalent.get_shader_parameter(row.name)
		if parameters.get(row.name)!=actual:parameter_changes.append({"name":row.name,"before":str(parameters.get(row.name)),"after":str(actual)})
	check(Geometry.material_key(equivalent)==key,"equivalent materials keep the same batch key")
	check(Geometry.material_key(material)==key,"Inspector default population leaves original key stable")
	equivalent.set_shader_parameter("region_a_color",Color(.8,.1,.2,1.))
	check(Geometry.material_key(equivalent)==key,"disabled region parameters remain irrelevant")
	equivalent.set_shader_parameter("ground_enabled",true)
	check(Geometry.material_key(equivalent)!=key,"enabling a region changes the batch key")
	equivalent.set_shader_parameter("ground_enabled",false)
	equivalent.set_shader_parameter("base_color",Color(.8,.1,.2,1.))
	check(Geometry.material_key(equivalent)!=key,"different appearance still splits batches")
	var scene:=Node3D.new();root.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.03,.04,.05)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1.
	scene.add_child(environment)
	var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(1,3,4);camera.look_at(Vector3(1,0,0));camera.current=true
	var surfaces:Array=Terrain.arrays(record)
	var saved:=var_to_bytes(surfaces)
	var members:Array=[];var nodes:Array[MeshInstance3D]=[]
	for x:int in 2:
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surfaces[0]);mesh.surface_set_material(0,material)
		var node:=MeshInstance3D.new();node.mesh=mesh;scene.add_child(node);node.position.x=x*2.
		nodes.append(node)
		members.append({"record":record,"transform":node.transform,"surfaces":[surfaces[0]],"materials":[material],"keys":[key]})
	var before:=await capture()
	var unchanged:=await capture()
	check(before.get_data()==unchanged.get_data(),"unchanged scene is pixel deterministic before batching")
	var packet:=Geometry.build(members,Vector3.ZERO)
	check(not packet.is_empty() and packet.source_surfaces==2,"real batch builder processes both independent sources")
	check(packet.mesh.get_surface_count()==1,"two source surfaces become one render surface")
	var combined:=MeshInstance3D.new();combined.mesh=packet.mesh;scene.add_child(combined)
	for node in nodes:node.visible=false
	var combined_material:ShaderMaterial=packet.mesh.surface_get_material(0)
	check(combined_material.shader==(Variants.TERRAIN if legacy else Variants.terrain()) and combined_material.get_shader_parameter("batch_enabled"),"published layered batch retains selected variant")
	var after:=await capture()
	before.save_png(output.get_base_dir().path_join("before.png"));after.save_png(output.get_base_dir().path_join("after.png"))
	check(after.get_data()==before.get_data(),"combined terrain preserves exact same-camera pixels")
	check(var_to_bytes(record)==original and var_to_bytes(surfaces)==saved,"authoring record and source geometry remain unchanged")
	var shader:=material.shader
	var default_material:=ShaderMaterial.new();default_material.shader=shader
	var default_key:=Geometry.material_key(default_material)
	var original_code:=shader.code
	shader.code=original_code.replace("uniform float wet_height = .3;","uniform float wet_height = .8;")
	check(shader.code!=original_code and Geometry.material_key(default_material)!=default_key,"shader edit invalidates cached native defaults")
	shader.code=original_code
	check(Geometry.material_key(default_material)==default_key,"restored shader defaults reproduce original key")
	scene.queue_free();River.cache.clear()
	var report:={"checks":checks,"failures":failures,"parameter_changes":parameter_changes,"legacy_shader":legacy,"engine":Engine.get_version_info(),"scope":"actual surface material construction and derived terrain batching; no production map write"}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	quit(0 if failures.is_empty() else 1)
