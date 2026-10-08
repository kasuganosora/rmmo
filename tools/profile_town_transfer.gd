extends SceneTree
## Real entry and same-map transfer; only the pre-existing disposable checkpoint.
const MAP="D:/code/rmmo_runtime/cache/world3d/reference_load_checkpoint_26004507/map.gltf"
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var output:="D:/code/rmmo_runtime/review_artifacts/town_transfer_20261008.json"
var report:Dictionary={"failures":0,"stages":[]}
var world:Node
var result:Dictionary={"done":false,"ok":false}

func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if not value:report.failures+=1
func persist()->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()

func surface_at(specs:Array,point:Vector2)->Dictionary:
	var answer:Dictionary={};var highest:=-INF;var visited:=0;var triangles:=0
	for spec:Dictionary in specs:
		var extra:Dictionary=spec.get("extras",{})
		if extra.get("rmmo_collision","")=="none" or extra.get("hostile",false) or extra.get("ally",false):continue
		# Only already-loaded native CPU geometry, never import a deferred model
		# or use a guessed/default ground height to make the transfer pass.
		var shape:Mesh=spec.mesh
		if shape.get_script()!=Cpu and not shape.has_meta("ground_cpu_cache"):continue
		var pose:Transform3D=spec.transform;var bounds:AABB=pose*shape.get_aabb()
		if point.x<bounds.position.x or point.x>bounds.end.x or point.y<bounds.position.z or point.y>bounds.end.z:continue
		visited+=1
		var cpu:Mesh=shape if shape.get_script()==Cpu else shape.get_meta("ground_cpu_cache")
		var faces:PackedVector3Array=cpu.collision_faces()
		var origin:=Vector3(point.x,bounds.end.y+1,point.y)
		for index in range(0,faces.size()-2,3):
			var a:Vector3=pose*faces[index];var b:Vector3=pose*faces[index+1];var c:Vector3=pose*faces[index+2]
			var normal:Vector3=(b-a).cross(c-a).normalized();triangles+=1
			if absf(normal.y)<cos(deg_to_rad(40)):continue
			var hit:Variant=Geometry3D.ray_intersects_triangle(origin,Vector3.DOWN,a,b,c)
			if hit is Vector3 and hit.y>highest:
				highest=hit.y
				answer={"uuid":str(spec.get("uuid","")),"surface_id":str(extra.get("surface_id","")),"kind":str(extra.get("kind","")),"y":hit.y,"normal":[normal.x,normal.y,normal.z],"triangle":[[a.x,a.y,a.z],[b.x,b.y,b.z],[c.x,c.y,c.z]]}
	answer.scanned_specs=visited;answer.scanned_triangles=triangles
	return answer

func execute_transfer(destination:Vector3)->void:
	result.ok=await world.transfer_map(MAP,destination);result.done=true

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not Paths.allowed(output,Paths.external_root().path_join("review_artifacts")) or not FileAccess.file_exists(MAP):quit(1);return
	create_timer(900).timeout.connect(func():report.timeout=true;persist();quit(2))
	Engine.max_fps=60;root.size=Vector2i(1440,900);root.content_scale_size=root.size
	report.map=MAP;report.map_sha=FileAccess.get_sha256(MAP);report.formal_sha=FileAccess.get_sha256(FORMAL)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session:=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_map_path=MAP
	var entry_started:=Time.get_ticks_usec();session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_node("FailActions"):
			check(false,"real loading entry: "+str(current_scene.status_label.text));persist();quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	world=current_scene;report.entry_ms=(Time.get_ticks_usec()-entry_started)/1000.
	report.entry_profile=world._map_root.get_meta("load_profile",{}).duplicate(true)
	var old_map:Node=world._map_root;var old_position:Vector3=world._player.global_position
	report.origin=[old_position.x,old_position.y,old_position.z]
	var deferred:Node=old_map.get_node_or_null("DeferredAssets")
	report.initial_pending=deferred.pending.size() if deferred!=null else 0
	check(report.initial_pending>0,"real town enters with remote ordinary models still pending")
	var xz:=Vector2(292.9,151.4)
	var nearby:=AABB(Vector3(xz.x-48,-100000,xz.y-48),Vector3(96,200000,96))
	var unprepared:bool=deferred!=null and not deferred.ensure_geometry(nearby)
	check(unprepared,"bridge district really contains unprepared nearby ordinary models")
	report.target_pending=[]
	if deferred!=null:
		for item:Dictionary in deferred.pending:
			var box:AABB=item.bounds
			if Rect2(nearby.position.x,nearby.position.z,nearby.size.x,nearby.size.z).intersects(Rect2(box.position.x,box.position.z,box.size.x,box.size.z)):
				report.target_pending.append({"uuid":str(item.record.uuid),"path":str(item.path)})
	var height_started:=Time.get_ticks_usec()
	var hit:=surface_at(old_map.get_meta("stream_library",[]),xz)
	report.height_query_ms=(Time.get_ticks_usec()-height_started)/1000.;report.destination_surface=hit
	check(hit.has("y"),"bridge destination height comes from a native walkable triangle intersection")
	if not hit.has("y") or not unprepared:persist();world.free();current_scene=null;quit(1);return
	var destination:=Vector3(xz.x,float(hit.y)+.9,xz.y)
	report.destination=[destination.x,destination.y,destination.z]
	var began:=Time.get_ticks_usec();var last_log:=began;var previous_stage:=""
	var saw_cover:=false;var continuous:=true;var frozen:=true;var stayed:=true;var drawn_first:=true;var captured:=false
	execute_transfer(destination)
	while not result.done:
		var cover:Node=world.get_node_or_null("TransferLoading")
		continuous=continuous and cover!=null
		if cover!=null:
			saw_cover=true;frozen=frozen and world._player.input_locked and not world._player.is_physics_processing()
			if world._map_root==old_map:stayed=stayed and world._player.global_position.is_equal_approx(old_position)
			if is_instance_valid(world._transfer_loader):drawn_first=drawn_first and cover.drawn_frame>=0
			if str(cover.stage)!=previous_stage:
				previous_stage=cover.stage;report.stages.append({"stage":previous_stage,"at_ms":(Time.get_ticks_usec()-began)/1000.})
			if not captured and cover.drawn_frame>=0:
				var capture_started:=Time.get_ticks_usec();report.cover_image=output.get_basename()+"_cover.png"
				check(root.get_texture().get_image().save_png(report.cover_image)==OK,"capture one actual transfer loading frame")
				report.cover_capture_ms=(Time.get_ticks_usec()-capture_started)/1000.;captured=true
		if Time.get_ticks_usec()-last_log>=15000000:
			last_log=Time.get_ticks_usec();print("TOWN_TRANSFER_STAGE ",previous_stage," elapsed_ms=",(last_log-began)/1000.)
		await process_frame
	report.transfer_ms=(Time.get_ticks_usec()-began)/1000.;report.transfer_ok=result.ok
	check(saw_cover and continuous and frozen,"cover remains throughout transfer with input and gravity frozen")
	check(stayed and drawn_first,"no early target placement and loading cover precedes heavy work")
	check(result.ok,"real same-town bridge transfer commits")
	report.loading_profile=world.get_meta("transfer_loading_profile",{}).duplicate(true)
	report.destination_map_profile=world._map_root.get_meta("load_profile",{}).duplicate(true)
	report.destination_nav_profile=world._navigation.loading_profile.duplicate(true)
	check(report.loading_profile.get("ready_frame",0)>report.loading_profile.get("drawn_frame",0),"target first rendered frame precedes cover retirement")
	await process_frame
	check(world.get_node_or_null("TransferLoading")==null and not world._transfer_pending,"loading cover retires at completed handoff")
	check(world._hud._radar.terrain_is_prepared(),"target minimap drawing is ready before loading cover retires")
	check(world._player.global_position.distance_to(destination)<.15 and not world._player.input_locked,"player arrives at calculated bridge height and regains input")
	var target_service:Node=world._map_root.get_node_or_null("DeferredAssets")
	check(target_service==null or target_service.ensure_geometry(nearby),"target nearby model catalog is complete")
	check(Stream.nearby_collision_ready(world._map_root,destination) and world._navigation.ready_for_queries and world._navigation.near_surface(destination-Vector3.UP*.9,.35,.4),"target collision and actual local navigation surface are ready")
	world._camera.yaw=-2.2
	await process_frame;await RenderingServer.frame_post_draw
	report.final_image=output.get_basename()+"_destination.png"
	check(root.get_texture().get_image().save_png(report.final_image)==OK,"capture one final bridge view facing town")
	check(FileAccess.get_sha256(MAP)==report.map_sha and FileAccess.get_sha256(FORMAL)==report.formal_sha,"checkpoint and formal source map SHA remain unchanged")
	persist();print("TOWN_TRANSFER_FINISHED failures=",report.failures," transfer_ms=",report.transfer_ms," report=",output)
	world.free();current_scene=null
	for frame in 3:await process_frame
	quit(0 if report.failures==0 else 1)
