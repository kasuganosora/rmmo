extends SceneTree
## Explicit offline command; writes only derived exact collision products.
## Real models should use run_godot_background.py on the private desktop.
## --asset=... (repeatable) | --paths-json=...; --content-root=...; --output=...
const Builder=preload("res://scripts/world3d/collision_asset_builder.gd")
const Descriptor=preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var _worker:Thread
var _token:RefCounted
var _ledger:=Admission.new()
var _current:=""
func _initialize()->void:run.call_deferred()
func fail(message:String)->void:push_error("COLLISION_ASSET_BUILD: "+message);quit(1)
func run()->void:
	var assets:Array[String]=[];var root_path:=Paths.external_root();var output:="";var list_path:="";var verify_reader:=false
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="):assets.append(argument.trim_prefix("--asset="))
		elif argument.begins_with("--paths-json="):list_path=argument.trim_prefix("--paths-json=")
		elif argument.begins_with("--content-root="):root_path=argument.trim_prefix("--content-root=")
		elif argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		elif argument=="--verify-reader":verify_reader=true
		else:fail("unknown argument: "+argument);return
	if not list_path.is_empty():
		var file:=FileAccess.open(list_path,FileAccess.READ)
		if file==null or file.get_length()>1048576:fail("unreadable or oversized paths JSON");return
		var values:Variant=JSON.parse_string(file.get_as_text());file.close()
		if not values is Array or values.size()>4096:fail("expected bounded string list");return
		for value:Variant in values:
			if not value is String:fail("path is not a string");return
			if value not in assets:assets.append(value)
	if assets.is_empty() or root_path.is_empty():fail("asset and explicit content root required");return
	for path:String in assets:
		if not Paths.allowed(path,root_path):fail("source is outside content root");return
	if output.is_empty():output=Descriptor.directory(root_path).path_join("build_report.json")
	var reviews:=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("rmmo_runtime/review_artifacts")
	if output.get_extension().to_lower()!="json" or (not Paths.allowed(output,Descriptor.directory(root_path)) and not Paths.allowed(output,reviews)):
		fail("report must be under collision cache or runtime review_artifacts");return
	_ledger.worker_limit=1
	var rows:Array=[];var failures:=0
	for path:String in assets:
		var producer_started:=Time.get_ticks_usec()
		_current=path;var estimate:=Builder.estimate(path,root_path)
		if estimate.is_empty() or not _ledger.reserve(path,estimate):
			rows.append({"path":path,"ok":false,"reason":"unsupported_or_admission"});failures+=1;continue
		_worker=Thread.new();_token=Drainer.CancelToken.new()
		if verify_reader:Trace.start()
		var started:=Time.get_ticks_usec();var code:int=_worker.start(Builder.build.bind(path,root_path,estimate.estimated_bytes,_token))
		if code!=OK:
			_worker=null;_ledger.release(path);rows.append({"path":path,"ok":false,"reason":"thread_start"});failures+=1;continue
		while _worker.is_alive():await process_frame
		var result:Dictionary=_worker.wait_to_finish();_worker=null;_ledger.park(path)
		var row:Dictionary={"path":path,"ok":result.get("ok",false),"reason":result.get("reason",""),"elapsed_us":Time.get_ticks_usec()-started,"admitted_bytes":estimate.estimated_bytes,"candidate":result.get("candidate",{}).duplicate(true)}
		var expected:Array=[]
		if verify_reader:
			row.producer_trace=Trace.stop()
			if row.ok:expected=_scene_snapshot(result.private_preparation.scene)
		# Main fence/free occurs before the full import+workspace lease is released.
		Drainer.dispose_result(result);_ledger.release(path);_token=null
		row.producer_total_us=Time.get_ticks_usec()-producer_started
		if verify_reader and row.ok:
			var frozen:Dictionary=row.candidate
			var read_estimate:Dictionary={"estimated_bytes":int(frozen.estimated_bytes),"exclusive":false,"stage":"collision_asset_read"}
			if not _ledger.reserve(path,read_estimate):row.ok=false;row.reason="read_admission"
			else:
				_worker=Thread.new();_token=Drainer.CancelToken.new();Trace.start()
				var read_start:=Time.get_ticks_usec();var read_code:int=_worker.start(Descriptor.read.bind(frozen,root_path,int(frozen.estimated_bytes),_token))
				if read_code!=OK:
					_worker=null;row.ok=false;row.reason="reader_thread";Trace.stop()
				else:
					while _worker.is_alive():await process_frame
					var restored:Dictionary=_worker.wait_to_finish();_worker=null;_ledger.park(path)
					row.reader_wall_us=Time.get_ticks_usec()-read_start;row.reader_trace=Trace.stop();row.reader_profile=restored.get("profile",{});row.reader_elapsed_us=restored.get("elapsed_us",0)
					row.exact_geometry_and_transform=false;row.cpu_unique_triangles=0
					if restored.get("ok",false):
						var actual:=_asset_snapshot(restored.asset);row.exact_geometry_and_transform=actual==expected;row.node_instances=actual.size()
						for i:int in int(frozen.product_count):row.cpu_unique_triangles+=restored.asset.geometry(i).faces.size()/3
					row.reader_import_calls=_label_count(row.reader_trace,"deferred.model_parse");row.reader_scene_calls=_label_count(row.reader_trace,"deferred.scene_generate");row.reader_capture_calls=_label_count(row.reader_trace,"deferred.cpu_capture")
					if not restored.get("ok",false) or not row.exact_geometry_and_transform or row.reader_import_calls!=0 or row.reader_scene_calls!=0 or row.reader_capture_calls!=0:
						row.ok=false;row.reason="reader_parity:"+str(restored.get("reason",""))
					restored.clear()
				_ledger.release(path);_token=null
		rows.append(row);if not row.ok:failures+=1
		print("COLLISION_ASSET ",JSON.stringify(row))
	var report:Dictionary={"version":1,"engine":Engine.get_version_info(),"assets":rows,"failures":failures,"ledger":_ledger.snapshot(),"source_assets_modified":false,"runtime_enabled":Descriptor.enabled,"physics_readiness_granted":false}
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir())!=OK:fail("report directory");return
	var temp:=output+".%d.tmp"%OS.get_process_id();var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:fail("report open");return
	file.store_string(JSON.stringify(report,"\t"));file.flush();var code:int=file.get_error();file.close()
	if code==OK:code=Atomic.publish(temp,output) if FileAccess.file_exists(output) else DirAccess.rename_absolute(temp,output)
	if FileAccess.file_exists(temp):DirAccess.remove_absolute(temp)
	if code!=OK:fail("report publish");return
	print("COLLISION_ASSET_BUILD_COMPLETE failures=",failures," report=",output);quit(0 if failures==0 else 1)
func _finalize()->void:
	if _worker!=null and _worker.is_started():Drainer.drain_shutdown(_worker,_token)
	_ledger.release(_current)

func _label_count(trace:Dictionary,label:String)->int:
	var count_:=0
	for row:Dictionary in trace.get("stats",[]):
		if row.label==label:count_+=int(row.count)
	return count_
func _scene_snapshot(node:Node,pose:Transform3D=Transform3D.IDENTITY,selector:String="root")->Array:
	var rows:Array=[]
	if node is Node3D:pose=pose*node.transform
	if node is MeshInstance3D:
		var mesh:Mesh=node.get_meta("collision_solid",node.get_meta("paint_source",node.mesh))
		var cpu:Cpu=mesh if mesh is Cpu else mesh.get_meta("ground_cpu_cache")
		rows.append({"selector":selector,"transform":pose,"faces_sha":Descriptor.Products._digest(cpu._collision_faces.to_byte_array()),"box":cpu.box_size,"collision":Io.extras_of(node).get("rmmo_collision","")})
	for index:int in node.get_child_count():rows.append_array(_scene_snapshot(node.get_child(index),pose,selector+"/"+str(index)))
	return rows
func _asset_snapshot(asset:RefCounted)->Array:
	var rows:Array=[]
	for entry:Dictionary in asset.entries():
		var geometry:Dictionary=asset.geometry(entry.product)
		rows.append({"selector":entry.selector,"transform":entry.transform,"faces_sha":Descriptor.Products._digest(geometry.faces.to_byte_array()),"box":geometry.box,"collision":entry.collision})
	return rows
