extends SceneTree
## Temporary headless native product and footprint. No real assets or GPU.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Reader=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const ModelPreparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const EditorLoadJob=preload("res://scripts/world_editor/load_job.gd")
const EditorQueue=preload("res://scripts/world_editor/load_preparation_queue.gd")
class NoRawPreparation extends "res://scripts/world3d/model_parse_preparation.gd":
	var raw_calls:=0
	func _guarded_fallback(path:String,parse:Callable,require_eligible:bool)->Dictionary:
		raw_calls+=1;return super._guarded_fallback(path,parse,require_eligible)
var passed:=0
var failed:=0
var content_root:=""
var source:=""
var candidate:Dictionary={}

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1

func write_bytes(path:String,data:PackedByteArray)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(data);file.flush();var error:=file.get_error();file.close()
	return error==OK

func write_text(path:String,data:String)->bool:
	return write_bytes(path,data.to_utf8_buffer())

func mutate_descriptor(field:String,value:Variant)->bool:
	var path:=Footprint.descriptor_path(source,content_root)
	var envelope:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not envelope is Dictionary or not envelope.get("body") is String:return false
	var descriptor:Variant=JSON.parse_string(envelope.body)
	if not descriptor is Dictionary:return false
	descriptor[field]=value;envelope.body=JSON.stringify(descriptor);envelope.sha256=envelope.body.sha256_text()
	return write_text(path,JSON.stringify(envelope))

func make_coordinator()->NoRawPreparation:
	var job:=NoRawPreparation.new();job.require_native_products=true
	# The test isolates reader/coordinator behavior. MapLoader's full-material
	# metadata and absent-GLB admission are separate, not demonstrated here.
	job.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":128*1024*1024,"exclusive":false,"known":true}
	return job

func editor_history_lookahead(expected:Dictionary)->void:
	var manager:Node=root.get_node_or_null("AssetManager")
	if manager==null:check(false,"editor plan fixture has an asset manager");return
	var previous_root:String=manager.content_root_override;manager.content_root_override=content_root
	var previous_resident:bool=EditorLoadJob.prepared_model_residency_enabled;EditorLoadJob.prepared_model_residency_enabled=false
	var job:=EditorLoadJob.new();root.add_child(job)
	var key:="model:"+source;var record:={"kind":"asset","uuid":"native_fixture","asset_path":source}
	job._begin_asset_lookahead([record,record])
	var queue:Node=job._preparation
	check(queue!=null and queue.has(key) and job._asset_paths.size()==1 and job._model_candidates.has(source) and queue.rows[key].estimate.get("stage")=="compiled_read","actual editor initial plan deduplicates and selects the historical native candidate")
	if queue!=null and queue.has(key) and queue.rows[key].estimate.get("stage")=="compiled_read":
		var planned:Dictionary=job._model_candidates[source]
		check(planned.payload_sha==expected.payload_sha and planned.estimated_bytes==expected.estimated_bytes,"editor initial plan reserves the exact published native product and budget")
		var deadline:=Time.get_ticks_msec()+15000
		while not queue.is_ready(key) and Time.get_ticks_msec()<deadline:await process_frame
		check(queue.is_ready(key),"actual editor initial native worker finishes")
		if queue.is_ready(key):
			var packet:Dictionary=queue.acquire(key)
			check(EditorLoadJob._native_result_action(planned,packet)=="ready" and packet.get("packed") is PackedScene,"actual editor initial plan loads a usable historical native scene")
			queue.release(key)
		else:check(false,"actual editor initial plan loads a usable historical native scene")
	else:
		check(false,"editor initial plan reserves the exact published native product and budget")
		check(false,"actual editor initial native worker finishes")
		check(false,"actual editor initial plan loads a usable historical native scene")
	job._clear_asset_lookahead();job.free();await process_frame
	EditorLoadJob.prepared_model_residency_enabled=previous_resident;manager.content_root_override=previous_root

func editor_reject_old_product_generation(old:Dictionary)->void:
	# Published format identity is authoritative for editor consumption; a
	# conversion can still explicitly request a specific generator revision.
	var manager:Node=root.get_node_or_null("AssetManager")
	if manager==null:check(false,"published product editor fixture has an asset manager");return
	var previous_root:String=manager.content_root_override;manager.content_root_override=content_root
	var job:=EditorLoadJob.new();root.add_child(job)
	job._begin_asset_lookahead([{"kind":"asset","uuid":"native_fixture","asset_path":source}])
	var queue:Node=job._preparation;var key:="model:"+source
	check(queue!=null and queue.has(key) and queue.rows[key].estimate.get("stage")=="compiled_read" and job._model_candidates.has(source),"editor selects compatible published format regardless of producer source hash")
	var worker:=Reader.read(source,old,content_root,Callable(),true,false,"",true)
	check(worker.get("error",FAILED)==OK and worker.get("packed") is PackedScene,"published reader accepts historical producer without source access")
	worker.clear()
	worker=Reader.read(source,old,content_root,Callable(),true,false,Compiled.generator(),true)
	check(worker.get("fallback_required",false) and not worker.has("packed"),"explicit conversion revision still rejects a different producer")
	worker.clear();job._clear_asset_lookahead();job.free();await process_frame
	manager.content_root_override=previous_root

func make_candidate(resource:Resource)->Dictionary:
	var folder:=Compiled.directory(content_root)
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return {}
	# ResourceSaver chooses the writer by extension; non-scene Resources use the
	# binary .res writer before moving into the real .scn product namespace.
	var staged:=folder.path_join("fixture-staged.scn" if resource is PackedScene else "fixture-staged.res")
	if ResourceSaver.save(resource,staged,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)!=OK:return {}
	var digest:=FileAccess.get_sha256(staged)
	var product:=folder.path_join(digest+".scn")
	if DirAccess.rename_absolute(staged,product)!=OK:return {}
	var file:=FileAccess.open(product,FileAccess.READ)
	if file==null:return {}
	var bytes:=file.get_length();file.close()
	return {"source_path":source,"source_sha":FileAccess.get_sha256(source),"payload_sha":digest,"generator":Compiled.generator(),"bytes":bytes,"product":product}

func write_footprint(value:Dictionary)->bool:
	var stats:=Footprint.empty_stats();stats.nodes=2;stats.native_uncompressed_bytes=4096
	var estimate:=Footprint.estimate_stats(stats)
	if estimate.is_empty():return false
	var index:={"version":Compiled.VERSION,"source_sha":value.source_sha,"generator":value.generator,"payload_sha":value.payload_sha,"bytes":value.bytes}
	if not write_text(Compiled.index_path(source,content_root),JSON.stringify(index)):return false
	var source_file:=FileAccess.open(source,FileAccess.READ)
	if source_file==null:return false
	var source_bytes:=source_file.get_length();source_file.close()
	var descriptor:Dictionary={"version":Footprint.VERSION,"source_path":source,"source_sha":value.source_sha,"payload_sha":value.payload_sha,"generator":value.generator,"bytes":value.bytes,"source_bytes":source_bytes,"footprint_generator":Footprint.generator(),"stats":stats,"estimated_bytes":estimate.estimated_bytes,"resident_bytes":estimate.resident_bytes}
	var folder:=Footprint.directory(content_root)
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	var body:=JSON.stringify(descriptor)
	return write_text(Footprint.descriptor_path(source,content_root),JSON.stringify({"version":Footprint.VERSION,"body":body,"sha256":body.sha256_text()}))

func make_scene()->PackedScene:
	var node:=Node3D.new();node.name="fixture"
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=StandardMaterial3D.new();material.albedo_color=Color(0.3,0.6,0.8);mesh.surface_set_material(0,material)
	var child:=MeshInstance3D.new();child.name="mesh";child.mesh=mesh;node.add_child(child);child.owner=node
	var packed:=PackedScene.new();var error:=packed.pack(node);node.free()
	return packed if error==OK else null

func label_count(report:Dictionary,label:String)->int:
	var count:=0
	for entry:Dictionary in report.get("stats",[]):
		if entry.get("label")==label:count+=int(entry.get("count",0))
	return count

func fixture_glb()->PackedByteArray:
	var json:PackedByteArray=JSON.stringify({"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"fixture"}]}).to_utf8_buffer()
	while json.size()%4!=0:json.append(32)
	var bytes:=PackedByteArray();bytes.resize(20+json.size())
	bytes.encode_u32(0,0x46546c67);bytes.encode_u32(4,2);bytes.encode_u32(8,bytes.size())
	bytes.encode_u32(12,json.size());bytes.encode_u32(16,0x4e4f534a)
	for i:int in json.size():bytes[20+i]=json[i]
	return bytes

func run()->void:
	var logger:=preload("res://tools/test_deferred_backpressure.gd").Errors.new();OS.add_logger(logger)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-root="):content_root=arg.trim_prefix("--test-root=")
	var base:="D:/code/rmmo_runtime/review_artifacts"
	if content_root.is_empty() or not content_root.is_absolute_path() or not Paths.allowed(content_root,base) or content_root==base:
		check(false,"explicit temporary test content_root inside review_artifacts required");finish(logger);return
	if DirAccess.make_dir_recursive_absolute(content_root)!=OK:
		check(false,"temporary content_root created");finish(logger);return
	source=content_root.path_join("source.glb")
	var original:PackedByteArray=fixture_glb()
	check(write_bytes(source,original),"temporary logical source written")
	var packed:=make_scene();check(packed!=null,"temporary packed scene created")
	if packed==null:finish(logger);return
	candidate=make_candidate(packed);packed=null
	check(not candidate.is_empty(),"actual native product written and identity captured")
	if candidate.is_empty():finish(logger);return
	check(write_footprint(candidate),"complete temporary footprint and index written")
	var offered:Dictionary=Footprint.candidate(source,content_root,candidate.source_sha)
	check(not offered.is_empty() and offered.payload_sha==candidate.payload_sha and int(offered.estimated_bytes)>0,"legacy candidate uses real fixture product and bounded descriptor")
	if offered.is_empty():finish(logger);return
	var trusted_candidate:Dictionary=Footprint.candidate(source,content_root,candidate.source_sha,true)
	check(trusted_candidate==offered,"trusted candidate retains exact strict product identity and accounting budget")
	check(Footprint.candidate(source,content_root,"f".repeat(64),true).is_empty(),"trusted candidate rejects a different requested source identity")
	var descriptor_path:=Footprint.descriptor_path(source,content_root);var index_path:=Compiled.index_path(source,content_root)
	var descriptor_bytes:=FileAccess.get_file_as_bytes(descriptor_path);var index_bytes:=FileAccess.get_file_as_bytes(index_path)
	var wrong_index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index_path));wrong_index.version=Compiled.VERSION+1
	check(write_text(index_path,JSON.stringify(wrong_index)),"fixture writes unsupported index version")
	check(Footprint.candidate(source,content_root,candidate.source_sha,true).is_empty(),"trusted candidate rejects unsupported index version")
	check(write_bytes(index_path,index_bytes),"fixture restores supported index version")
	for field:String in ["source_path","source_sha","payload_sha","generator","bytes","version"]:
		var replacement:Variant=999 if field in ["bytes","version"] else ("f".repeat(64) if field in ["source_sha","payload_sha"] else "different")
		check(mutate_descriptor(field,replacement),"fixture mutates descriptor "+field)
		check(Footprint.candidate(source,content_root,candidate.source_sha,true).is_empty(),"trusted candidate rejects mismatched descriptor "+field)
		check(write_bytes(descriptor_path,descriptor_bytes),"fixture restores descriptor "+field)
	for invalid:Variant in [0,-1,Footprint.MAX_BYTES+1,1.5]:
		check(mutate_descriptor("estimated_bytes",invalid),"fixture writes invalid budget")
		check(Footprint.candidate(source,content_root,candidate.source_sha,true).is_empty(),"trusted candidate rejects invalid budget "+str(invalid))
		check(write_bytes(descriptor_path,descriptor_bytes),"fixture restores valid budget")
	check(mutate_descriptor("resident_bytes",int(offered.estimated_bytes)+1),"fixture writes unequal resident budget")
	check(Footprint.candidate(source,content_root,candidate.source_sha,true).is_empty(),"trusted candidate rejects unequal resident budget")
	check(write_bytes(descriptor_path,descriptor_bytes),"fixture restores resident budget")
	var envelope:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor_path));envelope.sha256="0".repeat(64)
	check(write_text(descriptor_path,JSON.stringify(envelope)),"fixture changes only descriptor authentication")
	check(not Footprint.candidate(source,content_root,candidate.source_sha,true).is_empty() and Footprint.candidate(source,content_root,candidate.source_sha,false).is_empty(),"trusted package skips body authentication while strict audit rejects it")
	check(write_bytes(descriptor_path,descriptor_bytes),"fixture restores descriptor authentication")
	var history:="b".repeat(64);var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index_path));index.generator=history
	check(write_text(index_path,JSON.stringify(index)) and mutate_descriptor("generator",history),"fixture publishes consistent historical generator")
	var historic:Dictionary=Footprint.candidate(source,content_root,candidate.source_sha,true)
	check(not historic.is_empty() and Footprint.candidate(source,content_root,candidate.source_sha,false).is_empty(),"trusted candidate accepts matching historical generator and strict audit rejects it")
	await editor_reject_old_product_generation(historic)
	var historic_read:=Reader.read(source,historic,content_root,Callable(),true)
	check(historic_read.get("error",FAILED)==OK and historic_read.get("packed") is PackedScene,"trusted reader accepts the exact historical product identity")
	historic_read.clear();check(write_bytes(index_path,index_bytes) and write_bytes(descriptor_path,descriptor_bytes),"fixture restores current index and descriptor")
	check(mutate_descriptor("footprint_generator","previous-footprint-source-hash"),"fixture installs a prior footprint generator")
	check(Footprint.candidate(source,content_root,candidate.source_sha,false).is_empty(),"strict candidate rejects the prior footprint generator")
	await editor_history_lookahead(offered)
	check(write_bytes(descriptor_path,descriptor_bytes),"fixture restores footprint generator after actual editor plan")
	Trace.minimum_event_us=0;Trace.start()
	var trusted:Dictionary=Reader.read(source,offered,content_root,Callable(),true)
	var profile:=Trace.stop()
	check(trusted.get("error",FAILED)==OK and trusted.get("packed") is PackedScene,"trusted reader loads real native scene")
	check(label_count(profile,"compiled.payload_sha")==0,"trusted reader does not hash the native payload")
	if trusted.get("packed") is PackedScene:
		var scene:Node=trusted.packed.instantiate();var child:=scene.get_node_or_null("mesh") as MeshInstance3D
		check(child!=null and child.mesh is ArrayMesh and child.mesh.surface_get_material(0) is StandardMaterial3D,"trusted native scene preserves mesh and material")
		scene.free()
	else:check(false,"trusted native scene preserves mesh and material")
	trusted.clear()
	var held:=source+".held"
	check(DirAccess.rename_absolute(source,held)==OK,"temporarily remove private authoring source")
	var without_source:Dictionary=Footprint.candidate(source,content_root,candidate.source_sha,true)
	check(without_source==offered and Footprint.candidate(source,content_root,candidate.source_sha,false).is_empty(),"trusted candidate preserves exact budget without GLB; strict candidate requires it")
	var no_source:=Reader.read(source,offered,content_root,Callable(),true)
	check(no_source.get("error",FAILED)==OK and no_source.get("packed") is PackedScene,"trusted reader accepts the published native without its GLB")
	no_source.clear()
	var coordinator:=make_coordinator();var prepared:Dictionary=coordinator.run([source,source],Callable(),2,Callable(),content_root)
	check(prepared.get("error",FAILED)==OK and prepared.get("unique_count",-1)==1 and prepared.get("entries",[]).size()==1 and prepared.entries[0].get("compiled",false) and prepared.entries[0].get("packed") is PackedScene and coordinator.raw_calls==0,"require-native coordinator deduplicates a repeated path and loads without GLB or raw fallback")
	check(prepared.get("inflight_jobs_at_return",-1)==0 and prepared.get("inflight_reserved_at_return",-1)==0 and prepared.get("threads_joined",-1)==prepared.get("threads_started",-2),"native coordinator joins workers and settles admission")
	prepared.clear();coordinator=null
	var native_path:String=offered.product
	check(DirAccess.rename_absolute(native_path,native_path+".held")==OK,"hide native product during coordinator failure")
	check(Footprint.candidate(source,content_root,candidate.source_sha,true).is_empty(),"trusted candidate rejects a missing native product")
	coordinator=make_coordinator();var failed_native:Dictionary=coordinator.run([source,source],Callable(),2,Callable(),content_root)
	check(failed_native.get("error",OK)!=OK and coordinator.raw_calls==0 and failed_native.get("unique_count",-1)==1,"require-native missing product fails without raw fallback or duplicate work")
	check(failed_native.get("inflight_jobs_at_return",-1)==0 and failed_native.get("inflight_reserved_at_return",-1)==0,"failed native coordinator settles admission")
	failed_native.clear();coordinator=null;check(DirAccess.rename_absolute(native_path+".held",native_path)==OK,"restore native product after coordinator failure")
	check(DirAccess.rename_absolute(held,source)==OK,"restore private authoring source")
	var altered:=original.duplicate();altered[0]=altered[0]^1
	check(write_bytes(source,altered) and altered.size()==original.size(),"strict fixture changes source at identical length")
	var changed:=Reader.read(source,offered,content_root,Callable(),false)
	check(changed.get("error") == ERR_BUSY and changed.get("native_source_retry",false) and changed.get("packed") is PackedScene,"strict reader detects same-length source change and retains its owner")
	changed.clear()
	check(source.get_file()=="source.glb","editor mutable source uses a human-readable filename")
	var editor_packet:Dictionary=EditorLoadJob._parse_native_asset(source,content_root,offered)
	var editor_action:String=EditorLoadJob._native_result_action(offered,editor_packet)
	check(editor_packet.get("error")==OK and editor_action=="ready","editor consumes the published native product without rereading changed import bytes")
	if editor_packet.get("packed") is PackedScene:
		var editor_owner:WeakRef=weakref(editor_packet.packed)
		check(editor_owner.get_ref()!=null,"editor result retains the native owner until main-thread retirement")
		editor_packet.clear()
		check(editor_owner.get_ref()==null,"editor result owner releases on the main thread")
	else:
		check(false,"editor result retains the native owner until main-thread retirement")
		check(false,"editor result owner releases on the main thread")
	check(write_bytes(source,original),"restore strict fixture source")
	var product:String=offered.product;var bytes:=FileAccess.get_file_as_bytes(product);var corrupt:=bytes.duplicate()
	if not corrupt.is_empty():corrupt[corrupt.size()/2]=corrupt[corrupt.size()/2]^1
	check(not corrupt.is_empty() and write_bytes(product,corrupt),"strict fixture corrupts product without changing size")
	var bad:=Reader.read(source,offered,content_root,Callable(),false)
	check(bad.get("fallback_required",false) and bad.get("cache_reason")=="candidate_checksum" and not bad.has("packed"),"strict reader rejects corrupted product before allocating scene")
	check(write_bytes(product,bytes),"restore private native product")
	check(DirAccess.rename_absolute(product,product+".held")==OK,"temporarily hide private native product")
	var missing:=Reader.read(source,offered,content_root,Callable(),true)
	check(missing.get("fallback_required",false) and not missing.has("packed"),"missing native product fails before allocation")
	check(DirAccess.rename_absolute(product+".held",product)==OK,"restore private native product path")
	var wrong_material:=StandardMaterial3D.new();var wrong:=make_candidate(wrong_material);wrong_material=null
	check(not wrong.is_empty(),"non-PackedScene native resource fixture created")
	if not wrong.is_empty():
		var wrong_result:=Reader.read(source,wrong,content_root,Callable(),true)
		check(wrong_result.get("error",OK)!=OK and wrong_result.get("packed")==null and not wrong_result.get("retained_resources",[]).is_empty(),"wrong native resource type retains allocated owner for main-thread disposal")
		if not wrong_result.get("retained_resources",[]).is_empty():
			var retained:Array=wrong_result.retained_resources;var owner:WeakRef=weakref(retained[0])
			check(owner.get_ref()!=null,"wrong resource survives until the result owner retires it")
			wrong_result.clear();retained.clear()
			check(owner.get_ref()==null,"main-thread owner release disposes the wrong resource")
	finish(logger)

func finish(logger:RefCounted)->void:
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("TRUSTED_NATIVE_PREPARATION passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
