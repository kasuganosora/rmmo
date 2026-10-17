extends "res://tools/test_residential_curves_runtime.gd"

func walk_approach(authority:RefCounted,route:Array,label:String)->void:
	# The production controller raises the capsule during step-up before
	# move_and_slide can mark is_on_floor again. Check actual nearby static
	# support every tick, including those transitions, instead of forbidding
	# the controller's intended stair motion. Flat-road tests remain strict.
	var space:=host.get_world_3d().direct_space_state
	var ray:=PhysicsRayQueryParameters3D.create(route[0]+Vector3.UP*1.5,route[0]-Vector3.UP*8);ray.exclude=[body.get_rid()]
	var hit:=space.intersect_ray(ray)
	check(not hit.is_empty(),label+": native support below exterior start");if hit.is_empty():return
	body.position=hit.position+Vector3.UP*.91;body.velocity=Vector3.ZERO
	for i in 12:await move(authority,Vector3.ZERO)
	var ticks:=0;var rejected:=0;var airborne:=0;var unsupported:=0;var reached:=1;var max_clearance:=0.;var min_clearance:=INF
	for at:Vector3 in route.slice(1):
		while Vector2(body.position.x-at.x,body.position.z-at.z).length()>.13 and ticks<1800:
			var wish:Vector3=at-body.position;wish.y=0.;var result:=await move(authority,wish.normalized());ticks+=1
			if not result.ok:rejected+=1
			if not body.is_on_floor():airborne+=1
			var feet:=body.position-Vector3.UP*.9
			var support:=Traversal.support(space,feet,wish.normalized(),feet.y,body.collision_mask,[body.get_rid()])
			if support.is_empty():unsupported+=1
			else:
				var clearance:float=feet.y-support.position.y;max_clearance=maxf(max_clearance,clearance);min_clearance=minf(min_clearance,clearance)
				if clearance>.405 or clearance<-.02:unsupported+=1
		if Vector2(body.position.x-at.x,body.position.z-at.z).length()<=.13:reached+=1
		else:break
	for i in 12:await move(authority,Vector3.ZERO)
	var passed_:bool=reached==route.size() and rejected==0 and unsupported==0 and body.is_on_floor()
	check(passed_,label+": every waypoint reached with native support within controller step reach, no rejected move or ground penetration")
	walks.append({"case":label,"passed":passed_,"ticks":ticks,"waypoints":route.size(),"reached":reached,"rejected":rejected,"airborne":airborne,"unsupported_ticks":unsupported,"max_feet_clearance":max_clearance,"min_feet_clearance":min_clearance,"settled_on_floor":body.is_on_floor()})

func run()->void:
	create_timer(240).timeout.connect(func():quit(2));Engine.max_fps=60
	var input:="D:/code/rmmo_runtime/review_artifacts/residential_relocation_20261017/http.json";var output:="D:/code/rmmo_runtime/review_artifacts/residential_relocation_20261017/runtime.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):input=arg.trim_prefix("--manifest=")
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	check(report.failures==0 and FileAccess.get_sha256(report.fixture)==report.map_sha256,"saved relocated map matches actual HTTP fixture SHA")
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
	var house:Array=doc.records.filter(func(r):return r.uuid in report.plan.house_ids)
	var entry:Dictionary=preload("res://scripts/world_editor/residential_access.gd").entrance(house,doc.map_meta.building_instances[report.plan.building_id].yaw)
	check(entry.ok,"migrated saved entrance identity resolves")
	if entry.ok:
		var approach:Array=[entry.position+entry.outward*.55,City.vec(report.road_points[0]),City.vec(report.road_points[1])]
		await walk_approach(authority,approach,"migrated exterior treads through new access to street")
		approach.reverse();await walk_approach(authority,approach,"street through new access to migrated exterior treads")
	await walk(authority,City.vec(report.road_points[0]),City.vec(report.road_points[1]),"exterior entrance to curved street")
	await walk(authority,City.vec(report.road_points[1]),City.vec(report.road_points[0]),"curved street to exterior entrance")
	var edge:Dictionary=report.source_graph.edges.filter(func(e):return e.id=="main_lane")[0];var nodes:Dictionary={}
	for n:Dictionary in report.source_graph.nodes:nodes[n.id]=n
	var route:Array=[]
	for i in 25:route.append(Split.position(edge,nodes,.05+.9*float(i)/24.))
	await walk_curve(authority,route,"curved street forward across new junction");route.reverse();await walk_curve(authority,route,"curved street reverse across new junction")
	await walk(authority,Vector3(8,0,-16),Vector3(40,0,-16),"adjacent stone bridge eastbound")
	await walk(authority,Vector3(40,0,-16),Vector3(8,0,-16),"adjacent stone bridge westbound")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"fixture":report.fixture,"map_sha256":report.map_sha256,"collisions":collisions,"walks":walks,"scope":"Saved native colliders and production WorldAuthority capsule movement; exterior only, no avatar renderer, full streaming or arbitrary curve walkability claim"},"\t"))
	authority.release();host.free();print("RESIDENTIAL_RELOCATION_RUNTIME passed=",passed," failures=",failures);quit(1 if failures else 0)
