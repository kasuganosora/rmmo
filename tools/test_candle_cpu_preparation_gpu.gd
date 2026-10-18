extends SceneTree
const Sconce=preload("res://scripts/world3d/candle_sconce_mesh.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func material_values(value:Material)->Array:
	return [value.albedo_color,value.metallic,value.roughness,value.cull_mode,value.transparency,value.shading_mode]
func reference_mesh(record:Dictionary)->ArrayMesh:
	# Portable copy of the original GPU builder, using the unchanged authored
	# data. The external frozen script is optional, never a test dependency.
	var result:=ArrayMesh.new();var original_arrays:Array=[]
	var scale_:Vector3=Vector3(record.size[0],record.size[1],record.size[2])/Sconce.SIZE
	for slot:int in Sconce.DATA.surfaces.size():
		var surface:Dictionary=Sconce.DATA.surfaces[slot]
		var material:=StandardMaterial3D.new()
		material.albedo_color=[Color(.095,.079,.064),Color(.82,.68,.38),Color(.022,.013,.008)][slot]
		material.metallic=.78 if slot==0 else 0.;material.roughness=.52 if slot==0 else .79
		for start:int in range(0,surface.triangles.size(),120):
			var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES);builder.set_material(material)
			for at:int in range(start,mini(start+120,surface.triangles.size())):
				for index:int in surface.triangles[at]:
					var vertex:Array=surface.vertices[index];var point:=Vector3(vertex[0],vertex[1],vertex[2])*scale_
					builder.set_uv(Vector2(point.x,point.y));builder.add_vertex(point)
			builder.generate_normals();builder.generate_tangents()
			var arrays:Array=builder.commit_to_arrays();original_arrays.append(arrays)
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(result.get_surface_count()-1,material)
	Cpu.remember(result,original_arrays)
	return result
func run()->void:
	create_timer(100).timeout.connect(func():quit(2))
	var legacy_path:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/candle_sconce_mesh_before_cpu.gd"
	var legacy:Script=load(legacy_path) if "--frozen-reference" in OS.get_cmdline_user_args() and FileAccess.file_exists(legacy_path) else null
	var record:Dictionary={"uuid":"sconce","kind":"box","surface_id":"block","collision":"none","building_shape":"candle_sconce","building":{"id":"house","role":"light_sconce","floor":0,"part":"wall/candle","floor_y":0.},"size":[.26,.54,.46],"position":[0,0,0],"rotation":[0,0,0],"color":[.2,.3,.4]}
	var began:=Time.get_ticks_usec();var prepared:Mesh=Sconce.cpu_mesh(record)
	print("CANDLE_CPU_PREPARE_US ",Time.get_ticks_usec()-began)
	var expected:Mesh=legacy.mesh(record) if legacy!=null else reference_mesh(record);var reference:Mesh=Cpu.capture(expected)
	check(prepared.surfaces==reference.surfaces and prepared.get_aabb().is_equal_approx(expected.get_aabb()),"authored positions/normals/tangents/UV/index channels and bounds match the previous actual GPU mesh")
	check(prepared.collision_faces()==reference.collision_faces(),"every original triangle and winding remains exact")
	var equal:=prepared.get_surface_count()==expected.get_surface_count()
	for slot:int in prepared.get_surface_count():equal=equal and material_values(prepared.surface_get_material(slot))==material_values(expected.surface_get_material(slot))
	check(equal,"iron, wax and wick retain every material value and independent paint surface")
	check(Sconce.cpu_mesh(record)==prepared,"simultaneously live same-size components share their immutable CPU descriptor")
	var document:=Doc.new();document.load_immutable_records=true
	var node:MeshInstance3D=document._mesh(record)
	check(node.mesh is Cpu and node.mesh==prepared and node.get_meta("extras").building.role=="light_sconce","actual immutable document route uses CPU data and preserves light/room semantics")
	node.free()
	var gpu:Mesh=prepared.restore()
	check(Cpu.capture(gpu).surfaces==reference.surfaces,"actual GPU restoration preserves every channel and original paint granularity")
	var viewport:=SubViewport.new();viewport.size=Vector2i(160,160);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.8;camera.position=Vector3(.8,.3,1.2);world.add_child(camera);camera.look_at(Vector3(0,0,.02))
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color(.15,.17,.2);settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.6;environment.environment=settings;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);world.add_child(light)
	var visual:=MeshInstance3D.new();visual.mesh=expected;world.add_child(visual)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var original_image:Image=viewport.get_texture().get_image()
	visual.mesh=gpu
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var new_image:Image=viewport.get_texture().get_image();var max_error:=0.
	for y:int in new_image.get_height():
		for x:int in new_image.get_width():
			var a:=original_image.get_pixel(x,y);var b:=new_image.get_pixel(x,y)
			max_error=maxf(max_error,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
	check(max_error<=1./255.,"same GPU camera/light/exposure gives equivalent rendered pixels")
	visual.mesh=null;viewport.free();RenderingServer.force_sync()
	var cpu_watch:WeakRef=weakref(prepared);var gpu_watch:WeakRef=weakref(gpu);var material_watch:WeakRef=weakref(prepared.materials[0])
	prepared=null;gpu=null;RenderingServer.force_sync();await process_frame
	check(cpu_watch.get_ref()==null and gpu_watch.get_ref()==null and material_watch.get_ref()==null,"weak memo tables retain no CPU descriptor, GPU mesh or material after the last owner leaves")
	var editable:Mesh=Sconce.mesh(record);var editable_watch:WeakRef=weakref(editable)
	check(editable is ArrayMesh and Sconce.mesh(record)==editable,"editor/shared GPU operation still reuses the same live mesh")
	editable=null;RenderingServer.force_sync();await process_frame
	check(editable_watch.get_ref()==null,"editor GPU cache also releases its final owner")
	if legacy!=null:legacy._meshes.clear()
	reference=null;expected=null
	print("CANDLE_CPU_PREPARATION checks=",checks," failures=",failures);quit(1 if failures else 0)
