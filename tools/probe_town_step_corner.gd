extends SceneTree
## CPU-only diagnosis of the exact immutable doorstep collision definition.
const MAP="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const START:=Vector3(325.141418,.899608,163.781601)
const GOAL:=Vector3(325.2,.200001,163.7)
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Step=preload("res://scripts/world3d/step_support.gd")
class Body extends CharacterBody3D:
	var surface_id:="ground"
	func _sense_surface()->void:pass
var report:Dictionary={"frames":[],"failures":0}
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:report.failures+=1
func solid(host:Node3D,shape:Shape3D,pose:Transform3D,id:String)->StaticBody3D:
	var node:=StaticBody3D.new();node.set_meta("uuid",id);var collider:=CollisionShape3D.new();collider.shape=shape;node.add_child(collider)
	host.add_child(node);node.global_transform=pose;return node
func hit_data(hit:Dictionary)->Dictionary:
	return {} if hit.is_empty() else {"position":hit.position,"normal":hit.normal,"uuid":hit.collider.get_meta("uuid","")}
func diagnostics(body:CharacterBody3D,wish:Vector3,delta:float)->Dictionary:
	var feet:=body.global_position-Vector3.UP*.9;var row:={"position":body.global_position,"wish":wish,"rays":[]}
	for length:float in [.32+wish.length()*delta,.32,.24,.16]:
		var ahead:=feet+wish.normalized()*length
		var query:=PhysicsRayQueryParameters3D.create(ahead+Vector3.UP*.4,ahead-Vector3.UP*.04,body.collision_mask,[body.get_rid()])
		row.rays.append({"length":length,"hit":hit_data(body.get_world_3d().direct_space_state.intersect_ray(query))})
	var contact:=KinematicCollision3D.new();row.horizontal_blocked=body.test_move(body.global_transform,wish*delta,contact)
	if contact.get_collision_count()>0:
		row.test_contact={"normal":contact.get_normal(),"position":contact.get_position(),"uuid":contact.get_collider().get_meta("uuid","")}
		var outward:=Vector3(contact.get_normal().x,0,contact.get_normal().z).normalized()
		var inward:=contact.get_position()-outward*.025
		var query:=PhysicsRayQueryParameters3D.create(Vector3(inward.x,feet.y+.4,inward.z),Vector3(inward.x,feet.y-.04,inward.z),body.collision_mask,[body.get_rid()])
		var tread:=body.get_world_3d().direct_space_state.intersect_ray(query);row.contact_tread=hit_data(tread)
		if not tread.is_empty():
			row.contact_rise=tread.position.y-feet.y+.005
			var up:=Vector3.UP*float(row.contact_rise);row.contact_up_blocked=body.test_move(body.global_transform,up)
			var raised:=body.global_transform;raised.origin+=up;row.contact_raised_forward_blocked=body.test_move(raised,wish*delta)
	row.rise=Step.rise(body,feet,wish,delta,.32,body.collision_mask,cos(deg_to_rad(40.)),.005)
	if row.rise>.01:
		var up:=Vector3.UP*float(row.rise);row.up_blocked=body.test_move(body.global_transform,up)
		var raised:=body.global_transform;raised.origin+=up;row.raised_forward_blocked=body.test_move(raised,wish*delta)
	return row
func run()->void:
	create_timer(30).timeout.connect(func():quit(2))
	var gltf:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MAP));var records:Array=gltf.nodes[0].extras.rmmo_records
	var compact:Array=records.filter(func(record):return record.uuid=="obj_200062")
	var hydrated:Dictionary=Store.read_records(compact,MAP,"D:/code/rmmo_runtime")
	check(hydrated.ok and hydrated.records.size()==1,"only exact authored doorstep definition is read and verified")
	if not hydrated.ok or hydrated.records.size()!=1:quit(1);return
	var record:Dictionary=hydrated.records[0];var prepared:=Prefab.prepare_cpu(record)
	check(not prepared.is_empty(),"doorstep CPU faces decode without textures or renderer")
	if prepared.is_empty():quit(1);return
	var faces:PackedVector3Array=prepared.collision_faces[int(prepared.data.entries[0][1][1])]
	var host:=Node3D.new();root.add_child(host)
	var ground:=BoxShape3D.new();ground.size=Vector3(20,.2,20);solid(host,ground,Transform3D(Basis.IDENTITY,Vector3(325,-.1,162)),"floor")
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
	var pose:Transform3D=preload("res://scripts/world3d/building_fixtures.gd").transform(record)
	solid(host,shape,pose,record.uuid);report.record={"uuid":record.uuid,"position":record.position,"rotation":record.rotation,"size":record.size,"face_vertices":faces.size()}
	var body:=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider)
	host.add_child(body);body.position=START;body.floor_snap_length=.2;body.set_meta("profile_frame",true)
	var nav:=Node.new();host.add_child(nav)
	var authority:=preload("res://scripts/world3d/world_authority.gd").new();authority.mount(body,nav,"test/step-corner")
	authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":0}
	await physics_frame;await physics_frame
	for i in 120:
		await physics_frame
		var flat:=GOAL-body.position;flat.y=0
		if flat.length()<.002:break
		var delta:=body.get_physics_process_delta_time();var speed:=minf(4.,flat.length()/delta);var wish:=flat.normalized()*speed
		var row:=diagnostics(body,wish,delta) if i<3 or i==119 else {}
		var moved:Dictionary=authority.move_intent(i,wish.normalized(),speed)
		if not row.is_empty():row.after=body.position;row.result=moved;row.profile=body.get_meta("motion_timing",{});report.frames.append(row)
	report.final_position=body.position;report.distance=Vector2(body.position.x-GOAL.x,body.position.z-GOAL.z).length();report.reached=report.distance<.002
	check(report.reached,"exact authored step corner reaches its navigation waypoint through authority physics")
	print("STEP_CORNER_DIAG ",JSON.stringify(report))
	var output:="D:/code/rmmo_runtime/review_artifacts/town_step_corner_probe_20261011.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	authority.release();host.free();quit(int(report.failures))
