extends "res://tools/test_residential_relocation_runtime.gd"

func run()->void:
	create_timer(360).timeout.connect(func():quit(2));Engine.max_fps=60
	var input:="D:/code/rmmo_runtime/review_artifacts/residential_structure_20261017/http.json";var output:="D:/code/rmmo_runtime/review_artifacts/residential_structure_20261017/runtime.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):input=arg.trim_prefix("--manifest=")
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	check(report.failures==0 and report.cases.size()==3,"three successful HTTP structure cases")
	if failures:quit(1);return
	var fixtures:Array=[]
	for example:Dictionary in report.cases:
		check(FileAccess.get_sha256(example.fixture)==example.map_sha256,"saved "+example.kind+" map matches HTTP SHA")
		var doc=Doc.open_file(example.fixture);host=Node3D.new();root.add_child(host)
		var scene:Node3D=doc.build(true);host.add_child(scene);var collisions:=0
		for mesh:MeshInstance3D in Doc.SurfaceMaterials.meshes(scene):
			var spec:={"uuid":str(mesh.get_path()),"mesh":mesh.get_meta("collision_solid",mesh.get_meta("paint_source",mesh.mesh)),"transform":mesh.global_transform,"extras":mesh.get_meta("extras",{})}
			if Stream._make_body(host,spec)!=null:collisions+=1
		check(collisions>10,example.kind+" actual saved colliders construct")
		body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);body.floor_snap_length=.2
		var nav:=NavStub.new();host.add_child(nav);var authority:=Authority.new();authority.mount(body,nav,example.fixture)
		var published:=Engine.get_physics_frames();authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":published}
		await physics_frame;await physics_frame
		var plan:Dictionary=example.plan;var value:Dictionary=doc.map_meta.building_instances[plan.building_id]
		var house:Array=doc.records.filter(func(r):return r.uuid in plan.house_ids)
		var entry:Dictionary=preload("res://scripts/world_editor/residential_access.gd").entrance(house,value.yaw,example.request.entrance_id)
		check(entry.ok,example.kind+" saved explicit entrance resolves")
		if entry.ok:
			var route:Array=[entry.position+entry.outward*.55,City.vec(plan.road_points[0]),City.vec(plan.road_points[1])]
			await walk_approach(authority,route,example.kind+" exterior threshold to street");route.reverse();await walk_approach(authority,route,example.kind+" street to exterior threshold")
			if example.kind=="arch":
				route=[entry.position-entry.outward*.35,entry.position+entry.outward*.55]
				await walk_approach(authority,route,"arch portal outward");route.reverse();await walk_approach(authority,route,"arch portal inward")
		if example.kind=="piers":
			var origin:Vector3=City.vec(value.position)
			await walk(authority,origin+Vector3(0,0,-4),origin+Vector3(0,0,4),"under raised slab forward")
			await walk(authority,origin+Vector3(0,0,4),origin+Vector3(0,0,-4),"under raised slab reverse")
		fixtures.append({"kind":example.kind,"fixture":example.fixture,"map_sha256":example.map_sha256,"collisions":collisions})
		authority.release();host.free();await physics_frame
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"fixtures":fixtures,"walks":walks,"scope":"Saved native collision and production capsule movement; exterior, new arch portal and underfloor passage only. No avatar, production art or streaming/performance acceptance."},"\t"))
	print("RESIDENTIAL_STRUCTURE_RUNTIME passed=",passed," failures=",failures);quit(1 if failures else 0)
