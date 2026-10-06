extends SceneTree
const Layout=preload("res://scripts/world3d/house_candle_layout.gd")
const MeshSource=preload("res://scripts/world3d/candle_sconce_mesh.gd")
const Lights=preload("res://scripts/world3d/house_candle_lights.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/candle_sconce"
var failed:=0
func check(ok:bool,label:String)->void:
	if ok:print("PASS: ",label)
	else:failed+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var total:=0
	for preset in Blueprint.medieval_presets():
		var plan:Dictionary=Blueprint.generate(preset.parameters)
		check(plan.get("ok",false),preset.id+" plan")
		if not plan.get("ok",false):continue
		if not plan.records.any(func(r):return r.get("building_shape")=="candle_sconce"):Layout.add_to_plan(plan)
		var lamps:Array=plan.records.filter(func(r):return r.get("building_shape")=="candle_sconce")
		var cloth:Array=plan.records.filter(func(r):return r.building.role=="curtain")
		check(lamps.size()>0,preset.id+" has wall candles")
		check(lamps.size()==plan.rooms.size(),preset.id+" every room receives one candle")
		for lamp in lamps:
			total+=1;check(MeshSource.valid(JSON.parse_string(JSON.stringify(lamp))),lamp.uuid+" JSON valid")
			var safe:=true
			for c in cloth:
				if Layout.distance(Layout.bounds(lamp),Layout.bounds(c))<1.0:safe=false
			check(safe,lamp.uuid+" >=1m from all curtain bounds")
			check(float(lamp.position[1])-float(lamp.building.floor_y)>=2.14,lamp.uuid+" above walking headroom")
			var pose:=Transform3D(Basis.from_euler(Layout.v(lamp.rotation)*PI/180.0),Layout.v(lamp.position))
			var contact:Vector3=pose*Vector3(0,0,-.21)
			check(plan.records.any(func(r):return r.get("building_shape")=="wall_grid" and Layout.bounds(r).grow(.006).has_point(contact)),lamp.uuid+" backplate physically meets a wall")
		print("LAYOUT ",preset.id," lamps=",lamps.size()," rooms=",plan.rooms.size())
	var record:Dictionary={"uuid":"test_wall_candle","size":[.26,.54,.46],"position":[0,2.15,.205],"rotation":[0,0,0],"collision":"none","building_shape":"candle_sconce","building":{"role":"light_sconce"}}
	var mesh:=MeshSource.mesh(record)
	check(mesh.get_faces().size()/3==304,"actual Blender-exported 304 triangles")
	var sane:=true
	for face in range(0,mesh.get_faces().size(),3):
		var faces:=mesh.get_faces()
		if (faces[face+1]-faces[face]).cross(faces[face+2]-faces[face]).length()<.00000001:sane=false
	check(sane,"no degenerate mesh faces")
	for hour in [0.0,5.99,20.0,23.99]:check(Lights.is_night(hour),"night "+str(hour))
	for hour in [6.0,12.0,17.0,19.99]:check(not Lights.is_night(hour),"day/dusk off "+str(hour))
	var scene:=Node3D.new();root.add_child(scene)
	var records:Array=[]
	for i in 12:
		var r:Dictionary=record.duplicate(true);r.uuid="lamp%d"%i;r.position[0]=i*.3;records.append(r)
	scene.set_meta("extras",{"rmmo_records":records})
	var controller:=Lights.new();root.add_child(controller);controller.bind_map(scene)
	controller.set_hours(0);check(controller.lit_count()==Lights.MAX_LIGHTS,"night shadow light budget capped at two")
	controller.set_hours(12);check(controller.lit_count()==0 and controller.fixtures.all(func(f):return not f.effect.visible),"daytime flame and light both off")
	scene.set_meta("stream_meshes",{});controller.set_hours(0);check(controller.lit_count()==0,"unloaded fixtures cannot emit")
	var source:=MeshInstance3D.new();source.name="lamp0";source.mesh=mesh;scene.add_child(source);source.position=Vector3(0,2.15,.205)
	scene.set_meta("stream_meshes",{"lamp0":source});controller.refresh();check(controller.lit_count()==1,"loaded fixture emits")
	source.visible=false;controller.refresh();check(controller.lit_count()==0,"floor visibility hides its candle light")
	source.visible=true;source.position.x=3;controller.refresh();check(is_equal_approx(controller.fixtures[0].effect.global_position.x,3.0),"candle follows moved fixture")
	source.free();controller.refresh();check(controller.lit_count()==0,"freed source in stale stream dictionary emits no light or crash")
	for cycle in 12:
		var replacement:=MeshInstance3D.new();replacement.mesh=mesh;scene.add_child(replacement);scene.set_meta("stream_meshes",{"lamp0":replacement})
		controller.refresh();check(controller.lit_count()==1,"stream return "+str(cycle));replacement.free();controller.refresh()
	controller.bind_map(scene);controller.set_hours(0);check(controller.lit_count()==0,"rebinding with stale unloaded source is safe")
	scene.free();controller.refresh();check(controller.lit_count()==0,"freed map hides all lights safely")
	controller.free()
	await priority_test(record)
	if "--preview" in OS.get_cmdline_user_args():await preview(record,mesh)
	print("HOUSE_CANDLES_RESULT failures=",failed," authored_lamps=",total);quit(1 if failed else 0)
func priority_test(record:Dictionary)->void:
	var scene:=Node3D.new();root.add_child(scene);var records:Array=[]
	var positions:Array=[Vector3(2,2.15,0),Vector3(-3,2.15,0),Vector3(-4,2.15,0),Vector3(0,6.15,0)]
	for i in positions.size():
		var r:Dictionary=record.duplicate(true);r.uuid="priority%d"%i;r.position=[positions[i].x,positions[i].y,positions[i].z];r.building.floor_y=positions[i].y-2.15;records.append(r)
	scene.set_meta("extras",{"rmmo_records":records})
	var observer:=Node3D.new();scene.add_child(observer)
	var wall:=StaticBody3D.new();scene.add_child(wall);wall.position=Vector3(1,2,0)
	var collision:=CollisionShape3D.new();collision.shape=BoxShape3D.new();collision.shape.size=Vector3(.2,4,10);wall.add_child(collision)
	for i in 2:await physics_frame
	var weather:=preload("res://scripts/world3d/weather_controller.gd").new();weather.values={"time_hours":0.0}
	var controller:=Lights.new();scene.add_child(controller);controller.bind_map(scene,observer,weather)
	check(controller.lit_count()==2,"binding reads existing night clock immediately")
	check(controller.fixtures[1].light.visible and controller.fixtures[2].light.visible and not controller.fixtures[0].light.visible and not controller.fixtures[3].light.visible,"same-room lights win over nearer candles through wall or upper floor")
	observer.position.x=2.6;controller.refresh();check(controller.fixtures[0].light.visible,"crossing doorway selects the newly occupied room")
	weather.free();scene.free()
func add_box(parent:Node,p:Vector3,size:Vector3,color:Color)->void:
	var n:=MeshInstance3D.new();var b:=BoxMesh.new();b.size=size;n.mesh=b;n.position=p
	var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=.9;b.material=m;parent.add_child(n)
func preview(record:Dictionary,mesh:Mesh)->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var viewport:=SubViewport.new();viewport.size=Vector2i(1000,1000);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
	var scene:=Node3D.new();viewport.add_child(scene);scene.set_meta("extras",{"rmmo_records":[record]})
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.13,.14,.15);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.55,.60,.68);env.environment.ambient_light_energy=.5;viewport.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-30,0);sun.shadow_enabled=true;sun.light_energy=1.2;viewport.add_child(sun)
	var fixture:=MeshInstance3D.new();fixture.mesh=mesh;fixture.position=Vector3(0,2.15,.205);scene.add_child(fixture)
	add_box(scene,Vector3(0,1.8,-.08),Vector3(2.2,2.0,.16),Color(.72,.66,.54))
	var observer:=Node3D.new();scene.add_child(observer);observer.position=Vector3(.8,2.4,1.4)
	var controller:=Lights.new();scene.add_child(controller);controller.bind_map(scene,observer)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.position=observer.position;camera.look_at(Vector3(0,2.15,.20));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.0
	for mode in ["day","night"]:
		controller.set_hours(12 if mode=="day" else 0);sun.light_energy=1.2 if mode=="day" else .015;env.environment.ambient_light_energy=.5 if mode=="day" else .04
		for frame in 8:await process_frame
		await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(OUT.path_join(mode+".png"))
