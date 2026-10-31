extends "res://tools/test_world3d_mcp.gd"
## Real-GPU native-only consumption, failure retirement and HTTP editing.
## Only temporary GLBs/maps plus their derived products are written.
const Job=preload("res://scripts/world_editor/load_job.gd")
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Native=preload("res://scripts/world3d/compiled_asset_preparation.gd")
var passed:=0
var results:Array=[]
var temporary_directory:=""

class Lifetime extends RefCounted:
	var audit:RefCounted
	var kind:String
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and audit!=null:audit.released(kind)

class Audit extends RefCounted:
	var ledger:WeakRef
	var resources:Array=[]
	var releases:Array=[]
	var starts:Array=[]
	var native_packet:Dictionary={}
	var native_action:=""
	var native_reason:=""
	var observe_lifetime:=true
	var seen:Dictionary={}
	var mutex:=Mutex.new()
	func observe(resource:Resource,kind:String)->void:
		if resource==null or seen.has(resource.get_instance_id()):return
		seen[resource.get_instance_id()]=true
		if observe_lifetime:
			var marker:=Lifetime.new();marker.audit=self;marker.kind=kind
			resource.set_meta("native_admission_gpu_lifetime",marker)
		resources.append({"weak":weakref(resource),"kind":kind})
	func observe_packed(packed:PackedScene)->void:
		observe(packed,"packed")
		var state:=packed.get_state()
		for node in state.get_node_count():
			for property in state.get_node_property_count(node):
				var value:Variant=state.get_node_property_value(node,property)
				if value is Mesh:
					observe(value,"mesh")
					for surface in value.get_surface_count():
						var material:Material=value.surface_get_material(surface)
						if material!=null:
							observe(material,"material")
							if material is BaseMaterial3D and material.albedo_texture!=null:observe(material.albedo_texture,"texture")
	func released(kind:String)->void:
		var thread_id:=OS.get_thread_caller_id()
		var owner:RefCounted=ledger.get_ref() if ledger!=null and thread_id==OS.get_main_thread_id() else null
		mutex.lock();releases.append({"kind":kind,"thread":thread_id,"charged_bytes":owner.reserved_bytes if owner!=null else -1});mutex.unlock()
	func alive()->bool:
		for row:Dictionary in resources:
			if row.weak.get_ref()!=null:return true
		return false
	func charged_main_retirement()->bool:
		if releases.size()!=resources.size() or resources.is_empty() or alive():return false
		for row:Dictionary in releases:
			if row.thread!=OS.get_main_thread_id() or row.charged_bytes<=0:return false
		return true
	func read_native(path:String,content_root:String,candidate:Dictionary)->Dictionary:
		var parsed:=Job._parse_native_asset(path,content_root,candidate)
		native_packet=parsed;native_action=Job._native_result_action(candidate,parsed)
		native_reason=str(parsed.get("cache_reason",""))
		if parsed.get("packed") is PackedScene:observe_packed(parsed.packed)
		return parsed
	func start(worker:Thread,task:Callable,queue:Node,key:String)->int:
		var row:Dictionary=queue.rows[key]
		starts.append({"stage":row.estimate.get("stage",""),"bytes":queue.ledger.reserved_bytes,
			"estimate":row.estimate.duplicate(),"native_alive":alive(),"packet_empty":native_packet.is_empty()})
		return worker.start(task,Thread.PRIORITY_LOW)

func check(ok:bool,label:String)->void:
	super.check(ok,label)
	if ok:passed+=1

func put(path:String,bytes:PackedByteArray)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(bytes);file.flush();var ok:=file.get_error()==OK;file.close()
	return ok and FileAccess.get_file_as_bytes(path)==bytes

func fixture(path:String,width:float,texture_size:int,color:Color)->bool:
	var model:=Node3D.new();model.name="NativeFixture_%d"%Time.get_ticks_usec()
	var mesh:=MeshInstance3D.new();mesh.name="ExactBox";var box:=BoxMesh.new();box.size=Vector3(width,2,3)
	var image:=Image.create(texture_size,texture_size,false,Image.FORMAT_RGBA8);image.fill(color)
	var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(image);box.material=material;mesh.mesh=box
	model.add_child(mesh);mesh.owner=model
	var err:=Io.save_scene(model,path)
	Drainer.dispose_scene(model)
	if err!=OK:return false
	# This fixture is an ordinary external model, not a Godot-root scene. The
	# exporter declares GODOT_single_root despite using a plain glTF node graph;
	# remove only that optional declaration in our temporary generated document.
	var bytes:=FileAccess.get_file_as_bytes(path)
	var json_size:=bytes.decode_u32(12)
	var data:Dictionary=JSON.parse_string(bytes.slice(20,20+json_size).get_string_from_utf8())
	var used:Array=data.get("extensionsUsed",[]);used.erase("GODOT_single_root")
	data["extensionsUsed"]=used
	var header:=JSON.stringify(data).to_utf8_buffer()
	while header.size()%4:header.append(32)
	var binary:=bytes.slice(20+json_size)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_32(0x46546c67);file.store_32(2);file.store_32(20+header.size()+binary.size())
	file.store_32(header.size());file.store_32(0x4e4f534a);file.store_buffer(header);file.store_buffer(binary);file.close()
	return true

func first_mesh(node:Node)->MeshInstance3D:
	if node is MeshInstance3D:return node
	for child in node.get_children():
		var found:=first_mesh(child)
		if found!=null:return found
	return null

func scene_matches(scene:Node,width:float,texture_size:int)->bool:
	if not is_instance_valid(scene):return false
	var mesh:=first_mesh(scene)
	if mesh==null or mesh.mesh==null or not is_equal_approx(mesh.mesh.get_aabb().size.x,width):return false
	var material:Material=mesh.get_active_material(0)
	return material is BaseMaterial3D and material.albedo_texture!=null and material.albedo_texture.get_width()==texture_size

func prepare_fixture_job(path:String,candidate:Dictionary)->Dictionary:
	Library._scenes.erase(path)
	var job:=Job.new();root.add_child(job)
	job._timings={"build":{"units":{}},"asset_lookahead":{"ready_on_consume":0,"native_retries":0,"native_retry_reasons":{},"consumed":0,"started":0,"start_failures":0,"peak_unconsumed":0,"compiled_hits":0,"compiled_misses":0}}
	job._model_candidates[path]=candidate.duplicate(true)
	var queue:=Queue.new();job.add_child(queue);job._preparation=queue
	var audit:=Audit.new();audit.ledger=weakref(queue.ledger)
	var key:="model:"+path
	queue.thread_starter=audit.start.bind(queue,key)
	var estimate:={"estimated_bytes":int(candidate.estimated_bytes),"exclusive":bool(candidate.exclusive),"stage":"compiled_read"}
	check(queue.enqueue(key,audit.read_native.bind(path,Paths.external_root(),candidate),estimate),"real native reader queued under fixed product footprint")
	return {"job":job,"queue":queue,"audit":audit,"key":key}

func direct_case(path:String,candidate:Dictionary,mode:String,width:float,texture_size:int)->void:
	var fixture_job:=prepare_fixture_job(path,candidate)
	var job:Node=fixture_job.job;var queue:Node=fixture_job.queue;var audit:Audit=fixture_job.audit
	var packet:Dictionary=await job._prepare_asset({"kind":"asset","asset_path":path,"uuid":"direct_"+mode})
	var expected_failure:bool=mode in ["corrupt_product","missing_product"]
	if expected_failure:
		check(packet.get("scene")==null and not Library._scenes.has(path),mode+": failed native product never publishes a scene or cache owner")
		check(audit.native_action=="reject" and job._timings.asset_lookahead.compiled_misses==1,mode+": native failure stays a failure without importing the available GLB")
		check(audit.native_reason==("candidate_checksum" if mode=="corrupt_product" else "candidate_size") and audit.resources.is_empty(),mode+": explicit failure is detected before native resource allocation")
	else:
		check(scene_matches(packet.get("scene"),width,texture_size),mode+": real LoadJob publishes the admitted native geometry and texture")
		check(Library._scenes.has(path),mode+": accepted scene enters shared instance cache")
		check(audit.native_action=="ready" and job._timings.asset_lookahead.compiled_hits==1,mode+": admitted native product records one successful publication")
		check(audit.resources.any(func(row):return row.kind=="mesh") and audit.resources.any(func(row):return row.kind=="texture"),mode+": observes real native mesh and texture owners")
	check(audit.starts.size()==1 and audit.starts[0].stage=="compiled_read" and audit.starts[0].bytes==candidate.estimated_bytes,mode+": exactly one native worker uses the admitted native footprint")
	check(queue.metrics.raw_retries==0 and job._timings.asset_lookahead.native_retries==0,mode+": no source readmission or raw importer")
	check(queue.ledger.reserved_bytes==0 and queue.rows[fixture_job.key].state=="done",mode+": consumed result returns complete lease")
	check(audit.native_packet.is_empty(),mode+": native result aliases are cleared by owner")
	results.append({"mode":mode,"starts":audit.starts.duplicate(true),"releases":audit.releases.duplicate(true),"native_reason":audit.native_reason,"queue":queue.snapshot()})
	Drainer.dispose_result(packet);Library._scenes.erase(path);Drainer.synchronize_transfer()
	job.free();await process_frame

func cancel_case(path:String,candidate:Dictionary)->void:
	var value:=prepare_fixture_job(path,candidate);var queue:Node=value.queue;var audit:Audit=value.audit
	var deadline:=Time.get_ticks_msec()+15000
	while not queue.is_ready(value.key) and Time.get_ticks_msec()<deadline:await process_frame
	check(queue.is_ready(value.key),"native cancellation fixture joins real GPU reader")
	check(audit.alive() and queue.ledger.reserved_bytes==candidate.estimated_bytes,"joined unconsumed native GPU resources retain full reservation")
	queue.cancel()
	check(queue.ledger.reserved_bytes==0 and audit.native_packet.is_empty(),"cancelling ready native packet clears aliases and returns lease")
	check(audit.charged_main_retirement(),"ready cancellation destroys real renderer resources on main before returning credit")
	value.job.free();await process_frame

func http_case(path:String)->void:
	var doc:=Doc.new();var first:String=doc.add_asset({"asset_path":path},Vector3.ZERO)
	var second:String=doc.add_asset({"asset_path":path},Vector3(5,0,0))
	var map_path:=temporary_directory.path_join("map.gltf")
	check(doc.save(map_path)==OK,"temporary two-instance reference map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=map_path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=temporary_directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real 3D HTTP MCP server started")
	var discovery:=await rpc("tools/list")
	var names:Array=discovery.get("result",{}).get("tools",[]).map(func(tool):return tool.name)
	check(["open_world","place_asset","delete_selection","undo","save_world"].all(func(name_):return name_ in names),"HTTP tool discovery exposes load and ordinary editing operations")
	Library._scenes.erase(path)
	await call_tool("open_world",{"path":map_path})
	var metrics:Dictionary=editor._load_job.state().timings
	check(metrics.asset_lookahead.native_footprints_enabled and metrics.asset_lookahead.native_candidates==1 and metrics.asset_lookahead.compiled_hits==1,"HTTP open uses one native footprint candidate for both instances")
	check(metrics.preparation.ledger.reserved_bytes==0 and metrics.preparation.raw_retries==0,"HTTP completed native load releases every preparation lease")
	var a:Node=editor._view.get_node(first);var b:Node=editor._view.get_node(second)
	check(a!=b and scene_matches(a,1,8) and scene_matches(b,1,8),"native shared resource produces independent visual instances with texture")
	check(editor._bodies_by_uuid.has(first) and editor._bodies_by_uuid.has(second),"both instances have independent exact picking bodies")
	await call_tool("select_objects",{"ids":[first]})
	await call_tool("set_object_transform",{"id":first,"position":[1,0,0]})
	check(equivalent(editor._doc._find(second).position,[5,0,0]),"moving first instance preserves second record position")
	check(editor._view.get_node(second)==b,"moving first instance preserves second visual identity")
	await call_tool("undo");await call_tool("redo")
	var entry:={"asset_path":path,"label":"Temporary native fixture","category":"test","bounds_position":[-.5,-1,-1.5],"bounds_size":[1,2,3]}
	editor._assets.entries.append(entry)
	var placed:=await call_tool("place_asset",{"asset_id":preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(entry),"position":[10,0,0]})
	var third:String=str(placed.get("ids",[""])[0])
	check(not third.is_empty() and scene_matches(editor._view.get_node_or_null(third),1,8),"HTTP placement reuses valid model while retaining a new UUID")
	await call_tool("select_objects",{"ids":[third]});await call_tool("delete_selection")
	check(editor._doc._find(third).is_empty(),"HTTP deletion removes only placed instance")
	await call_tool("undo");check(not editor._doc._find(third).is_empty(),"undo restores original placed UUID")
	await call_tool("redo");check(editor._doc.records.size()==2,"redo returns original two-instance document")
	var before: Array=editor._doc.records.duplicate(true)
	await call_tool("save_world")
	Library._scenes.erase(path)
	await call_tool("open_world",{"path":map_path})
	check(equivalent(before,editor._doc.records) and scene_matches(editor._view.get_node(first),1,8),"HTTP save/reopen preserves records geometry material and texture")
	var retained:Node=editor._view
	await call_tool("open_world",{"path":temporary_directory.path_join("absent.gltf")},false)
	check(editor._view==retained and not editor._load_job.active,"failed HTTP open has no scene side effects")
	editor.queue_free();await settle();editor=null;Library._scenes.erase(path)

func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Run via tools/run_godot_background.py with a GPU backend");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=30000
	create_timer(150).timeout.connect(func():quit(2))
	var original_setting:bool=Job.native_model_footprints_enabled
	var require_default:bool="--require-native-default" in OS.get_cmdline_user_args()
	if require_default:
		check(original_setting,"production default enables staged native model admission")
		if not original_setting:quit(1);return
	else:Job.native_model_footprints_enabled=true
	var previous_precheck:bool=Native.source_precheck_enabled;Native.source_precheck_enabled=false
	var previous_audit:bool=Policy.verify_packages;Policy.verify_packages=false
	temporary_directory=Paths.cache_directory("native_admission_gpu_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(temporary_directory)
	var path:=temporary_directory.path_join("fixture.glb");var changed:=temporary_directory.path_join("changed.glb")
	check(fixture(path,1,8,Color(.7,.2,.1)),"small self-contained textured GLB exported")
	check(fixture(changed,4,32,Color(.1,.6,.2)),"different import source exported to detect forbidden source replacement")
	var original:=FileAccess.get_file_as_bytes(path);var replacement:=FileAccess.get_file_as_bytes(changed)
	var built:=Compiled.build(path);check(built.get("ok",false),"real native PackedScene cache built")
	var measured:=Footprint.build(path);check(measured.get("ok",false),"real resource footprint sidecar measured and built")
	var candidate:=Footprint.candidate(path,Paths.external_root())
	check(not candidate.is_empty(),"source-bound native candidate available")
	if candidate.is_empty():print("FIXTURE_FAILURE ",built," ",measured);quit(1);return
	var product:String=candidate.product;var product_bytes:=FileAccess.get_file_as_bytes(product)
	await direct_case(path,candidate,"native_hit",1,8)
	check(put(path,replacement),"replacement source committed before frozen native candidate is enqueued")
	await direct_case(path,candidate,"source_changed",1,8)
	check(put(path,original),"original temporary source restored after native-only load")
	check(DirAccess.rename_absolute(product,product+".held")==OK,"temporarily hide private native product while valid GLB remains")
	await direct_case(path,candidate,"missing_product",1,8)
	check(DirAccess.rename_absolute(product+".held",product)==OK,"restore private native product after failure")
	var damaged:=product_bytes.duplicate();damaged[-1]=damaged[-1]^1
	check(put(product,damaged),"unique temporary derived product damaged at same length")
	Policy.verify_packages=true # Explicit audit fixture, never a production load requirement.
	await direct_case(path,candidate,"corrupt_product",1,8)
	Policy.verify_packages=false
	check(put(product,product_bytes) and FileAccess.get_sha256(product)==candidate.payload_sha,"temporary native product restored exactly")
	await cancel_case(path,candidate)
	check(DirAccess.rename_absolute(path,path+".held")==OK and not FileAccess.file_exists(path),"remove private GLB before direct load and actual HTTP editing")
	await direct_case(path,candidate,"source_absent",1,8)
	await http_case(path)
	check(not FileAccess.file_exists(path),"HTTP open place undo save and reopen never recreate the absent GLB")
	check(DirAccess.rename_absolute(path+".held",path)==OK,"restore private authoring fixture after HTTP test")
	check(FileAccess.get_sha256(path)==candidate.source_sha and FileAccess.get_sha256(product)==candidate.payload_sha,"temporary source and compiled product end at their original identities")
	Job.native_model_footprints_enabled=original_setting;Native.source_precheck_enabled=previous_precheck;Policy.verify_packages=previous_audit
	var report:={"passed":passed,"failures":failed,"fixture_directory":temporary_directory,"cases":results,"native_enabled_only_for_test":not require_default,"native_production_default":original_setting}
	write_report(report)
	print("EDITOR_NATIVE_ADMISSION_GPU passed=",passed," failures=",failed);quit(1 if failed else 0)

func write_report(report:Dictionary)->void:
	var output:=temporary_directory.path_join("report.json")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not output.is_absolute_path() or not Paths.allowed(output,Paths.external_root()):
		check(false,"report stays inside external runtime");return
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:check(false,"report can be written");return
	file.store_string(JSON.stringify(report,"\t"));file.close()
