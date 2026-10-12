extends "res://tools/test_medieval_town_houses.gd"
const OUT="D:/code/rmmo_runtime/review_artifacts/bridge_road_edges_20261007"
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
func walk(target:Vector3,label_:String)->void:
	var before:=failures
	await super.walk(target,label_)
	if failures==before:return
	var body:CharacterBody3D=world._player;var foot:=body.position-Vector3.UP*.9
	var direction:=Vector3(target.x-foot.x,0,target.z-foot.z).normalized()
	var hits:Array=[]
	for distance in [0.,.15,.25,.32,.32+4./60.,.4,.5,.7]:
		var at:Vector3=foot+direction*distance
		var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.4,at-Vector3.UP*2);query.exclude=[body.get_rid()]
		var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():hits.append({"ahead":distance,"position":B.arr(hit.position),"normal":B.arr(hit.normal),"collider":str(hit.collider.get_path())})
	print("KERB_STOP_RAYS ",JSON.stringify(hits))
	await capture("gate_stop",foot+Vector3(-3,3,2),foot+direction*.5)
func run()->void:
	create_timer(900).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900);output_directory=OUT
	var published:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/published.json"))
	check(published.failures==0 and published.sha256==FileAccess.get_sha256(FORMAL),"published street matches reviewed map")
	if failures:quit(1);return
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/plan.json"))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession");session.world3d_map_path=FORMAL;session.world3d_spawn=Vector3(312,.9,171)
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(FORMAL)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"native runtime worker loads saved kerb geometry")
	if loaded[0]==null:quit(1);return
	session.prepared_world3d=loaded[0];session.world3d_loading=true
	world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	for child in world.get_children():
		if child is CanvasLayer:child.hide()
	world._request_environment({"time_hours":12.,"time_speed":0.})
	var bridge:Dictionary=plan.records.filter(func(r):return r.uuid=="stone_e_0be972769041dbc9")[0]
	var center:=B.vec(bridge.position);var basis:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var x:float=bridge.bridge_mesh.length/2-4.
	var on_bridge:=center+basis*Vector3(x,preload("res://scripts/world3d/bridge_mesh.gd").height_at(x,bridge.bridge_mesh),0)
	var approach:=center+basis*Vector3(bridge.bridge_mesh.length/2+6,0,0)
	await teleport(on_bridge);await walk(approach,"bridge to open approach")
	await walk(on_bridge,"open approach to bridge")
	var graph:Dictionary=plan.metadata.editor_layout.roads;var nodes:Dictionary={}
	for node:Dictionary in graph.nodes:nodes[node.id]=B.vec(node.position)
	var street:Dictionary=graph.edges.filter(func(e):return e.id=="e_8c02b3753c1cd333")[0]
	var route:Array=[]
	for t in [.15,.35,.60]:route.append(nodes[street.from].bezier_interpolate(B.vec(street.controls[0]),B.vec(street.controls[1]),nodes[street.to],t)+Vector3.UP*.025)
	await teleport(route[0]);await walk(route[1],"residential road center before bend")
	await walk(route[2],"residential road center through bend")
	var yard:Dictionary=plan.metadata.building_instances["building_911d5e25d3ff8ab3477b"]
	var yb:=Basis(Vector3.UP,deg_to_rad(yard.yaw));var yp:=B.vec(yard.position)
	await teleport(yp+yb*Vector3(plan.gate_x,.025,-18));await walk(yp+yb*Vector3(plan.gate_x,.025,-10),"cross low kerb toward courtyard gate exterior")
	var home:Dictionary=plan.metadata.building_instances[plan.new_home];var hb:=Basis(Vector3.UP,deg_to_rad(home.yaw));var hp:=B.vec(home.position)
	await teleport(Vector3(293,.025,192))
	await walk(hp+hb*Vector3(-home.parameters.width/2+1.2,.025,-home.parameters.depth/2-1.2),"riverside road across kerb to house exterior")
	await walk(Vector3(293,.025,192),"house exterior back across kerb")
	await teleport(Vector3(312,.025,172));world._player.hide();world._camera.camera.fov=60
	await capture("game_bridge_street",center+basis*Vector3(4,5.2,12),center+basis*Vector3(53,4,0))
	await capture("game_junction",Vector3(290,17,154),Vector3(316,0,179))
	await capture("game_road_detail",Vector3(309,1.6,168),Vector3(316,.06,171))
	var batcher=world._map_root.get_node_or_null("GroundRenderBatches");var stats:Dictionary=batcher.stats() if batcher!=null else {}
	check(not stats.is_empty() and stats.source_surfaces>stats.render_surfaces,"actual runtime static batches reduce surfaces")
	FileAccess.open(OUT+"/game_result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"sha256":FileAccess.get_sha256(FORMAL),"batching":stats,"interior_tests":"omitted at user request","scope":"bridgehead, street and exterior doorstep routes"},"\t"))
	print("ROAD_EDGE_GAME failures=",failures," batching=",JSON.stringify(stats));world.free();quit(failures)
