extends SceneTree
## Read-only isolation of a ranked real instance: native worker, template pack,
## asset construction, spec projection and private-node disposal. No GLB import.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const ROOT="D:/code/rmmo_runtime"
var failures:Array=[]
var output:=""
var map_path:=""
var uuid:=""
var draw_between:=false
var dirty_private_count:=0
var queued_shader_path:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9).replace("\\","/")
		elif arg.begins_with("--map="):map_path=arg.substr(6).replace("\\","/")
		elif arg.begins_with("--uuid="):uuid=arg.substr(7)
		elif arg=="--draw-between":draw_between=true
		elif arg.begins_with("--dirty-private-count="):dirty_private_count=int(arg.get_slice("=",1))
		elif arg.begins_with("--queued-shader="):queued_shader_path=arg.substr(16).replace("\\","/")
	if dirty_private_count<0 or dirty_private_count>32768:quit(2);return
	if not queued_shader_path.is_empty() and (not queued_shader_path.begins_with(ROOT+"/review_artifacts/") or not FileAccess.file_exists(queued_shader_path)):quit(2);return
	if not output.begins_with(ROOT+"/review_artifacts/") or not map_path.begins_with(ROOT+"/review_artifacts/") or uuid.is_empty():quit(2);return
	check(DisplayServer.get_name()!="headless","actual renderer on private desktop")
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);root.size=Vector2i(512,512)
	var map_sha:=FileAccess.get_sha256(map_path)
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(map_path));var compact:Dictionary={}
	for node:Dictionary in document.nodes:
		for row:Dictionary in node.get("extras",{}).get("rmmo_records",[]):
			if row.uuid==uuid:compact=row;break
	check(not compact.is_empty(),"ranked UUID exists in the fixed map snapshot")
	if compact.is_empty():quit(1);return
	var hydrated:=Store.read_records([compact],map_path,ROOT,null,1,true)
	check(hydrated.ok and hydrated.records.size()==1,"read the exact instance definition without rewriting it")
	if not hydrated.ok:quit(1);return
	var record:Dictionary=hydrated.records[0]
	check(record.get("kind")=="asset" and not record.has("house_prefab"),"ranked instance uses the ordinary native asset cursor")
	if record.get("kind")!="asset" or record.has("house_prefab"):quit(1);return
	var path:String=record.asset_path;var candidate:=Assets.native_candidate(path,ROOT)
	check(not candidate.is_empty(),"native product exists independently of logical source extension")
	if candidate.is_empty():quit(1);return
	var report:={"uuid":uuid,"record":record,"candidate":candidate,"map_sha":map_sha,"engine":Engine.get_version_info(),"draw_between":draw_between,"dirty_private_count":dirty_private_count,"interference":[],"units":[],"iterations":[],"failures":failures}
	if not queued_shader_path.is_empty():report.queued_shader={"path":queued_shader_path,"sha256":FileAccess.get_sha256(queued_shader_path)}
	var worker:=Thread.new();Trace.minimum_event_us=0;Trace.start()
	var began:=Time.get_ticks_usec()
	check(worker.start(Deferred._prepare_fixed_scene.bind(path,candidate.source_sha,null,{},false,ROOT,candidate,Deferred.CollisionGeometry.ALL,true,false))==OK,"same native preparation runs on one actual worker")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish();report.prepare_us=Time.get_ticks_usec()-began
	check(packet.get("error","missing")=="" and is_instance_valid(packet.get("scene")),"native worker returns a complete private graph")
	if not packet.get("error","").is_empty() or not is_instance_valid(packet.get("scene")):Drainer.dispose_result(packet);quit(1);return
	began=Time.get_ticks_usec();Drainer.synchronize_transfer();report.join_sync_us=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec();check(Assets.cache_scene(path,packet.scene,candidate.source_sha),"real template cache publication succeeds")
	report.cache_us=Time.get_ticks_usec()-began;packet.erase("scene")
	var template:PackedScene=Assets._scenes.get(path)
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	doc.load_immutable_records=true;doc.load_require_native_products=true;doc.load_paint_validation={};doc.load_material_pool={};doc.load_texture_checks={}
	var stage:=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();stage.add_child(camera);camera.current=true
	var target:=Vector3(record.position[0],record.position[1],record.position[2])
	camera.position=target+Vector3(0,2,5);camera.look_at(target+Vector3(0,.5,0))
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.shadow_enabled=true;stage.add_child(light)
	for iteration:int in 3:
		var cursor:=preload("res://scripts/world3d/asset_instance_preparation.gd").new()
		began=Time.get_ticks_usec();cursor.begin(doc,record,template)
		report.units.append({"iteration":iteration,"stage":"asset_begin","us":Time.get_ticks_usec()-began})
		var ready:=false
		while not ready:
			began=Time.get_ticks_usec();ready=cursor.advance(2000)
			report.units.append({"iteration":iteration,"stage":"asset_step","us":Time.get_ticks_usec()-began})
			if not ready:await process_frame
		var holder:Node3D=cursor.take_holder()
		check(not holder.has_meta("missing_asset") and not holder.has_meta("paint_error"),"real record constructs successfully, iteration="+str(iteration))
		var spec_cursor:=preload("res://scripts/world3d/instance_spec_preparation.gd").new();spec_cursor.begin(holder,false,0)
		# A scaling diagnostic for unrelated pending renderer instances. They
		# borrow the real asset's mesh, remain outside the SceneTree, and are
		# retained until the measured graph is fully disposed. No fake sleep.
		var unrelated:Array[MeshInstance3D]=[]
		if dirty_private_count>0:
			var source_mesh:Mesh=holder.find_children("*","MeshInstance3D",true,false)[0].mesh
			began=Time.get_ticks_usec()
			for item:int in dirty_private_count:
				var pending:=MeshInstance3D.new();pending.mesh=source_mesh;unrelated.append(pending)
			report.interference.append({"iteration":iteration,"create_us":Time.get_ticks_usec()-began,"instances":unrelated.size()})
		# Exact shader text read from the real stalled material. It is owned by
		# an unrelated material, never by the graph about to be disposed.
		var unrelated_material:ShaderMaterial
		if not queued_shader_path.is_empty():
			began=Time.get_ticks_usec()
			var shader:=Shader.new();shader.code=FileAccess.get_file_as_string(queued_shader_path)
			unrelated_material=ShaderMaterial.new();unrelated_material.shader=shader
			check(unrelated_material.get_rid().is_valid(),"unrelated captured shader enters the real dirty-material queue")
			report.units.append({"iteration":iteration,"stage":"unrelated_material_create","us":Time.get_ticks_usec()-began})
		ready=false
		while not ready:
			began=Time.get_ticks_usec();ready=spec_cursor.advance(2000)
			report.units.append({"iteration":iteration,"stage":"spec_step","us":Time.get_ticks_usec()-began})
			if not ready:await process_frame
		check(not is_instance_valid(holder) and not spec_cursor.specs.is_empty(),"private graph is fully disposed while projected geometry survives")
		report.iterations.append({"asset":cursor.profile.duplicate(),"spec":spec_cursor.profile.duplicate(),"specs":spec_cursor.specs.size()})
		began=Time.get_ticks_usec()
		for pending:MeshInstance3D in unrelated:pending.free()
		if dirty_private_count>0:report.interference.back().release_us=Time.get_ticks_usec()-began
		var visuals:Array[Node]=[]
		if draw_between:
			for spec:Dictionary in spec_cursor.specs:
				var visual:MeshInstance3D=preload("res://scripts/world3d/world_stream.gd")._spawn(stage,spec)
				stage.add_child(visual);visuals.append(visual)
			for frame:int in 3:await process_frame
		for visual:Node in visuals:visual.free()
		spec_cursor.specs.clear();await process_frame
		unrelated_material=null
	report.trace=Trace.stop();report.units.sort_custom(func(a,b):return a.us>b.us)
	stage.free();doc=null;template=null;Assets.evict_cached_scene(path);Drainer.dispose_result(packet);Drainer.synchronize_transfer()
	check(FileAccess.get_sha256(map_path)==map_sha,"fixed source map remains unchanged")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NATIVE_INSTANCE_LIFECYCLE ",JSON.stringify({"prepare_us":report.prepare_us,"join_sync_us":report.join_sync_us,"cache_us":report.cache_us,"slow_units":report.units.slice(0,8),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
