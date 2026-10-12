extends "res://tools/test_collision_instance_residency_gpu.gd"
## Real nested GLB, independent cooked descriptor and MapLoadingProof. The
## render collector must derive its pose from the actual imported source tree.
## Run with run_godot_background.py on a private desktop.

func nested_glb(path:String)->void:
	write_glb(path)
	var original:=FileAccess.get_file_as_bytes(path);var length:int=original.decode_u32(12)
	var data:Dictionary=JSON.parse_string(original.slice(20,20+length).get_string_from_utf8())
	var random:=RandomNumberGenerator.new();random.seed=20261011
	# Distinct all-axis transforms and nonuniform scales deliberately exercise
	# non-associativity. Keep the independently imported GLB hierarchy intact.
	for index:int in [3,4,0]:
		var position:=Vector3(random.randf_range(-10,10),random.randf_range(-2,4),random.randf_range(-10,10))
		var rotation:=Vector3(random.randf_range(-180,180),random.randf_range(-180,180),random.randf_range(-180,180))*(PI/180.0)
		var size:=Vector3(random.randf_range(.2,2),random.randf_range(.2,2),random.randf_range(.2,2))
		var q:=Basis.from_euler(rotation).get_rotation_quaternion()
		if index>=data.nodes.size():data.nodes.append({"name":"Parent%d"%index,"children":[4 if index==3 else 0]})
		data.nodes[index].translation=[position.x,position.y,position.z]
		data.nodes[index].rotation=[q.x,q.y,q.z,q.w];data.nodes[index].scale=[size.x,size.y,size.z]
	data.scenes[0].nodes=[3]
	var binary:=original.slice(28+length);var json:=JSON.stringify(data).to_utf8_buffer()
	while json.size()%4:json.append(32)
	var output:=FileAccess.open(path,FileAccess.WRITE)
	output.store_32(0x46546c67);output.store_32(2);output.store_32(28+json.size()+binary.size())
	output.store_32(json.size());output.store_32(0x4e4f534a);output.store_buffer(json)
	output.store_32(binary.size());output.store_32(0x004e4942);output.store_buffer(binary);output.close()

func run()->void:
	create_timer(120).timeout.connect(func():push_error("canonical collision promotion timeout");quit(2))
	var errors:=Base.Errors.new();OS.add_logger(errors)
	files=Base.Files.new();files.content_root=Paths.external_root();files.folder=Paths.cache_directory("canonical_collision_gpu_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var path:String=files.folder.path_join("nested.glb");nested_glb(path);files.created.append(path)
	var estimate:=Builder.estimate(path,files.content_root);var ledger:=Admission.new()
	if not check(not estimate.is_empty() and ledger.reserve(path,estimate),"nested real GLB receives bounded collision cook admission"):finish(errors);return
	var built:=await worker(Builder.build.bind(path,files.content_root,estimate.estimated_bytes));ledger.park(path)
	var ok:bool=built.get("ok",false);check(ok,"independent descriptor cooks actual three-level source transforms")
	if not ok:print(built)
	Drainer.dispose_result(built);ledger.release(path)
	if ok:await map_case({"uuid":"entry_fixture","kind":"asset","asset_path":path,"position":[321.2,.9,160.3],"rotation":[12.345,136.088,-4.321],"size":[.7,.85,1.13],"collision":""},"canonical",errors)
	finish(errors)

func exercise(batch:RefCounted,record:Dictionary,map_path:String,_errors:RefCounted)->void:
	var live:=world();initialize_index(live.host)
	var store:=Residency.new();live.host.add_child(store);store.configure(live.host,map_path,FileAccess.get_sha256(map_path),1)
	if not check(store.enqueue(batch,1).ok,"map accepts the truly verified independent collision batch"):live.viewport.free();return
	var deadline:=Time.get_ticks_msec()+10000
	while not store.instance_readiness(record.uuid,1).ok and Time.get_ticks_msec()<deadline:
		store.step(1500);await physics_frame;await process_frame
	check(store.instance_readiness(record.uuid,1).ok,"nested collision completes real physical synchronization")
	var rows:Dictionary={};var solid:Dictionary={}
	for instance:Dictionary in batch.instances():
		for row:Dictionary in instance.rows:
			rows[row.uuid]=row
			if row.collision!="none":solid=row
	var body:StaticBody3D=store.body_for(solid.uuid)
	if not check(body!=null,"nested solid has a real independent collision body"):live.viewport.free();return
	var id:=body.get_instance_id();var rid:=body.get_rid();var stamp:int=body.get_meta("stream_physics_published_frame")
	var before:=source_rays(live.host,solid.transform)
	check(before.wall and not before.door and before.floor and not before.hole,"transformed source retains its real wall, doorway, floor and hole")
	var prepared:=await worker(Deferred.prepare_scene.bind(record.asset_path,FileAccess.get_sha256(record.asset_path),null,{},true,files.content_root,true))
	if not check(prepared.get("scene") is Node3D,"ordinary renderer imports the same nested GLB independently"):Drainer.dispose_result(prepared);live.viewport.free();return
	var holder:=Document.new()._asset(record,prepared);prepared.erase("scene")
	var old:Array=[];Deferred._collect(holder,Transform3D.IDENTITY,old)
	var additions:Array=[];Deferred._collect_collision_asset(holder,additions)
	var old_diff:=false;var exact:=additions.size()==rows.size();var spatial:=true
	for entry:Dictionary in old:old_diff=old_diff or entry.transform!=rows[entry.uuid].transform
	for entry:Dictionary in additions:
		exact=exact and rows.has(entry.uuid) and entry.transform==rows[entry.uuid].transform
		var bounds:AABB=entry.transform*entry.mesh.get_aabb()
		spatial=spatial and entry.position==entry.transform.origin and entry.rotation==entry.transform.basis.get_euler() and entry.chunk==Stream.chunk_key(entry.position) and entry.chunk_min==Stream.chunk_key(bounds.position) and entry.chunk_max==Stream.chunk_key(bounds.end)
	check(old_diff,"actual imported GLB reproduces the former multiplication-order mismatch")
	check(exact,"every canonical visual row equals the independent descriptor pose exactly")
	check(spatial,"canonical real visuals retain world-space position, rotation and chunk coverage")
	check(store.preflight_promotion(additions).ok,"complete canonical namespace passes unchanged strict promotion proof")
	var source_root:Node3D=holder.get_child(0);var original:Transform3D=source_root.transform
	source_root.position.x+=.001;var changed:Array=[];Deferred._collect_collision_asset(holder,changed)
	check(not store.preflight_promotion(changed).ok,"real source node transform change cannot borrow old collision")
	source_root.transform=original
	var wrong:=Cpu.new();wrong.bounds=solid.bounds;wrong._collision_faces=solid.faces.duplicate();wrong._collision_faces[0].x+=.01
	changed=additions.duplicate(true)
	for entry:Dictionary in changed:
		if entry.uuid==solid.uuid:entry.collision_mesh=wrong
	check(not store.preflight_promotion(changed).ok,"same pose cannot conceal changed source triangles")
	check(live.host.get_meta("stream_library").is_empty() and body.get_rid()==rid and body.collision_layer==1,"rejected source changes cause no visual or physics publication side effects")
	var appended:=Stream.append_specs(live.host,additions)
	check(appended.ok,"canonical ordinary visual publication promotes the real typed collision product")
	if not appended.ok:print(appended)
	var promoted:Variant=live.host.get_meta("stream_bodies",{}).get(solid.uuid)
	check(promoted==body and body.get_instance_id()==id and body.get_rid()==rid and int(body.get_meta("stream_physics_published_frame"))==stamp,"promotion keeps the exact body ID, physics RID and publication watermark")
	Stream.sync(live.host,live.host,solid.transform.origin)
	check(live.host.get_meta("stream_meshes",{}).has(solid.uuid),"ordinary Stream shows the actual nested visual after canonical promotion")
	await physics_frame;await process_frame
	check(source_rays(live.host,solid.transform)==before,"real ray outcomes remain unchanged through render handoff")
	holder.free();Drainer.dispose_result(prepared);live.viewport.free()

func source_rays(host:Node3D,pose:Transform3D)->Dictionary:
	var pairs:Dictionary={"wall":[Vector3(-3,1,-2),Vector3(-3,1,2)],"door":[Vector3(0,1,-2),Vector3(0,1,2)],"floor":[Vector3(-3,1,-2),Vector3(-3,-1,-2)],"hole":[Vector3(3.5,1,1.5),Vector3(3.5,-1,1.5)]}
	var result:Dictionary={}
	for key:String in pairs:
		var query:=PhysicsRayQueryParameters3D.create(pose*pairs[key][0],pose*pairs[key][1],1);query.hit_back_faces=true
		result[key]=not host.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	return result

func finish(errors:RefCounted)->void:
	if files!=null:files.free();files=null
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script or engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_CANONICAL_PROMOTION_GPU checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
