extends SceneTree
## Actual shadow-depth comparison; no author assets or screenshots are written.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Shadow=preload("res://scripts/world3d/building_shadow_proxy.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func capture(view:SubViewport)->PackedByteArray:
	for i:int in 8:await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image().get_data()
func maximum_error(a:PackedByteArray,b:PackedByteArray)->int:
	if a.size()!=b.size():return 256
	var error:=0
	for i:int in a.size():error=maxi(error,absi(int(a[i])-int(b[i])))
	return error
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	check(DisplayServer.get_name()!="headless","comparison uses the real GPU shadow map")
	var view:=SubViewport.new();view.size=Vector2i(512,512);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var scene:=Node3D.new();view.add_child(scene)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color(.3,.3,.3)
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.25
	environment.environment=settings;scene.add_child(environment)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=9
	scene.add_child(camera);camera.position=Vector3(6,7,8);camera.look_at(Vector3.ZERO);camera.current=true
	var light:=DirectionalLight3D.new();light.shadow_enabled=true;light.light_energy=1.4
	light.rotation_degrees=Vector3(-50,-30,0);scene.add_child(light)
	var floor:=MeshInstance3D.new();var slab:=BoxMesh.new();slab.size=Vector3(9,.2,9)
	var floor_material:=StandardMaterial3D.new();floor_material.albedo_color=Color(.65,.65,.65)
	slab.material=floor_material;floor.mesh=slab;floor.position.y=-.1;scene.add_child(floor)
	var cpu:=Cpu.new()
	for i:int in 3:
		var box:=BoxMesh.new();box.size=Vector3(1.,1.5,1.)
		var arrays:=box.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for at:int in vertices.size():vertices[at]+=Vector3((i-1)*1.5,.75,0)
		arrays[Mesh.ARRAY_VERTEX]=vertices;cpu.surfaces.append(arrays)
		var material:=StandardMaterial3D.new();material.albedo_color=Color(.5,.25,.1)
		if i==1:material.cull_mode=BaseMaterial3D.CULL_DISABLED
		cpu.materials.append(material)
	cpu.collision_faces()
	var visual:=MeshInstance3D.new();visual.mesh=cpu.restore()
	visual.set_meta("ground_batch_record",{"house_prefab":{},"building":{"id":"shadow-fixture"}});scene.add_child(visual)
	var native:PackedByteArray=await capture(view)
	Shadow.unshaded_materials_enabled=false;Shadow._materials.clear()
	check(Shadow.attach(visual),"three opaque surfaces produce two independent culling partitions")
	var legacy:PackedByteArray=await capture(view)
	var proxy:MeshInstance3D=visual.get_meta("building_shadow_proxy")
	check(maximum_error(native,legacy)<=1,"merged shadow retains the native multi-surface depth result")
	for i:int in proxy.mesh.get_surface_count():
		var old:StandardMaterial3D=proxy.mesh.surface_get_material(i)
		var unlit:=StandardMaterial3D.new();unlit.cull_mode=old.cull_mode;unlit.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		proxy.mesh.surface_set_material(i,unlit)
	var optimized:PackedByteArray=await capture(view)
	check(maximum_error(legacy,optimized)<=1,"unshaded shadow-only materials preserve the actual GPU shadow pixels")
	proxy.hide();var absent:PackedByteArray=await capture(view)
	check(maximum_error(optimized,absent)>20,"comparison actually covers visible cast shadows")
	view.free();Shadow._materials.clear();Shadow.unshaded_materials_enabled=true
	print("SHADOW_MATERIAL_EQUIVALENCE checks=",checks," failures=",failures);quit(1 if failures else 0)
