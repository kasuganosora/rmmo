extends "res://tools/test_editor_texture_owner_refresh_http.gd"
const Job=preload("res://scripts/world_editor/load_job.gd")
const ImportWorker=preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
class CapturedDecode extends RefCounted:
	var captured:=false
	var mutex:=Mutex.new()
	var gate:=Semaphore.new()
	var requested:Dictionary
	var content_root:String
	var plan:Dictionary
	var representation:String
	func active()->bool:
		mutex.lock();var value:=captured;mutex.unlock();return value
	func run()->Dictionary:
		var packet:=Job._decode_textures(requested,content_root,plan)
		for image:Image in packet.get("images",{}).values():representation=image.get_meta("runtime_texture_representation","")
		mutex.lock();captured=true;mutex.unlock();gate.wait()
		return packet
class ImportJob extends "res://scripts/world_editor/load_job.gd":
	var capture:CapturedDecode
	var attempts:=0
	func _enqueue_textures(key:String,requested:Dictionary,content_root:String)->void:
		super._enqueue_textures(key,requested,content_root)
		if capture==null:
			capture=CapturedDecode.new();capture.requested=requested;capture.content_root=content_root
			capture.plan=PrefabPixels.estimate(requested,content_root,true)
			_preparation.rows[key].task=capture.run
	func _prepare_record_textures(record:Dictionary)->Dictionary:
		attempts+=1
		return await super._prepare_record_textures(record)
var import_owner:Texture2D
var release_ok:=false
func publish_while_captured(job:ImportJob,source:String,dds:Image)->void:
	while job.capture==null or not job.capture.active():await process_frame
	check(job.capture.representation=="source","worker holds the actual decoded PNG before returning")
	Paint.refresh_texture_source(source)
	var saved:=Paint.cache_byte_budget;Paint.cache_byte_budget=16384
	check(Paint.publish_import_texture(source,dds),"in-flight import publishes real CPU-encoded DDS")
	import_owner=Paint.retained_texture(Paint.texture_key(source))
	Paint.cache_byte_budget=saved;Paint.trim_cached_resources()
	check(import_owner!=null and not Paint._textures.has(Paint.texture_key(source)),"DDS remains owned while the strong cache is empty")
	Pixels.reset_profile();Pixels.profile_enabled=true;Paint.texture_profile_enabled=true
	job.capture.gate.post();release_ok=true
func run()->void:
	create_timer(120).timeout.connect(func():quit(2));Engine.max_fps=60;rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("texture_inflight_dds_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var source:=directory.path_join("color.png");var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.4,.8));image.save_png(source)
	var encoded:=ImportWorker.encode_dds(image)
	check(encoded.get("ok",false),"candidate engine encodes a real DDS image")
	if not encoded.get("ok",false):quit(1);return
	var dds:Image=encoded.image;dds.set_meta("runtime_source_sha256",FileAccess.get_sha256(source))
	dds.set_meta("runtime_texture_representation","dds:"+ImportWorker._digest(encoded.bytes));dds.set_meta("runtime_upload_has_alpha",false)
	var definition:={"name":"shared","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":source}
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor);editor._safety.enabled=false
	var old_budget:=Paint.cache_byte_budget;Paint.cache_byte_budget=0
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual HTTP editor started")
	for kind:String in ["terrain","prefab"]:
		var doc:=Doc.new();var first:=make_record(doc,kind,0,definition);var second:=make_record(doc,kind,1,definition)
		var path:=directory.path_join(kind+".gltf");check(doc.save(path)==OK,kind+": save actual two-record map")
		editor._load_job.queue_free();var gated:=ImportJob.new();gated.editor=editor;editor._load_job=gated;editor.add_child(gated)
		Paint.refresh_sources();import_owner=null;release_ok=false
		publish_while_captured.call_deferred(gated,source,dds)
		await call_tool("open_world",{"path":path,"discard_changes":true})
		var state:=gated.state();var counters:Dictionary=Pixels.profile_snapshot("").counters
		check(release_ok and state.phase=="complete",kind+": full production load completes after gated worker returns")
		check(state.timings.preparation.started==1 and state.timings.preparation.ledger.jobs==0,kind+": exactly one pixel worker and no retained budget lease")
		check(texture(first,kind)==import_owner and texture(second,kind)==import_owner,kind+": both scene records keep the already published DDS allocation")
		var uploaded:Image=texture(first,kind).get_image() if texture(first,kind)!=null else null
		check(uploaded!=null and uploaded.get_format()==Image.FORMAT_DXT1,kind+": final GPU texture stays compressed")
		check(counters.get("paint.texture.upload_bytes",0)==0 and counters.get("paint.texture.sidecar_main_reads",0)==0 and counters.get("paint.texture.runtime_image_lookup",0)==0,kind+": no replacement upload or synchronous source read")
		var candidate:Image=image.duplicate();candidate.set_meta("runtime_texture_representation","source")
		var packet:={"images":{Paint.texture_key(source):candidate},"owners":{}}
		check(Job.TerrainTextures.owners_current(packet),kind+": unknown source identity cannot be superseded by a cached DDS")
		candidate.set_meta("runtime_source_sha256","different-source")
		check(Job.TerrainTextures.owners_current(packet),kind+": fresh different-source pixels keep their normal publication path")
		candidate.set_meta("runtime_source_sha256",dds.get_meta("runtime_source_sha256"));candidate.set_meta("runtime_texture_representation","dds:other-encoding")
		check(Job.TerrainTextures.owners_current(packet),kind+": a new DDS representation is not replaced by an older GPU encoding")
		print("INFLIGHT_DDS_WORK ",JSON.stringify({"kind":kind,"attempts":gated.attempts,"preparation":state.timings.preparation,"counters":counters}))
		Pixels.profile_enabled=false;Paint.texture_profile_enabled=false
	Paint.cache_byte_budget=old_budget;import_owner=null
	editor.queue_free();await settle()
	print("EDITOR_TEXTURE_INFLIGHT_DDS_FAILED=",failed);quit(1 if failed else 0)
