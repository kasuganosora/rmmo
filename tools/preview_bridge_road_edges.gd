extends "res://tools/preview_bridge_details_20261007.gd"
const EDGE_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_road_edges_20261007"
const Stream=preload("res://scripts/world3d/world_stream.gd")
func run()->void:
	root.size=Vector2i(1440,900);Engine.max_fps=30
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(EDGE_OUT+"/plan.json"));var digest:=FileAccess.get_sha256(EDGE_OUT+"/plan.json")
	check(plan.failures==0,"road-edge candidate passed")
	var d:=Doc.new();var area:=AABB(Vector3(220,-30,85),Vector3(220,80,215))
	for r:Dictionary in plan.records:
		if Geometry.bounds([r]).intersects(area):d.records.append(r)
	var scene:=d.build();root.add_child(scene)
	# Review cameras/lights belong to the host, not the imported map hierarchy.
	var env:=WorldEnvironment.new();env.environment=Environment.new();root.add_child(env)
	var sun:=DirectionalLight3D.new();root.add_child(sun)
	preload("res://scripts/world3d/environment_settings.gd").apply(plan.metadata.environment,sun,env.environment)
	var camera:=Camera3D.new();camera.far=500;camera.fov=60;root.add_child(camera)
	var bridge:Dictionary=d._find("stone_e_0be972769041dbc9");var basis:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var center:=B.vec(bridge.position)
	for shot:Dictionary in [{"name":"bridge_street","eye":center+basis*Vector3(4,5.2,12),"target":center+basis*Vector3(53,4,0)},{"name":"residential_junction","eye":Vector3(290,17,154),"target":Vector3(316,0,179)},{"name":"riverside_road","eye":Vector3(275,4,192),"target":Vector3(315,.2,189)},{"name":"street_detail","eye":Vector3(309,1.6,168),"target":Vector3(316,.06,171)}]:
		camera.position=shot.eye;camera.look_at(shot.target)
		for frame in 20:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(EDGE_OUT+"/"+shot.name+".png")
	Stream.sync(scene,scene,Vector3(311,0,173))
	for frame in 8:await physics_frame
	var batches=scene.get_node_or_null("GroundRenderBatches");var stats:Dictionary=batches.stats() if batches!=null else {}
	check(not stats.is_empty() and stats.source_surfaces>stats.render_surfaces and stats.pending_groups==0,"native shared static batches merge current street geometry")
	var merged_roads:=0
	if batches!=null:
		for id:String in plan.road_edges.changed:
			if batches._member_groups.has(id):merged_roads+=1
	check(merged_roads>0,"new kerb road chunks are actual batch members: "+str(merged_roads))
	var ports:Dictionary=preload("res://scripts/world3d/road_bridges.gd").resolve(plan.metadata.editor_layout)
	var blocked:=0;var samples:=0
	for port:Dictionary in ports.portals:
		if port.deck_id!=bridge.uuid:continue
		for endpoint:Array in port.endpoints:
			var at:=B.vec(endpoint);var along:Vector3=basis.x
			for offset in [-3.,0.,3.]:
				var start:Vector3=at+basis.z*offset-along*1.0+Vector3.UP*.16
				var end:Vector3=start+along*2.
				var hit:=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end))
				samples+=1
				if not hit.is_empty():blocked+=1
	check(blocked==0,"bridgehead walking width has no transverse kerb: "+str(samples)+" probes")
	check(digest==FileAccess.get_sha256(EDGE_OUT+"/plan.json"),"reviewed candidate unchanged")
	FileAccess.open(EDGE_OUT+"/review.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"plan_sha256":digest,"batching":stats,"merged_road_chunks":merged_roads,"bridgehead_probes":samples,"scope":"outdoor kerb appearance and batching"},"\t"))
	print("STREET_EDGE_REVIEW failures=",failures," batches=",JSON.stringify(stats));scene.free();quit(failures)
