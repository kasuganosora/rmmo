extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const F=preload("res://scripts/world3d/building_fixtures.gd")
const P=preload("res://scripts/world3d/house_prefab.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const PATH="D:/code/rmmo_runtime/cache/world3d/interior_door_review/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/interior_timber_door"
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	if not ok:failures+=1;push_error(label_)
func settle()->void:
	await physics_frame;await physics_frame;await process_frame
func run()->void:
	create_timer(420).timeout.connect(func():quit(2))
	var doc=Doc.open_file(PATH);if doc==null:quit(1);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(1100,900);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.20,.23,.25);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;viewport.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,35,0);viewport.add_child(light)
	var camera:=Camera3D.new();camera.near=.05;camera.fov=62;viewport.add_child(camera)
	var tested:=0;var houses:=0
	for id:String in doc.map_meta.building_instances:
		var instance:Dictionary=doc.map_meta.building_instances[id];var plan:=B.generate(instance.parameters)
		check(plan.ok,"source plan");if not plan.ok:continue
		var yaw:=Basis(Vector3.UP,deg_to_rad(instance.yaw));var origin:=B.vec(instance.position)
		var isolated:=Doc.new();isolated.records=doc.records.filter(func(r):return r.get("building",{}).get("id")==id).duplicate(true)
		var host:=Node3D.new();viewport.add_child(host);var scene:=isolated.build();host.add_child(scene);Stream.sync(scene,host,origin)
		var body:=CharacterBody3D.new();var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=2.0;shape.shape=capsule;body.add_child(shape);host.add_child(body)
		await settle()
		for swap:Dictionary in plan.interior_door_replacements:
			var record:Dictionary=isolated.records.filter(func(r):return r.get("fixture",{}).get("id")==swap.id)[0]
			var closed:=Transform3D(Basis.from_euler(B.vec(record.rotation)*PI/180),B.vec(record.position))
			var inward:=yaw*B.vec(swap.inward);var leaf:Dictionary=swap.leaf
			var center:=origin+yaw*(B.vec(leaf.position)+Vector3(0,1.025-float(leaf.size[1])/2,0))
			var geometry:=P.geometry(record)
			check(geometry.mesh.collision_faces().size()==576*3 and geometry.mesh.get_surface_count()==2 and geometry.source.collision_faces().size()==36,"approved low-poly leaf "+swap.id)
			for fraction in [.25,.5,1.0]:
				var pose:=F.pose(closed,record.fixture,fraction)
				check((pose.origin-closed.origin).dot(inward)>.05,"door swings into room "+id+" "+swap.id)
				check((pose*B.vec(record.fixture.pivot)).distance_to(closed*B.vec(record.fixture.pivot))<.0001,"fixed hinge")
			for amount in [0.0,1.0]:
				check(F.set_runtime(scene,id,swap.id,amount,0).ok,"runtime state change")
				await settle()
				var start:=Transform3D(Basis.IDENTITY,center-inward*1.1);body.global_transform=start
				check(body.test_move(start,inward*2.2)==(amount==0),"closed blocks/open permits entry "+id+" "+swap.id+" "+str(amount))
				if amount==1:check(not body.test_move(Transform3D(Basis.IDENTITY,center+inward*1.1),-inward*2.2),"open permits exit "+id+" "+swap.id)
				if tested==0:
					body.position=Vector3(0,-100,0);camera.position=center-inward*3.0+Vector3(0,.6,0)+yaw*Vector3(.2,0,0);camera.look_at(center+Vector3(0,.12,0))
					for frame in 8:await process_frame
					await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(OUT+("/town_closed.png" if amount==0 else "/town_open.png"))
			tested+=1
		host.free();await settle();houses+=1;print("CHECKED_HOUSE ",houses," doors=",tested)
	var report:={"houses":houses,"doors":tested,"failures":failures,"candidate":FileAccess.get_sha256(PATH)}
	var file:=FileAccess.open(OUT+"/physical.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print("INTERIOR_PHYSICAL ",JSON.stringify(report));quit(1 if failures else 0)
