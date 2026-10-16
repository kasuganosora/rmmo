extends "res://tools/review_axel_town_spawn.gd"
## Read-only outdoor review. Launch GPU only via run_godot_background.py.
## Authoritative saved graph/bridge bindings supply geometry; no stale hardcoded Y.
const City = preload("res://scripts/world3d/city_layout.gd")
const Ports = preload("res://scripts/world3d/road_bridges.gd")
const BridgeMesh = preload("res://scripts/world3d/bridge_mesh.gd")
const BridgeTools = preload("res://scripts/world_editor/bridge_tools.gd")
const FORMAL = "D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
var document
var layout: Dictionary
var nodes: Dictionary = {}
var records: Dictionary = {}
var bridge_ports: Array = []

func vector(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])

func object_id(collider: Object) -> String:
	return str(collider.get_meta("uuid","")) if collider!=null else ""

func ray_surface(point: Vector3, up: float = 4.0, down: float = 8.0) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*up,point-Vector3.UP*down)
	query.exclude=[world._player.get_rid()]; query.collision_mask=world._player.collision_mask
	var hit: Dictionary=world._player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"ok":false,"at":xyz(point)}
	return {"ok":hit.normal.y>=cos(deg_to_rad(45)),"position":xyz(hit.position),"normal":xyz(hit.normal),"id":object_id(hit.collider)}

func bridge_pose(record: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_euler(vector(record.rotation)*PI/180).scaled(vector(record.size)),vector(record.position))

func bridge_point(record: Dictionary, x: float, z: float = 0.0) -> Vector3:
	return bridge_pose(record)*Vector3(x,BridgeMesh.height_at(x,record.bridge_mesh),z)

func relocate(point: Vector3, label: String) -> bool:
	# The real same-map transfer prepares streaming collision/navigation before
	# moving the normal character; neither collision nor loading gates are removed.
	var ok: bool=await world.transfer_map(map_path,point+Vector3.UP*.9)
	var diagnostics:={"feet":xyz(point),"transfer":world.get_meta("transfer_loading_profile",{})}
	if not ok:
		diagnostics.actual_surface=ray_surface(point,1.,2.)
		diagnostics.status=str(world._status.text)
	if not check(ok,"native same-map review transfer "+label,diagnostics): return false
	for frame in 12: await physics_frame
	var supported:=support(feet(),.8,.3)
	check(not world._player.geometry_blocked and not world._player.input_locked,"review position has ready local geometry "+label)
	return check(supported.ok,"review position supported "+label,supported)

func stop_route() -> void:
	world._player.click_target=null; world._player._route.clear()

func await_visual_residency(label:String)->void:
	# Keep normal world processing alive until the requested region finishes.
	# Freezing camera follow also freezes streaming; a settled batcher alone
	# cannot prove that its not-yet-published source assets are present.
	var started:=Time.get_ticks_msec();var stable:=0
	while Time.get_ticks_msec()-started<120000:
		await process_frame
		var map:Node=world._map_root;var queue:Node=map.get_node_or_null("DeferredAssets")
		var pending:bool=queue!=null and queue.pending.any(func(item):return queue._demanded_by_id.has(item.record.uuid))
		var ready:bool=map.has_meta("stream_chunk") and map.get_meta("stream_jobs",[]).is_empty() and map.get_meta("stream_append_pending",[]).is_empty() and not pending
		stable=stable+1 if ready else 0
		if stable>=30:break
	if not report.has("view_preparations"):report.view_preparations=[]
	var result:={"id":label,"ready":stable>=30,"wait_ms":Time.get_ticks_msec()-started,"method":"normal world processing; no extra view demand or residency radius"}
	report.view_preparations.append(result)
	check(result.ready,"requested source assets and residency settle before capture "+label,result)

func walk_route(target: Vector3, label: String, bridge: Dictionary = {}) -> Dictionary:
	var start:=feet(); var request: Dictionary=world._player.set_click_target(target,"ground")
	var began:=Time.get_ticks_msec(); var unsupported:=0; var max_unsupported:=0
	var max_side:=0.0; var min_y:=start.y; var sample_count:=0
	var inverse:=Transform3D.IDENTITY
	if not bridge.is_empty(): inverse=bridge_pose(bridge).affine_inverse()
	while Time.get_ticks_msec()-began<45000:
		await physics_frame
		var point:=feet(); min_y=minf(min_y,point.y); sample_count+=1
		if not bridge.is_empty():
			var local:=inverse*point
			if absf(local.x)<=float(bridge.bridge_mesh.length)*.5: max_side=maxf(max_side,absf(local.z))
		var hit:=support(point,.6,.3)
		unsupported=0 if hit.ok else unsupported+1; max_unsupported=maxi(max_unsupported,unsupported)
		if unsupported>20: break
		if point.distance_to(target)<.35: break
		if not world._player.path_status.get("ok",false) and world._player.path_status.get("reason","")!="pending": break
	var remaining:=feet().distance_to(target)
	var within_lane:=bridge.is_empty() or max_side<(float(bridge.bridge_mesh.width)-1.16)*.5-.15
	var result:={"label":label,"start":xyz(start),"end":xyz(feet()),"target":xyz(target),"remaining_m":remaining,"elapsed_ms":Time.get_ticks_msec()-began,"unsupported_ticks":max_unsupported,"max_bridge_lateral_m":max_side,"minimum_y":min_y,"physics_samples":sample_count,"request_reason":request.get("reason",""),"final_path_reason":world._player.path_status.get("reason","")}
	result.passed=remaining<.45 and max_unsupported<=20 and within_lane
	if not result.passed:
		result.path_status=world._player.path_status.duplicate(true)
		result.remaining_route=Array(world._player._route).map(func(p):return xyz(p))
		result.click_target=xyz(world._player.click_target) if world._player.click_target is Vector3 else null
		result.velocity=xyz(world._player.velocity);result.on_floor=world._player.is_on_floor()
		result.contacts=[]
		for i in world._player.get_slide_collision_count():
			var collision:KinematicCollision3D=world._player.get_slide_collision(i)
			for j in collision.get_collision_count():result.contacts.append({"id":object_id(collision.get_collider(j)),"position":xyz(collision.get_position(j)),"normal":xyz(collision.get_normal(j))})
	check(result.passed,"actual player follows outdoor route "+label,result)
	stop_route()
	return result

func audit_bridge(port: Dictionary, index: int) -> void:
	var record: Dictionary=records[port.deck_id]
	var recipe: Dictionary=record.bridge_mesh
	var length_: float=recipe.length
	var a:=bridge_point(record,-length_*.5); var b:=bridge_point(record,length_*.5)
	var direction:=Vector3(b.x-a.x,0,b.z-a.z).normalized()
	report.phase="bridge_%d"%(index+1)
	if not await relocate(a,"bridge_%d_start"%(index+1)): return
	var samples: Array=[]; var invalid: Array=[]
	var steps:=ceili(length_/.5)
	var half_lane:=minf(1.35,(float(recipe.width)-1.16)*.28)
	for i in steps+1:
		# At the exact shared abutment edge, either the road or the bridge may
		# own the ray hit. Probe bridge-only identity 3 cm inside; the separate
		# approach samples still verify both exact joins and their height match.
		var x:=clampf(lerpf(-length_*.5,length_*.5,float(i)/steps),-length_*.5+.03,length_*.5-.03)
		for lane in [-half_lane,0.0,half_lane]:
			var expected:=bridge_point(record,x,lane)
			var hit:=ray_surface(expected,.4,1.0)
			var good: bool=hit.ok and absf(float(hit.get("position",[0,-10000,0])[1])-expected.y)<.10 and hit.get("id")==port.deck_id
			var row:={"x":x,"lane":lane,"expected":xyz(expected),"hit":hit,"passed":good}
			samples.append(row)
			if not good: invalid.append(row)
	check(invalid.is_empty(),"bridge %d center and both walking lanes have exact bridge collision"%(index+1),{"samples":samples.size(),"bad_samples":invalid})
	var approaches: Array=[];var endpoint_hits:Array=[{},{}]
	for endpoint in [0,1]:
		var endpoint_point: Vector3=a if endpoint==0 else b
		var outward: Vector3=-direction if endpoint==0 else direction
		# Runtime collision is prepared around the current player/arrival clip,
		# not the full rendered bridge vista. Prepare each endpoint locally by
		# the production transfer before demanding its actual road collision.
		if not await relocate(endpoint_point-outward*.03,"bridge_%d_end_%d"%[index+1,endpoint]):continue
		var previous: Variant=null
		for offset in [-.25,0.0,.15,.35,.65,1.0,1.5,2.0]:
			var expected: Vector3=endpoint_point+outward*float(offset)
			var hit:=ray_surface(expected,1.0,2.0)
			var carrier: Dictionary=records.get(hit.get("id",""),{})
			var good: bool=hit.ok and (carrier.has("road_mesh") or carrier.has("bridge_mesh"))
			if good and previous!=null:
				good=absf(float(hit.position[1])-float(previous))<=.22
			if hit.ok: previous=float(hit.position[1])
			approaches.append({"end":endpoint,"offset":offset,"hit":hit,"passed":good})
			if offset==2.0:endpoint_hits[endpoint]=hit
	check(approaches.size()==16 and approaches.all(func(r):return r.passed),"bridge %d both road/deck joins are continuous"%(index+1),{"samples":approaches})
	var rail_probes: Array=[]
	var center:=bridge_point(record,0)
	var side:=bridge_pose(record).basis.z.normalized()
	for sign_ in [-1,1]:
		var test_pose: Transform3D=world._player.global_transform
		test_pose.origin=center+Vector3.UP*.96
		var contact:=KinematicCollision3D.new()
		var blocked: bool=world._player.test_move(test_pose,side*float(sign_)*(float(recipe.width)*.5+.5),contact,.001,false)
		var collider: Object=contact.get_collider() if blocked else null
		var is_rail: bool=blocked and object_id(collider)==port.deck_id and contact.get_normal().dot(side*float(sign_))<-.4
		rail_probes.append({"side":sign_,"blocked":blocked,"owner":object_id(collider),"normal":xyz(contact.get_normal()) if blocked else [],"passed":is_rail})
	check(rail_probes.all(func(r):return r.passed),"bridge %d real player capsule is blocked by both stone parapets"%(index+1),{"probes":rail_probes})
	# Keep both previously measured local endpoints; do not raycast a distant
	# unloaded road again. The actual bidirectional walks must stream normally.
	var start_hit:Dictionary=endpoint_hits[0];var end_hit:Dictionary=endpoint_hits[1]
	var walks: Array=[]
	if start_hit.get("ok",false) and end_hit.get("ok",false) and invalid.is_empty() and approaches.size()==16 and approaches.all(func(r):return r.passed):
		if await relocate(vector(start_hit.position),"bridge_%d_approach"%(index+1)):
			walks.append(await walk_route(vector(end_hit.position),"bridge_%d_forward"%(index+1),record))
			if walks.back().passed: walks.append(await walk_route(vector(start_hit.position),"bridge_%d_reverse"%(index+1),record))
	else: check(false,"bridge %d cannot start a safe crossing"%(index+1))
	report.bridges.append({"number":index+1,"id":port.deck_id,"edge_id":port.edge_id,"start":xyz(a),"end":xyz(b),"clear_width":port.width,"deck_samples":samples,"approaches":approaches,"parapets":rail_probes,"walks":walks})
	if index==2:
		await capture("bridge3_runtime",center+side*13-direction*7+Vector3.UP*7,center+direction*5)
	save_report()

func adjoining(node_id: String) -> Array:
	return layout.roads.edges.filter(func(edge):return edge.kind=="ground" and node_id in [str(edge.from),str(edge.to)])

func junction_directions(node_id: String) -> Array[Vector3]:
	var center:=vector(nodes[node_id].position); var result: Array[Vector3]=[]
	for edge: Dictionary in adjoining(node_id):
		var from_: bool=edge.from==node_id
		var other:=vector(nodes[edge.to if from_ else edge.from].position)
		if edge.has("controls"): other=vector(edge.controls[0 if from_ else 1])
		var delta:=Vector3(other.x-center.x,0,other.z-center.z)
		if delta.length()>.01: result.append(delta.normalized())
	return result

func audit_junction(anchor: Vector2, label: String) -> void:
	var selected: Dictionary={}; var best:=INF
	for node: Dictionary in layout.roads.nodes:
		if adjoining(str(node.id)).size()<2: continue
		var distance:=anchor.distance_to(Vector2(node.position[0],node.position[2]))
		if distance<best: best=distance; selected=node
	if not check(not selected.is_empty() and best<25,"key junction found "+label,{"distance_from_plan":best}): return
	var center:=vector(selected.position); var directions:=junction_directions(selected.id)
	report.phase="junction_"+label
	# The saved graph retains design elevations. Transfer onto the current
	# native heightfield + road lift before streaming physics is queried; later
	# ray checks still require the actual generated road's collision UUID.
	var design_y:=center.y
	var terrain_records:Array=document.records.filter(func(r):return r.has("terrain_mesh"))
	var terrain_y:=BridgeTools.ground_height(terrain_records,center)
	if not check(is_finite(terrain_y),"junction native terrain sample available "+label):return
	center.y=terrain_y+float(layout.road_surface.settings.get("lift",.025))
	if not await relocate(center+Vector3.UP*.02,label): return
	var center_hit:=ray_surface(center,2,4)
	if not check(center_hit.ok and records.get(center_hit.get("id",""),{}).has("road_mesh"),"junction center has actual road support "+label,center_hit): return
	center=vector(center_hit.position)
	var samples: Array=[]
	for direction: Vector3 in directions:
		var previous_y:=center.y
		for index in 13:
			var hit:=ray_surface(center+direction*float(index)*.25,2,3)
			var carrier: Dictionary=records.get(hit.get("id",""),{})
			var good: bool=hit.ok and carrier.has("road_mesh")
			if good: good=absf(float(hit.position[1])-previous_y)<.20; previous_y=float(hit.position[1])
			samples.append({"distance":index*.25,"direction":xyz(direction),"hit":hit,"passed":good})
	check(samples.all(func(r):return r.passed),"key junction arms have continuous physical pavement "+label,{"samples":samples.size(),"failures":samples.filter(func(r):return not r.passed)})
	var walks: Array=[]
	if directions.size()>=2 and samples.all(func(r):return r.passed):
		var pair: Array=[directions[0],directions[1]]; var minimum_dot:=1.0
		for a: Vector3 in directions:
			for b: Vector3 in directions:
				if a.dot(b)<minimum_dot: minimum_dot=a.dot(b); pair=[a,b]
		var first:=ray_surface(center+pair[0]*3,2,3); var last:=ray_surface(center+pair[1]*3,2,3)
		if first.ok and last.ok and await relocate(vector(first.position),label+"_entry"):
			walks.append(await walk_route(vector(last.position),label+"_across"))
	report.junctions.append({"label":label,"node_id":selected.id,"center":xyz(center),"graph_design_y":design_y,"native_terrain_y":terrain_y,"arms":directions.size(),"samples":samples,"walks":walks})
	if label=="guild_south": await capture("guild_road_junction",center+Vector3(-10,9,13),center)
	save_report()

func run() -> void:
	started_ms=Time.get_ticks_msec(); map_path=FORMAL
	output="D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/runtime_review"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="): map_path=arg.trim_prefix("--map=").replace("\\","/").simplify_path()
		elif arg.begins_with("--out="): output=arg.trim_prefix("--out=").replace("\\","/").simplify_path()
	report={"scope":"saved outdoor road network, all five bridge lanes/approaches/parapets, bidirectional player crossings and three key junctions","not_tested":["interiors","full-town performance","all graph edges walked","global startup configuration"],"checks":[],"screenshots":[],"bridges":[],"junctions":[],"map_path":map_path,"phase":"metadata"}
	if not Paths.allowed(output) or DirAccess.make_dir_recursive_absolute(output)!=OK: quit(1); return
	create_timer(900).timeout.connect(func():
		if not finished: check(false,"outdoor road review timeout",{"phase":report.phase}); finish(2))
	if not check(DisplayServer.get_name()!="headless","actual renderer required") or not check(Paths.allowed(map_path) and FileAccess.file_exists(map_path),"saved review map available"): finish(); return
	report.map_sha256=FileAccess.get_sha256(map_path)
	document=Document.open_file(map_path)
	if not check(document!=null,"native map document opened read-only"): finish(); return
	layout=City.resolve(document.map_meta)
	for row: Dictionary in document.records: records[str(row.uuid)]=row
	for node: Dictionary in layout.roads.nodes: nodes[str(node.id)]=node
	var binding: Dictionary=Ports.resolve(layout)
	if not check(binding.get("ok",false),"native bridge bindings consistent",{"error":binding.get("error","")}): finish(); return
	bridge_ports=binding.portals.filter(func(p):return p.get("road_stone",false))
	bridge_ports.sort_custom(func(a,b):return float(a.endpoints[0][2])+float(a.endpoints[1][2])<float(b.endpoints[0][2])+float(b.endpoints[1][2]))
	if not check(bridge_ports.size()==5,"five real bound stone bridges saved"): finish(); return
	for port: Dictionary in bridge_ports:
		check(records.has(port.deck_id) and records.get(port.deck_id,{}).has("bridge_mesh"),"bridge recipe retained "+str(port.deck_id))
	check(layout.get("road_surface",{}).get("graph_token")==City.token(layout.roads),"generated road surface matches current graph")
	check(records.values().any(func(row):return row.has("road_mesh")),"generated physical road records present")
	if failures: finish(); return
	report.graph={"nodes":nodes.size(),"edges":layout.roads.edges.size(),"bridges":bridge_ports.size(),"settings":layout.road_surface.settings}
	Engine.max_fps=60; root.size=Vector2i(1600,1000); root.content_scale_size=root.size
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_requested=true; session.loading_mode="world3d_preview"; session.world3d_map_path=map_path
	session.world3d_spawn=Vector3(0,.9,4); session.prepared_world3d=null
	report.phase="native_loading"
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"enter production LoadingScene"): finish(); return
	while not finished:
		await process_frame; world=current_scene
		if world==null: continue
		if world.has_meta("entry_loading_error"): check(false,"runtime loading failed",{"error":world.get_meta("entry_loading_error")}); finish(); return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active: break
	if finished: return
	check(canonical_path(world._map_path)==canonical_path(map_path),"runtime loaded saved target map")
	check(is_instance_valid(world._player) and not world._player.get_node("CollisionShape3D").disabled,"normal character collision retained")
	for index in bridge_ports.size(): await audit_bridge(bridge_ports[index],index)
	for item: Array in [[Vector2(156,219),"guild_south"],[Vector2(165,111),"north_market"],[Vector2(248,235),"bridge3_west"]]:
		await audit_junction(item[0],item[1])
	check(FileAccess.get_sha256(map_path)==report.map_sha256,"read-only runtime review leaves map unchanged")
	report.phase="complete"; finish()
