extends SceneTree
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
var failures:=0
var comparisons:Array=[]
var output:="D:/code/rmmo_runtime/review_artifacts/wind_cutout_20261018/wind_%d"%Time.get_ticks_usec()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func grid()->ArrayMesh:
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uv:=PackedVector2Array();var indices:=PackedInt32Array()
	for y in 25:
		for x in 17:
			vertices.append(Vector3(float(x)/16*1.5,float(y)/24*2.5,0));normals.append(Vector3.BACK);uv.append(Vector2(float(x)/16,float(y)/24))
	for y in 24:
		for x in 16:
			var i:=y*17+x;indices.append_array(PackedInt32Array([i,i+17,i+1,i+1,i+17,i+18]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh
func make_world()->Dictionary:
	var view:=SubViewport.new();view.size=Vector2i(640,480);view.own_world_3d=true;view.use_taa=false;view.msaa_3d=Viewport.MSAA_DISABLED;view.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var scene:=Node3D.new();view.add_child(scene)
	var camera:=Camera3D.new();camera.position=Vector3(2.8,2.5,11);scene.add_child(camera);camera.look_at(Vector3(2.8,1.1,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=7;camera.current=true
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.08,.09,.12);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.45;scene.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.shadow_enabled=true;scene.add_child(sun)
	var wind:=Runtime.new();scene.add_child(wind);wind.camera=camera;wind.set_physics_process(false)
	var nodes:Array=[]
	for i in 4:
		var node:=MeshInstance3D.new();node.mesh=grid();node.position=Vector3((i%2)*3,(i/2)*2.2-1,0);node.scale=Vector3(.75,.7,1.3);node.rotation_degrees=Vector3(0,18*(i%2),-5*(i/2))
		var material:=StandardMaterial3D.new();material.albedo_color=[Color(.8,.12,.05),Color(.1,.6,.15),Color(.1,.25,.85),Color(.65,.45,.08)][i];material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.roughness=.65
		if i==1:
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;material.backlight_enabled=true;material.backlight=Color(.1,.2,.1)
		node.mesh.surface_set_material(0,material)
		node.set_meta("extras",{"rmmo_wind":{"profile":"foliage" if i==1 else "cloth","anchor":["bottom","top","left","right"][i],"amplitude":.9,"stiffness":.2,"shelter":true}})
		scene.add_child(node);Response.register(node);nodes.append(node)
	var floor_node:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(12,.2,6);floor_node.mesh=box;floor_node.position=Vector3(2,-1.2,0);scene.add_child(floor_node)
	wind.refresh()
	return {"view":view,"scene":scene,"camera":camera,"wind":wind,"nodes":nodes}
func shot(world:Dictionary,frames:int=3)->Image:
	for i in frames:await process_frame;await RenderingServer.frame_post_draw
	return world.view.get_texture().get_image()
func difference(a:Image,b:Image)->Dictionary:
	var aa:=a.get_data();var bb:=b.get_data();var changed:=0;var maximum:=0;var total:=0
	for i in aa.size():
		var delta:=absi(int(aa[i])-int(bb[i]));maximum=maxi(maximum,delta);total+=delta
		if delta>2:changed+=1
	return {"max_channel_delta":maximum,"mean_channel_delta":float(total)/aa.size(),"changed_channel_fraction":float(changed)/aa.size()}
func compare(world:Dictionary,velocity:Vector3,time:float,label:String)->Image:
	world.wind.set_shared_state_enabled(false);world.wind.advance(velocity,time)
	var legacy:=await shot(world)
	world.wind.set_shared_state_enabled(true);world.wind.advance(velocity,time)
	var shared:=await shot(world)
	var result:=difference(legacy,shared);result.label=label;comparisons.append(result)
	check(result.mean_channel_delta<.02 and result.changed_channel_fraction<.0001,"same camera/time legacy vs shared "+label+" "+str(result))
	legacy.save_png(output.path_join(label+"_legacy.png"));shared.save_png(output.path_join(label+"_shared.png"))
	return shared
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	create_timer(150).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute(output)
	var Materials=preload("res://scripts/world3d/wind_material.gd")
	var reference:=make_world()
	var candidate:=make_world()
	await shot(reference,12);await shot(candidate,12)
	candidate.wind.set_enabled(false);candidate.wind.set_enabled(true);candidate.wind.set_physics_process(false)
	Materials.shaders.clear();candidate.wind.cached_variants_only=true
	var gate:=Semaphore.new();Materials.preparation_test_gate=gate
	candidate.wind.refresh()
	check(candidate.wind.capability_status().pending_receivers==4 and candidate.wind.receivers.is_empty(),"unseen variants preserve entire authored rows before background completion")
	await shot(candidate,4)
	check(not candidate.view.disable_3d and candidate.view.find_child("TransferLoading",true,false)==null,"unprepared wind keeps real GPU frames visible without a cover")
	var before:=Time.get_ticks_usec();Materials.preparation_test_gate=null;gate.post()
	var until:=Time.get_ticks_msec()+60000
	while not candidate.wind.capability_status().ready and Time.get_ticks_msec()<until:
		candidate.wind._physics_process(.36);await process_frame
	var status:Dictionary=candidate.wind.capability_status()
	check(status.ready and status.ready_receivers==4 and status.pending_receivers==0,"background preparation drains unseen variants and binds every receiver")
	check(Materials.background_profile().completed==2 and Materials.background_profile().main_thread_builds==0,"duplicate keys prepare once on the worker")
	var convergence_ms:float=(Time.get_ticks_usec()-before)/1000.

	for view:Dictionary in [{"label":"detail","z":4.,"size":4.},{"label":"near","z":11.,"size":7.},{"label":"mid","z":30.,"size":14.},{"label":"far","z":70.,"size":30.}]:
		for world:Dictionary in [reference,candidate]:world.camera.position.z=view.z;world.camera.size=view.size
		for t:float in [1.,1.75]:
			reference.wind.advance(Vector3(12,0,2),t);candidate.wind.advance(Vector3(12,0,2),t)
			var a:=await shot(reference);var b:=await shot(candidate)
			var result:=difference(a,b);result.label=view.label+"_"+str(t);comparisons.append(result)
			check(result.mean_channel_delta<.02 and result.changed_channel_fraction<.0001,"background cache vs synchronous material, fixed camera/light/time "+result.label+" "+str(result))
			a.save_png(output.path_join(result.label+"_reference.png"));b.save_png(output.path_join(result.label+"_background.png"))
	# A receiver that arrives after entry with a genuinely different key.
	var late:=MeshInstance3D.new();late.mesh=grid();var source:=StandardMaterial3D.new();source.texture_repeat=false;source.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	late.mesh.surface_set_material(0,source);late.set_meta("extras",{"rmmo_wind":{"profile":"foliage","shelter":false}});candidate.scene.add_child(late);Response.register(late)
	candidate.wind.refresh();check(candidate.wind.capability_status().pending_receivers==1,"post-entry stream arrival advertises real pending variant")
	until=Time.get_ticks_msec()+60000
	while not candidate.wind.capability_status().ready and Time.get_ticks_msec()<until:
		candidate.wind._physics_process(.36);await process_frame
	check(candidate.view.find_child("TransferLoading",true,false)==null and not candidate.view.disable_3d,"post-entry unseen material completes without covering or disabling the viewport")
	check(candidate.wind.receivers.has(late.get_instance_id()) and candidate.wind.capability_status().ready,"post-entry material acquires wind automatically")
	var result:={"failures":failures,"media":output,"comparisons":comparisons,"background":status,"convergence_ms":convergence_ms}
	FileAccess.open("D:/code/rmmo_runtime/review_artifacts/wind_cutout_20261018/wind_gpu.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	reference.view.free();candidate.view.free();await process_frame
	print("WIND_BACKGROUND_GPU_FAILURES ",failures," report=",result);quit(1 if failures else 0)
