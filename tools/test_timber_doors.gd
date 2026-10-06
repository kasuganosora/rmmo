extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const F=preload("res://scripts/world3d/building_fixtures.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/timber_door"
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func settle()->void:
	await physics_frame;await physics_frame;await process_frame
func run()->void:
	create_timer(280).timeout.connect(func():quit(2))
	var path:="D:/code/rmmo_runtime/cache/world3d/timber_door_review/map.gltf"
	var doc=Doc.open_file(path)
	if doc==null:quit(1);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(1100,1000);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.38,.49,.61);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=.65;viewport.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.shadow_enabled=true;viewport.add_child(sun)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.fov=52
	var tested:=0
	for id:String in doc.map_meta.building_instances:
		var instance:Dictionary=doc.map_meta.building_instances[id];var doors:Array=doc.records.filter(func(r):return r.get("building",{}).get("id")==id and r.get("fixture",{}).get("id")=="f0/north/entrance/door")
		if doors.is_empty():continue
		var record:Dictionary=doors[0];var recipe:=B.generate(instance.parameters)
		var opening:Dictionary=recipe.openings.filter(func(o):return o.wall=="f0/north" and o.id=="entrance")[0]
		var yaw:=Basis(Vector3.UP,deg_to_rad(instance.yaw));var origin:=B.vec(instance.position)
		var center:Vector3=origin+yaw*Vector3(opening.u,opening.floor_y+1.1,opening.fixed)
		var inward:=yaw*Vector3.BACK
		var pivot:=F.transform(record)*B.vec(record.fixture.pivot)
		var closed:=Transform3D(Basis.from_euler(B.vec(record.rotation)*PI/180),B.vec(record.position))
		var moved:=F.pose(closed,record.fixture,1).origin-closed.origin
		check(moved.dot(inward)>.5,"entrance swings inward "+id)
		var isolated:=Doc.new();isolated.records=doc.records.filter(func(r):return r.get("building",{}).get("id")==id).duplicate(true)
		var host:=Node3D.new();viewport.add_child(host);var scene:=isolated.build();host.add_child(scene);Stream.sync(scene,host,center)
		var body:=CharacterBody3D.new();var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=2.1;shape.shape=capsule;body.add_child(shape);host.add_child(body)
		await settle()
		camera.position=center+yaw*Vector3(2,1.1,-5);camera.look_at(center)
		for amount in [0.0,1.0]:
			check(F.set_runtime(scene,id,record.fixture.id,amount,0).ok,"runtime hinge state")
			await settle()
			var start:=Transform3D(Basis.IDENTITY,center-inward*1.1)
			body.global_transform=start
			var blocked:=body.test_move(start,inward*2.2)
			check(blocked==(amount==0),"closed blocks / open clears capsule "+id+" "+str(amount))
			if amount==1:
				check(not body.test_move(Transform3D(Basis.IDENTITY,center+inward*1.1),-inward*2.2),"open leaf permits exit")
			if tested==0:
				for i in 6:await process_frame
				await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(OUT+("/house_closed.png" if amount==0 else "/house_open.png"))
		if tested==0:
			camera.position=center+yaw*Vector3(2,.6,3.5);camera.look_at(center)
			for i in 6:await process_frame
			await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(OUT+"/house_inside.png")
		host.free();await settle();tested+=1
	check(tested==24,"all 24 town entrances physically checked")
	var result:={"houses":tested,"failures":failures,"candidate":FileAccess.get_sha256(path)}
	var file:=FileAccess.open(OUT+"/physical.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("TIMBER_DOOR_PHYSICAL ",JSON.stringify(result));quit(1 if failures else 0)
