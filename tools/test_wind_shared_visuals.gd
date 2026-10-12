extends SceneTree
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
var failures:=0
var comparisons:Array=[]
var output:="D:/code/rmmo_runtime/review_artifacts/wind_shared_state_20261007"
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
	if DisplayServer.get_name()=="headless":push_error("Requires private-desktop GPU runner");quit(2);return
	create_timer(120).timeout.connect(func():push_error("wind shared GPU timeout");quit(2))
	DirAccess.make_dir_recursive_absolute(output)
	var a:=make_world();var b:=make_world();b.wind.set_shared_state_enabled(true);b.wind.advance(Vector3(-5,0,3),40)
	var b_before:=await shot(b)
	var calm:=await compare(a,Vector3.ZERO,1,"calm")
	var right:=await compare(a,Vector3(12,0,2),1,"right")
	var later:=await compare(a,Vector3(12,0,2),1.75,"later")
	check(difference(calm,right).changed_channel_fraction>.002 and difference(right,later).changed_channel_fraction>.002,"wind deformation and motion remain visibly present")
	await compare(a,Vector3(-10,1,0),4,"reverse")
	# The very next submitted frame must see a new texel, not a frame-old state.
	a.wind.set_shared_state_enabled(false);a.wind.advance(Vector3(7,0,-2),12.25);var expected:=await shot(a)
	a.wind.set_shared_state_enabled(true);a.wind.advance(Vector3.ZERO,0);await shot(a)
	a.wind.advance(Vector3(7,0,-2),12.25);var next_frame:=await shot(a,1)
	var immediate:=difference(expected,next_frame);comparisons.append(immediate.merged({"label":"first_frame_update"}))
	check(immediate.mean_channel_delta<.02 and immediate.changed_channel_fraction<.0001,"shared update reaches next rendered frame "+str(immediate))
	var paused:=await shot(a,5);check(difference(paused,next_frame).max_channel_delta==0,"paused explicit clock stays visually stationary")
	var roof:=StaticBody3D.new();roof.position=Vector3(.5,5,0);a.scene.add_child(roof)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,.2,2);collision.shape=box;roof.add_child(collision)
	await physics_frame;await physics_frame;a.wind.refresh();await compare(a,Vector3(12,0,0),3,"shelter")
	roof.free();await physics_frame;a.wind.refresh()
	for node:MeshInstance3D in a.nodes:node.visibility_range_end=5
	a.camera.position.z=25;a.wind.refresh();a.wind.advance(Vector3(9,0,0),5);await shot(a)
	a.camera.position.z=4;await compare(a,Vector3(9,0,0),6,"lod_reentry")
	var b_after:=await shot(b);check(difference(b_before,b_after).max_channel_delta==0,"another world keeps its original time and wind throughout A/B changes")
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"comparisons":comparisons},"\t"));file.close()
	a.view.free();b.view.free();print("WIND_SHARED_VISUAL_FAILURES ",failures);quit(1 if failures else 0)
