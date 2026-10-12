extends "res://tools/preview_bridge_details_20261007.gd"
const Fix=preload("res://tools/correct_bridge_spire_courtyard.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
func yard(p:Vector2,h:Dictionary)->Vector3:return B.vec(h.position)+Basis(Vector3.UP,deg_to_rad(h.yaw))*Vector3(p.x,1.,p.y)
func run()->void:
	root.size=Vector2i(1440,900);Engine.max_fps=60
	var review_out:String=preload("res://tools/setback_bridge_courtyard.gd").SET_OUT if "--setback" in OS.get_cmdline_user_args() else Fix.FIX_OUT
	if "--residential" in OS.get_cmdline_user_args():review_out="D:/code/rmmo_runtime/review_artifacts/bridge_residential_street_20261007"
	if "--lamps" in OS.get_cmdline_user_args():review_out="D:/code/rmmo_runtime/review_artifacts/bridge_residential_lamps_20261007"
	if "--complete" in OS.get_cmdline_user_args():review_out="D:/code/rmmo_runtime/review_artifacts/bridge_residential_complete_20261007"
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(review_out+"/plan.json"))
	var reviewed_sha:=FileAccess.get_sha256(review_out+"/plan.json")
	check(plan.failures==0,"candidate geometry checks passed")
	var doc:=Doc.new();var area:=AABB(Vector3(220,-30,85),Vector3(240,80,240))
	for r:Dictionary in plan.records:
		if Geometry.bounds([r]).intersects(area):doc.records.append(r)
	var scene:=doc.build();root.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();scene.add_child(env)
	var sun:=DirectionalLight3D.new();scene.add_child(sun)
	preload("res://scripts/world3d/environment_settings.gd").apply(plan.metadata.environment,sun,env.environment)
	var camera:=Camera3D.new();camera.far=500;camera.fov=60;scene.add_child(camera)
	if "--rear-lamps" in OS.get_cmdline_user_args():
		camera.fov=70
		for home:Dictionary in plan.houses:
			if not home.rear or home.id==plan.get("new_home",""):continue
			var h:Dictionary=plan.metadata.building_instances[home.id];var hb:=Basis(Vector3.UP,deg_to_rad(h.yaw));var hp:=B.vec(h.position);var dx:float=-h.parameters.width/2+1.2
			camera.position=hp+hb*Vector3(dx+.6,2.7,-h.parameters.depth/2-3)
			camera.look_at(hp+hb*Vector3(dx+.6,2.2,-h.parameters.depth/2))
			for frame in 8:await process_frame
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(review_out+"/rear_lamp_"+str(home.id)+".png")
		scene.free();quit();return
	var bridge:Dictionary=doc._find("stone_e_0be972769041dbc9");var basis:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var center:=B.vec(bridge.position)
	camera.position=center+basis*Vector3(4,5.2,12);camera.look_at(center+basis*Vector3(53,4,0))
	for i in plan.tower_sites.size():
		scene.get_node(Fix.SPIRE).position=B.vec(plan.tower_sites[i])
		for frame in 15:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(review_out+"/tower_"+str(i)+".png")
	for shot:Dictionary in [{"name":"courtyard","eye":Vector3(304,7,164),"target":Vector3(323,1,157)},{"name":"courtyard_back","eye":Vector3(336,9,137),"target":Vector3(326,1,154)},{"name":"courtyard_top","eye":Vector3(328,44,159),"target":Vector3(328,0,159.1)}]:
		camera.position=shot.eye;camera.look_at(shot.target)
		for frame in 15:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(review_out+"/"+shot.name+".png")
	var h:Dictionary=plan.metadata.building_instances[Fix.HOUSE]
	if plan.has("converted"):
		for id:String in plan.houses.map(func(home):return home.id) if plan.has("lamps") else plan.converted:
			var home:Dictionary=plan.metadata.building_instances[id];var hb:=Basis(Vector3.UP,deg_to_rad(home.yaw));var hp:=B.vec(home.position)
			camera.position=hp+hb*Vector3(-2,3.5,-home.parameters.depth/2-8);camera.look_at(hp+hb*Vector3(0,2,-home.parameters.depth/2))
			for frame in 5:await process_frame
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(review_out+"/facade_"+id+".png")
	Stream.sync(scene,scene,B.vec(h.position))
	for frame in 4:await physics_frame
	var edges:Array=[[Vector2(-6.3,-8.8),Vector2(10,-8.8),Vector2(0,-1)],[Vector2(10,-8.8),Vector2(10,9.4),Vector2(1,0)],[Vector2(10,9.4),Vector2(-6.3,9.4),Vector2(0,1)],[Vector2(-6.3,9.4),Vector2(-6.3,-8.8),Vector2(-1,0)]]
	var missed:Array=[];var sampled:=0
	for side in edges.size():
		var edge:Array=edges[side];var steps:=ceili(edge[0].distance_to(edge[1])/.25)
		for i in range(steps+1):
			var p:Vector2=edge[0].lerp(edge[1],float(i)/steps)
			if side==0 and absf(p.x-plan.gate_x)<1.14:continue
			var hit:=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(yard(p+edge[2],h),yard(p-edge[2],h)))
			sampled+=1
			if hit.is_empty() or not str(hit.collider.get_meta("uuid","")).begins_with("obj_310"):missed.append([side,B.arr(yard(p,h))])
	check(missed.is_empty(),"all four courtyard edges block entry except the intended gate: "+str(sampled)+" probes")
	if not missed.is_empty():print("PERIMETER_GAPS ",missed)
	var body:=CharacterBody3D.new();var cs:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=1.8;capsule.radius=.3;cs.shape=capsule;body.add_child(cs);scene.add_child(body)
	for frame in 3:await physics_frame
	# Isolate the new gate's clear width. Existing doorstep height is exercised
	# separately by the actual game player's stepping path after native save.
	for existing:StaticBody3D in scene.get_meta("stream_bodies").values():
		if not str(existing.get_meta("uuid","")).begins_with("obj_310"):body.add_collision_exception_with(existing)
	for offset in [-.65,0.,.65]:
		var start:=yard(Vector2(plan.gate_x+offset,-10.5),h);var end:=yard(Vector2(plan.gate_x+offset,-7.6),h)
		check(not body.test_move(Transform3D(Basis.IDENTITY,start),end-start),"new gateway capsule clear at offset "+str(offset))
	check(reviewed_sha==FileAccess.get_sha256(review_out+"/plan.json"),"candidate unchanged during review")
	FileAccess.open(review_out+"/review.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"plan_sha256":reviewed_sha,"perimeter_probes":sampled,"gaps":missed},"\t"))
	scene.free();print("COURTYARD_REVIEW failures=",failures);quit(failures)
