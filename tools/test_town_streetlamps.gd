extends SceneTree
const Author=preload("res://tools/place_town_streetlamps.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Wind=preload("res://scripts/world3d/wind_runtime.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func mark(stage:String)->void:
	var f:=FileAccess.open(Author.OUT+"/progress.txt",FileAccess.WRITE);f.store_string(stage);f.close();print(stage)
func check(ok:bool,label_:String)->void:
	if not ok:failures+=1;push_error(label_)
func settle()->void:
	await physics_frame;await physics_frame;await process_frame
func run()->void:
	create_timer(420).timeout.connect(func():quit(2))
	mark("opening candidate")
	var doc=Doc.open_file(Author.TARGET)
	mark("candidate opened; selecting district")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Author.OUT+"/placement.json"))
	var subset:=Doc.new();subset.map_meta=doc.map_meta.duplicate(true)
	var area:=AABB(Vector3(-365,-10,-115),Vector3(230,90,185))
	subset.records=doc.records.filter(func(r):return Geometry.bounds([r]).intersects(area)).duplicate(true)
	mark("district selected: "+str(subset.records.size()))
	var view:=SubViewport.new();view.size=Vector2i(1440,900);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var host:=Node3D.new();view.add_child(host)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.48,.65,.79);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.9,.94,1);env.environment.ambient_light_energy=.65;view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-30,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=130;view.add_child(sun)
	var camera:=Camera3D.new();camera.near=.08;camera.far=550;camera.fov=65;view.add_child(camera)
	var scene:=subset.build();host.add_child(scene)
	mark("district built")
	var body:=CharacterBody3D.new();var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collision.shape=capsule;body.add_child(collision);host.add_child(body)
	var wind:=Wind.new();wind.camera=camera;host.add_child(wind)
	var count:=0;var wind_ids:Dictionary={}
	for lamp:Dictionary in report.lamps:
		var at:=B.vec(lamp.position);var basis:=Basis(Vector3.UP,deg_to_rad(lamp.yaw))
		var house:Dictionary=doc.map_meta.building_instances[lamp.house];var origin:=B.vec(house.position)
		var house_basis:=Basis(Vector3.UP,deg_to_rad(house.yaw))
		camera.position=at+basis*Vector3(1,2,-3)
		Stream.sync(scene,host,at);await settle()
		# Road-side pedestrian route stays clear, while the post has real collision.
		var roadward:Vector3=(B.vec(lamp.road_edge)-at).normalized()
		var tangent:=Vector3(-roadward.z,0,roadward.x)
		var walk:=Transform3D(Basis.IDENTITY,at+roadward+tangent*-3+Vector3.UP*1.03)
		body.global_transform=walk
		check(not body.test_move(walk,tangent*6),"clear road-side path in front of lamp "+lamp.id)
		var hit:=Transform3D(Basis.IDENTITY,at+basis*Vector3(0,1.03,-1))
		check(body.test_move(hit,basis*Vector3(0,0,1.3)),"post collision present "+lamp.id)
		var entrance:=origin+house_basis*Vector3(-float(lamp.width)/2+1.2,1.4,-float(lamp.depth)/2-2.8)
		check(not body.test_move(Transform3D(Basis.IDENTITY,entrance),house_basis*Vector3(0,0,2.35)),"door approach clear "+lamp.id)
		body.position=Vector3(0,-100,0)
		var envelope:=BoxShape3D.new();envelope.size=Vector3(1.40,4.05,.52)
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=envelope
		query.transform=Transform3D(basis,at+basis*Vector3(-.4407,2.075,0))
		var exclude:Array[RID]=[body.get_rid()]
		for node in host.get_children():
			if node is StaticBody3D and str(node.get_meta("uuid","")).begins_with(lamp.id+"__"):exclude.append(node.get_rid())
		query.exclude=exclude
		var intrusions:=host.get_world_3d().direct_space_state.intersect_shape(query,16)
		check(intrusions.is_empty(),"lamp/banner envelope clears facade projections "+lamp.id+" "+str(intrusions.map(func(hit):return hit.collider.get_meta("uuid",""))))
		for delta in [Vector3(.25,0,0),Vector3(-.25,0,0),Vector3(0,0,.25),Vector3(0,0,-.25)]:
			var foot:Vector3=at+delta
			var ray:=PhysicsRayQueryParameters3D.create(foot+Vector3.UP*.15,foot-Vector3.UP*.1,1)
			var ground:=host.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not ground.is_empty(),"runtime ground supports lamp "+lamp.id)
		wind.refresh();wind.advance(Vector3(2,0,.7),4.0)
		var flag_found:=false
		for row:Dictionary in wind.receivers.values():
			var mesh:MeshInstance3D=row.node.get_ref()
			if str(mesh.name).begins_with(lamp.id+"__"):
				flag_found=true;wind_ids[lamp.id]=true
		check(flag_found,"independent wind banner loaded "+lamp.id)
		count+=1;mark("CHECKED_LAMP "+str(count)+" "+str(lamp.id))
	var shots:Array=[
		{"name":"street","position":Vector3(-318,2.5,-43),"target":Vector3(-263,3.0,-32)},
		{"name":"frontage","position":Vector3(-291,2.5,-42),"target":Vector3(-281,2.5,-59)},
		{"name":"residential","position":Vector3(-266,3,29),"target":Vector3(-256,2.5,8)}]
	for shot:Dictionary in shots:
		camera.position=shot.position;camera.look_at(shot.target);Stream.sync(scene,host,camera.position);await settle();wind.refresh();wind.advance(Vector3(2,0,.7),4.0)
		for frame in 12:await process_frame
		await RenderingServer.frame_post_draw
		check(view.get_texture().get_image().save_png(Author.OUT+"/"+shot.name+".png")==OK,"save visual review")
	var file:=FileAccess.open(Author.OUT+"/physical.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"lamps":count,"wind_banners":wind_ids.size(),"candidate":FileAccess.get_sha256(Author.TARGET)},"\t"));file.close()
	print("TOWN_LAMPS_PHYSICAL failures=",failures," lamps=",count);quit(1 if failures else 0)
