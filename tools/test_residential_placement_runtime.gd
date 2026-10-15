extends "res://tools/test_transfer_loading_gpu.gd"
## Reads only an explicit successful disposable HTTP-test manifest.
## Launch with tools/run_godot_background.py; never use the user's foreground desktop.
const WorldScript=preload("res://scripts/world3d/world_3d.gd")
const RoadSurface=preload("res://scripts/world3d/road_surface.gd")
var manifest_path:=""
var runtime_report:=""
var evidence:Dictionary={}
var intent_sequence:=3000000
var runtime_checks:Array=[]

func check(ok:bool,label_:String)->void:
	runtime_checks.append({"ok":ok,"label":label_})
	super.check(ok,label_)

func drive(direction:Vector3)->Dictionary:
	await physics_frame
	intent_sequence+=1
	var result:Dictionary=root.get_node("MockServer").try_move_world(intent_sequence,direction,2.6,false)
	await process_frame
	return result

func vector(values:Array)->Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

func road_support(doc:RefCounted,point:Vector3)->Dictionary:
	# Road graph Y is only a guide. Spawn on the actual saved native surface,
	# including terrain fit/lift, so the capsule is not embedded in its pavement.
	var best:= -INF
	var road_id:=""
	for record:Dictionary in doc.records:
		if not record.has("road_mesh"):continue
		var basis:=Basis.from_euler(vector(record.rotation)*PI/180.)
		var origin:=vector(record.position)
		for polygon:Array in RoadSurface.local_polygons(record):
			for i in range(1,polygon.size()-1):
				var hit:Variant=Geometry3D.ray_intersects_triangle(point+Vector3.UP*10.,Vector3.DOWN,basis*polygon[0]+origin,basis*polygon[i]+origin,basis*polygon[i+1]+origin)
				if hit is Vector3 and hit.y>best:best=hit.y;road_id=str(record.uuid)
	return {"ok":is_finite(best),"y":best,"road_id":road_id}

func entry_failure(reason:String,data:Dictionary)->void:
	check(false,reason)
	var diagnosis:Dictionary={"reason":reason,"requested_spawn":root.get_node("GameSession").world3d_spawn}
	if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and is_instance_valid(current_scene._player):
		world=current_scene
		diagnosis.player_position=world._player.global_position
		if world._building_entry!=null:diagnosis.entry=world._building_entry.report()
	var output:Dictionary={"failures":failures,"checks":runtime_checks,"manifest":manifest_path,"map_path":data.fixture,"map_sha256":data.map_sha256,"entry_failure":diagnosis}
	DirAccess.make_dir_recursive_absolute(runtime_report.get_base_dir())
	var file:=FileAccess.open(runtime_report,FileAccess.WRITE);file.store_string(JSON.stringify(output,"  "));file.close()
	if is_instance_valid(world):await cleanup_world()
	quit(1)

func run()->void:
	create_timer(300).timeout.connect(func():push_error("Residential runtime timeout");quit(2))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):manifest_path=argument.trim_prefix("--manifest=")
		if argument.begins_with("--report="):runtime_report=argument.trim_prefix("--report=")
	check(DisplayServer.get_name()!="headless","real renderer enabled on the private test desktop")
	check(not manifest_path.is_empty() and FileAccess.file_exists(manifest_path),"explicit HTTP fixture manifest exists")
	if failures:quit(1);return
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	check(parsed is Dictionary and int(parsed.get("failures",1))==0,"HTTP transaction fixture passed before runtime verification")
	if failures:quit(1);return
	var data:Dictionary=parsed
	var map_path:String=data.fixture
	directory=data.directory
	check(directory.get_file().begins_with("__residential_placement_") and Paths.allowed(map_path) and map_path.begins_with(directory+"/"),"runtime is confined to the newly generated disposable fixture")
	check(FileAccess.get_sha256(map_path)==data.map_sha256,"runtime loads the exact saved HTTP result")
	if failures:quit(1);return
	if runtime_report.is_empty():runtime_report=directory.path_join("runtime_result.json")
	var points:Array=data.road_points
	check(points.size()==2,"saved candidate supplies the complete straight approach")
	if failures:quit(1);return
	var position:Vector3=vector(data.plan.position)
	var a:=vector(points[0]);var b:=vector(points[1])
	var far_point:Vector3=a if a.distance_squared_to(position)>b.distance_squared_to(position) else b
	var near_point:Vector3=b if far_point==a else a
	var direction:=Vector3(near_point.x-far_point.x,0,near_point.z-far_point.z).normalized()
	var authored:RefCounted=Doc.open_file(map_path)
	check(authored!=null,"saved native fixture opens for exact road spawn sampling")
	if failures:quit(1);return
	var street_support:=road_support(authored,far_point)
	check(street_support.ok,"street spawn has a real saved pavement triangle beneath it")
	if failures:quit(1);return
	var start:=Vector3(far_point.x,float(street_support.y)+.9,far_point.z)
	check(data.plan.get("access",{}).get("threshold",[]).size()==3,"candidate supplies the actual entrance threshold")
	if failures:quit(1);return
	var goal:=vector(data.plan.access.threshold)+direction*1.5+Vector3.UP*.9
	WorldScript.building_readiness_enabled=true
	WorldScript.navigation_background_enabled=false;WorldScript.wind_background_enabled=true
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	session.world3d_map_path=map_path;session.world3d_spawn=start
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_meta("entry_loading_error"):
			await entry_failure(str(current_scene.get_meta("entry_loading_error")),data);return
		if is_instance_valid(current_scene) and current_scene.has_node("FailActions"):
			await entry_failure("loader: "+str(current_scene.status_label.text),data);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	world=current_scene
	world._player.set_physics_process(false)
	check(not world._player.input_locked,"production entry releases the real character after readiness")
	check(str(world._map_root.get_meta("source_map_sha256"))==data.map_sha256,"live stream uses the manifest source revision")
	var building_id:String=data.house_id
	var entrance:=""
	for row:Dictionary in world.list_building_components(building_id):
		if row.get("kind","")=="door" and str(row.get("id",""))==str(data.plan.access.fixture_id):
			entrance=str(row.id);break
	check(not entrance.is_empty(),"frozen house retains an operable entrance door")
	if not entrance.is_empty():check(world.set_building_component_state(building_id,entrance,1.,0).ok,"real authority opens the entrance for exterior-to-interior traversal")
	var min_y:float=world._player.global_position.y
	var max_sideways:=0.0
	var reasons:Dictionary={}
	var reached:=false
	for frame in 900:
		var remaining:Vector3=goal-world._player.global_position;remaining.y=0
		if remaining.length()<.3:reached=true;break
		var moved:=await drive(remaining.normalized())
		var reason:String=str(moved.get("reason","ok"));reasons[reason]=int(reasons.get(reason,0))+1
		min_y=minf(min_y,world._player.global_position.y)
		var from_start:Vector3=world._player.global_position-start;from_start.y=0
		max_sideways=maxf(max_sideways,(from_start-direction*from_start.dot(direction)).length())
		if world._player.global_position.y<start.y-1.:break
	check(reached,"actual character crosses generated road, doorstep and entrance")
	check(min_y>=minf(start.y,goal.y)-.45 and max_sideways<.5,"continuous walk has ground support and stays inside the narrow approach")
	check(world._building_traversal.attempts.has(building_id) and world._building_traversal.attempts[building_id].phase=="active","entrance crossing receives complete-building readiness authority")
	var batcher=world._map_root.get_node_or_null("GroundRenderBatches")
	var batch_deadline:=Time.get_ticks_msec()+60000
	while batcher!=null and int(batcher.stats().pending_groups)>0 and Time.get_ticks_msec()<batch_deadline:
		await process_frame
	var stats:Dictionary=batcher.stats() if batcher!=null else {}
	check(batcher!=null and int(stats.get("pending_groups",-1))==0,"runtime static preparation finishes before measuring batching")
	check(stats.get("enabled",false) and int(stats.get("groups",0))>0 and int(stats.get("source_surfaces",0))>int(stats.get("render_surfaces",0)),"actual runtime static batching reduces resident render surfaces")
	var connected:Dictionary={}
	for spec:Dictionary in world._map_root.get_meta("stream_library",[]):
		if data.house_ids.has(spec.uuid):connected[spec.uuid]=true
	check(data.house_ids.all(func(id):return connected.has(id)),"stream retains every independent house member identity")
	var returned:=false
	for frame in 900:
		var remaining:Vector3=start-world._player.global_position;remaining.y=0
		if remaining.length()<.3:returned=true;break
		await drive(remaining.normalized())
		if world._player.global_position.y<start.y-1.:break
	check(returned,"actual character returns from the entrance to the original street")
	evidence={"failures":failures,"manifest":manifest_path,"map_path":map_path,"map_sha256":data.map_sha256,"house_id":building_id,"start":[start.x,start.y,start.z],"goal":[goal.x,goal.y,goal.z],"reached":reached,"returned":returned,"minimum_character_y":min_y,"maximum_sideways_error":max_sideways,"movement_reasons":reasons,"batch_stats":stats,"scope":"Real HTTP-produced temporary map; exterior approach and entrance only, not unrelated rooms or a town performance benchmark"}
	evidence.street_support=street_support;evidence.entrance_fixture_id=entrance
	await cleanup_world();await process_frame;await process_frame
	evidence.failures=failures;evidence.checks=runtime_checks
	DirAccess.make_dir_recursive_absolute(runtime_report.get_base_dir())
	var file:=FileAccess.open(runtime_report,FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"  "));file.close()
	print("RESIDENTIAL_PLACEMENT_RUNTIME ",runtime_report," failures=",failures)
	quit(1 if failures else 0)
