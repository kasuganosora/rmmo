extends "res://tools/test_residential_relocation_runtime.gd"

func run()->void:
	create_timer(360).timeout.connect(func():quit(2));Engine.max_fps=60
	var input:="D:/code/rmmo_runtime/review_artifacts/residential_block_20261017/http.json";var output:="D:/code/rmmo_runtime/review_artifacts/residential_block_20261017/runtime.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):input=arg.trim_prefix("--manifest=")
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	check(report.failures==0 and FileAccess.get_sha256(report.fixture)==report.map_sha256,"saved block map matches actual HTTP fixture SHA")
	if failures:quit(1);return
	var doc=Doc.open_file(report.fixture);host=Node3D.new();root.add_child(host)
	var scene:Node3D=doc.build(true);host.add_child(scene);var collisions:=0
	for mesh:MeshInstance3D in Doc.SurfaceMaterials.meshes(scene):
		var spec:={"uuid":str(mesh.get_path()),"mesh":mesh.get_meta("collision_solid",mesh.get_meta("paint_source",mesh.mesh)),"transform":mesh.global_transform,"extras":mesh.get_meta("extras",{})}
		if Stream._make_body(host,spec)!=null:collisions+=1
	check(collisions>10,"saved native house, road, terrain and bridge collider construction")
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);body.floor_snap_length=.2
	var nav:=NavStub.new();host.add_child(nav);var authority:=Authority.new();authority.mount(body,nav,report.fixture)
	var published:=Engine.get_physics_frames();authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":published}
	await physics_frame;await physics_frame
	for home:Dictionary in report.plan.homes:
		var house:Array=doc.records.filter(func(r):return r.uuid in home.house_ids)
		var entry:Dictionary=preload("res://scripts/world_editor/residential_access.gd").entrance(house,doc.map_meta.building_instances[home.building_id].yaw)
		check(entry.ok,"saved block entrance identity resolves for "+home.id)
		if entry.ok:
			var approach:Array=[entry.position+entry.outward*.55,City.vec(home.road_points[0]),City.vec(home.road_points[1])]
			await walk_approach(authority,approach,home.id+" exterior treads through access to street")
			approach.reverse();await walk_approach(authority,approach,home.id+" street through access to exterior treads")
		await walk(authority,City.vec(home.road_points[0]),City.vec(home.road_points[1]),home.id+" access toward street")
		await walk(authority,City.vec(home.road_points[1]),City.vec(home.road_points[0]),home.id+" street toward access")
	var edge:Dictionary=report.source_graph.edges.filter(func(e):return e.id=="main_lane")[0];var nodes:Dictionary={}
	for n:Dictionary in report.source_graph.nodes:nodes[n.id]=n
	var route:Array=[]
	for i in 25:route.append(Split.position(edge,nodes,.05+.9*float(i)/24.))
	await walk_curve(authority,route,"curved street forward across new junction");route.reverse();await walk_curve(authority,route,"curved street reverse across new junction")
	await walk(authority,Vector3(8,0,-16),Vector3(40,0,-16),"adjacent stone bridge eastbound")
	await walk(authority,Vector3(40,0,-16),Vector3(8,0,-16),"adjacent stone bridge westbound")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"fixture":report.fixture,"map_sha256":report.map_sha256,"collisions":collisions,"walks":walks,"scope":"Saved native colliders and production WorldAuthority capsule movement; exterior only, no avatar renderer, full streaming or arbitrary curve walkability claim"},"\t"))
	authority.release();host.free();print("RESIDENTIAL_BLOCK_RUNTIME passed=",passed," failures=",failures);quit(1 if failures else 0)
