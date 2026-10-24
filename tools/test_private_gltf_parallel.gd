extends SceneTree
## Hidden GPU test: independent self-contained white imports, exact decoded
## geometry and per-document extension state. Formal assets are read-only.
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
class Errors extends Logger:
	var mutex:=Mutex.new()
	var messages:Array=[]
	func _log_error(_function:String,_file:String,_line:int,code:String,rationale:String,_editor_notify:bool,_error_type:int,backtraces:Array[ScriptBacktrace])->void:
		mutex.lock();messages.append(code+" "+rationale);mutex.unlock()
class ProbeExtension extends GLTFDocumentExtension:
	static var mutex:=Mutex.new()
	static var active:=0
	static var peak:=0
	var own_state:=0
	func _import_preflight(state:GLTFState,_extensions:PackedStringArray)->Error:
		own_state=state.get_instance_id();mutex.lock();active+=1;peak=maxi(peak,active);mutex.unlock()
		OS.delay_msec(30)
		var same:=own_state==state.get_instance_id()
		mutex.lock();active-=1;mutex.unlock()
		return OK if same else ERR_BUG
var failures:=0
var serial_lock:=Mutex.new()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture(path:String,offset:float)->void:
	var binary:=PackedFloat32Array([offset,0,0,offset+1,0,0,offset,1,0]).to_byte_array()
	var nodes:Array=[];var roots:Array=[]
	for i:int in 64:nodes.append({"name":"Part%d"%i,"mesh":0,"translation":[i*2,0,0]});roots.append(i)
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":roots}],"nodes":nodes,"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[offset,0,0],"max":[offset+1,1,0]}],"bufferViews":[{"buffer":0,"byteLength":binary.size()}],"buffers":[{"byteLength":binary.size()}]}
	var encoded:=JSON.stringify(data).to_utf8_buffer()
	while encoded.size()%4:encoded.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+encoded.size()+binary.size());file.store_32(encoded.size());file.store_32(0x4e4f534a);file.store_buffer(encoded);file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary)
func import_private(path:String,serial:bool)->Dictionary:
	if "--production-gate" in OS.get_cmdline_user_args():
		var manifest:Dictionary=preload("res://scripts/world3d/asset_bounds_manifest.gd").read(path);manifest.erase("known")
		var packet:Dictionary=preload("res://scripts/world3d/deferred_asset_loader.gd").prepare_scene(path,FileAccess.get_sha256(path),null,manifest,false,"D:/code/rmmo_runtime",true,2,false,true)
		packet.error=OK if packet.error.is_empty() else ERR_CANT_CREATE
		return packet
	if serial:serial_lock.lock()
	var document:=GLTFDocument.new();var state:=GLTFState.new();Controls.configure_gltf(state)
	var code:=document.append_from_file(path,state,0,path.get_base_dir())
	var scene:Node=Io.generate_scene(document,state,true) if code==OK else null
	if serial:serial_lock.unlock()
	return {"error":code,"document":document,"state":state,"scene":scene}
func signature(scene:Node)->String:
	var rows:Array=[];var nodes:Array=[scene]
	while not nodes.is_empty():
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
		var row:Array=[str(node.name),node.get_class(),node.transform if node is Node3D else null,node.get_meta("extras",{})]
		if node is MeshInstance3D:
			for slot:int in node.mesh.get_surface_count():row.append(node.mesh.surface_get_arrays(slot));row.append(preload("res://scripts/world3d/ground_cpu_mesh.gd").capture_lods(node.mesh,slot))
		rows.append(row)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(rows));return hash.finish().hex_encode()
func run()->void:
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var logger:=Errors.new();OS.add_logger(logger)
	Controls.discard_map_textures=true;Controls.enable_white_materials();Drainer.for_tree(self)
	var folder:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/private_parallel_fixture"
	DirAccess.make_dir_recursive_absolute(folder)
	var paths:Array[String]=[]
	for i:int in 3:
		var path:=folder.path_join("private%d.glb"%i);fixture(path,i*.25);paths.append(path)
	var extension:=ProbeExtension.new();GLTFDocument.register_gltf_document_extension(extension)
	var expected:Dictionary={};var trials:Array=[]
	for serial:bool in [true,false,false,true]:
		preload("res://scripts/world3d/model_parse_preparation.gd").parallel_white_imports_enabled=not serial
		ProbeExtension.peak=0;var workers:Array[Thread]=[];var began:=Time.get_ticks_usec()
		for i:int in 6:
			var thread:=Thread.new();thread.start(import_private.bind(paths[i%3],serial));workers.append(thread)
		while workers.any(func(w:Thread):return w.is_alive()):await process_frame
		var elapsed:=Time.get_ticks_usec()-began;var mesh_ids:Dictionary={};var equal:=true
		for i:int in workers.size():
			var packet:Dictionary=workers[i].wait_to_finish();var path:String=paths[i%3]
			equal=equal and packet.error==OK and is_instance_valid(packet.scene)
			if packet.scene!=null:
				var actual:=signature(packet.scene)
				if not expected.has(path):expected[path]=actual
				equal=equal and not actual.is_empty() and actual==expected[path]
				var mesh:Mesh=Io.find_named(packet.scene,"Part0").mesh
				equal=equal and not mesh_ids.has(mesh.get_instance_id());mesh_ids[mesh.get_instance_id()]=true
				packet.scene.free()
		check(equal,"independent documents retain exact nodes/transforms/GPU arrays/LOD and separate mesh owners")
		check(ProbeExtension.peak==1 if serial else ProbeExtension.peak>1,"extension callbacks are serialized or overlap as requested without state aliasing")
		trials.append({"serial":serial,"us":elapsed,"peak":ProbeExtension.peak})
	GLTFDocument.unregister_gltf_document_extension(extension)
	OS.remove_logger(logger);check(logger.messages.is_empty(),"zero engine and script errors throughout native parallel import and exact comparison")
	print("PRIVATE_GLTF_PARALLEL ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
