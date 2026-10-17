extends "res://tools/test_terrain_ramp_runtime.gd"
func run()->void:
	create_timer(180).timeout.connect(func():quit(2));Engine.max_fps=60
	var input:="D:/code/rmmo_runtime/review_artifacts/heightmap_import_20261017/result.json"
	var output:="D:/code/rmmo_runtime/review_artifacts/heightmap_import_20261017/runtime.json"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):input=argument.trim_prefix("--manifest=")
		if argument.begins_with("--report="):output=argument.trim_prefix("--report=")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	check(report.failures==0 and FileAccess.get_sha256(report.map)==report.map_sha256,"saved heightmap matches actual UI/HTTP fixture SHA")
	if failures:quit(1);return
	var doc=Doc.open_file(report.map);host=Node3D.new();root.add_child(host)
	var scene:Node3D=doc.build(true);host.add_child(scene);var collisions:=0
	for mesh:MeshInstance3D in Doc.SurfaceMaterials.meshes(scene):
		var spec:={"uuid":str(mesh.get_path()),"mesh":mesh.get_meta("collision_solid",mesh.get_meta("paint_source",mesh.mesh)),"transform":mesh.global_transform,"extras":mesh.get_meta("extras",{})}
		if Stream._make_body(host,spec)!=null:collisions+=1
	check(collisions==4,"four independent native terrain colliders from saved import")
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);body.floor_snap_length=.2
	var nav:=NavStub.new();host.add_child(nav);var authority:=Authority.new();authority.mount(body,nav,report.map)
	var published:=Engine.get_physics_frames();authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":published}
	await physics_frame;await physics_frame
	await walk(authority,doc,Vector3(24,0,24),Vector3(40,0,40),"uphill across four-way tile join")
	await walk(authority,doc,Vector3(40,0,40),Vector3(24,0,24),"downhill across four-way tile join")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"passed":passed,"map":report.map,"map_sha256":report.map_sha256,"collisions":collisions,"walks":walks,"scope":"native terrain collision and WorldAuthority capsule movement; no avatar, full streaming or arbitrary heightmap safety claim"},"\t"))
	authority.release();host.free();print("HEIGHTMAP_RUNTIME passed=",passed," failures=",failures);quit(1 if failures else 0)
