extends "res://tools/test_physical_traversal.gd"
## Exterior-only production physics regression, after the HTTP save/reopen test.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var walks:Array=[]

func walk(authority:RefCounted,first:Vector3,last:Vector3,label:String)->void:
	var ray:=PhysicsRayQueryParameters3D.create(first+Vector3.UP*8,first-Vector3.UP*8)
	ray.exclude=[body.get_rid()]
	var hit:=host.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty(),label+": start has real native support")
	if hit.is_empty():return
	body.position=hit.position+Vector3.UP*.91;body.velocity=Vector3.ZERO
	for i in 12:await move(authority,Vector3.ZERO)
	var ticks:=0;var rejected:=0;var airborne:=0
	while Vector2(body.position.x-last.x,body.position.z-last.z).length()>.13 and ticks<1200:
		var wish:=last-body.position;wish.y=0.
		var result:=await move(authority,wish.normalized());ticks+=1
		if not result.ok:rejected+=1
		if not body.is_on_floor():airborne+=1
	var distance:=Vector2(body.position.x-last.x,body.position.z-last.z).length()
	var passed_:bool=distance<=.13 and rejected==0 and airborne==0
	check(passed_,label+": reaches destination grounded with no rejected moves")
	walks.append({"case":label,"passed":passed_,"ticks":ticks,"distance":distance,"rejected":rejected,"airborne":airborne})

func run()->void:
	create_timer(200).timeout.connect(func():print("RESIDENTIAL_BRIDGES_RUNTIME_TIMEOUT");quit(2));Engine.max_fps=60
	var input:="";var output:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):input=argument.trim_prefix("--manifest=")
		if argument.begins_with("--report="):output=argument.trim_prefix("--report=")
	check(not input.is_empty() and not output.is_empty(),"explicit HTTP evidence and new output paths provided")
	if failures:quit(1);return
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	check(report.failures==0 and FileAccess.get_sha256(report.fixture)==report.map_sha256,"saved native map matches passing HTTP evidence SHA")
	if failures:quit(1);return
	var doc=Doc.open_file(report.fixture);host=Node3D.new();root.add_child(host)
	var scene:Node3D=doc.build(true);host.add_child(scene);var collisions:=0
	for mesh:MeshInstance3D in Doc.SurfaceMaterials.meshes(scene):
		var spec:={"uuid":str(mesh.get_path()),"mesh":mesh.get_meta("collision_solid",mesh.get_meta("paint_source",mesh.mesh)),"transform":mesh.global_transform,"extras":mesh.get_meta("extras",{})}
		if Stream._make_body(host,spec)!=null:collisions+=1
	check(collisions>10,"saved house, terrain, road and bridge use production collider builder")
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D"
	var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);body.floor_snap_length=.2
	var nav:=NavStub.new();host.add_child(nav);var authority:=Authority.new();authority.mount(body,nav,report.fixture)
	var published:=Engine.get_physics_frames();authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":published}
	await physics_frame;await physics_frame
	var start:=City.vec(report.road_points[0]);var finish:=City.vec(report.road_points[1])
	await walk(authority,start,finish,"entrance exterior to main road")
	await walk(authority,finish,start,"main road to entrance exterior")
	await walk(authority,Vector3(8,0,-16),Vector3(40,0,-16),"native stone bridge and both approaches eastbound")
	await walk(authority,Vector3(40,0,-16),Vector3(8,0,-16),"native stone bridge and both approaches westbound")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"passed":passed,"fixture":report.fixture,"map_sha256":report.map_sha256,"collisions":collisions,"walks":walks,"scope":"saved native meshes/colliders and WorldAuthority movement; exterior only, no repeated house interior review, no avatar renderer or formal map edits"},"\t"))
	authority.release();host.free();print("RESIDENTIAL_BRIDGES_RUNTIME failures=",failures);quit(1 if failures else 0)
