extends SceneTree
## Small headless regressions. No author assets; test queue uses real dispatch,
## bounded source hashing, joins, acceptance and cancellation with temporary bytes.
const Requirements=preload("res://scripts/world3d/model_collision_requirements.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
class Document extends RefCounted:
	var calls:=0
	func _asset(_record:Dictionary)->Node3D:
		calls+=1;return Node3D.new()
class GatedQueue extends "res://scripts/world3d/deferred_asset_loader.gd":
	var gate:=Semaphore.new()
	func _make_prepare_task(path:String,digest:String,token:RefCounted,item:Dictionary,needs_faces:bool,content_root:String,requests:Array,native:bool,need_model:bool)->Callable:
		return _held.bind(super._make_prepare_task(path,digest,token,item,needs_faces,content_root,requests,native,need_model))
	func _held(task:Callable)->Dictionary:
		gate.wait();return task.call()
var passed:=0
var failures:=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1
func record(id:String,mode:Variant="")->Dictionary:
	return {"uuid":id,"kind":"asset","asset_path":"test.glb","collision":mode}
func compact(id:String,digest:String="a")->Dictionary:
	return {"uuid":id,"rmmo_ref":{"uri":"map.gltf.resources/definition.rmres","sha256":digest.repeat(64)},"rmmo_state":{}}
func visual(mesh:Mesh,mode:String)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=mesh;node.set_meta("extras",{"rmmo_collision":mode});return node
func triangle()->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([2,0,1])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return {"mesh":mesh,"cpu":Cpu.remember(mesh,[arrays]),"arrays":arrays}
func template()->Dictionary:
	var mesh:=ArrayMesh.new();var holder:=Node3D.new();var node:=visual(mesh,"none")
	holder.add_child(node);node.owner=holder
	var packed:=PackedScene.new();packed.pack(holder);holder.free()
	return {"mesh":mesh,"packed":packed}
func fixture(path:String,digest:String,mode:String="none")->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	for key:String in Index.build([]):map.set_meta(key,Index.build([])[key])
	map.set_meta("stream_library",[]);map.set_meta("extras",{"rmmo_records":[]})
	var queue:=GatedQueue.new();map.add_child(queue);var document:=Document.new();queue._doc=document
	queue.activate(map);queue.set_process(false);queue._admission.byte_limit=96*1024*1024;queue._admission.worker_limit=2
	var item:Dictionary={"path":path,"digest":digest,"record":{"uuid":"model","kind":"asset","asset_path":path,"collision":mode},"bounds":AABB(Vector3.ZERO,Vector3.ONE),"memory":{"estimated_bytes":6*1024*1024*1024,"exclusive":true,"known":true}}
	queue.pending=[item];queue.source_signatures[path]=digest;queue._prepared_paths[path]=true
	queue.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)));queue.set_process(false)
	return {"map":map,"queue":queue,"document":document,"item":item}

func policies()->void:
	check(Requirements.record_mode(compact("a"))==Requirements.UNKNOWN,"compact missing collision is unknown, never implicit inheritance")
	check(Requirements.record_mode(record("a"))==Requirements.AUTHORED,"complete empty override inherits authored node collision")
	check(Requirements.record_mode(record("a","none"))==Requirements.NONE,"complete explicit none requires no solid geometry")
	for mode:Variant in ["walk","block","future_mode",false]:
		check(Requirements.record_mode(record("a",mode))==Requirements.ALL,"strong or unknown override remains conservative: "+str(mode))
	var edited:=record("a","none");edited.tree_settings={}
	check(Requirements.record_mode(edited)==Requirements.ALL,"generated model geometry keeps legacy preparation")
	var a:=compact("a");var b:=compact("b");var consumers:Array=[Requirements.consumer(a),Requirements.consumer(b)]
	var requests:Array=[{"compact_record":a}];var hydrated:Array=[record("a","none")]
	var resolved:=Requirements.resolve(consumers,hydrated,requests,"test.glb")
	check(resolved.mode==Requirements.NONE and resolved.definitions.size()==1,"one verified immutable definition resolves future instances sharing URI and SHA")
	var stronger:=consumers.duplicate(true);stronger.append(Requirements.consumer(record("c","block")))
	check(Requirements.resolve(stronger,hydrated,requests,"test.glb").mode==Requirements.ALL,"later same-source block overrides all decorative instances")
	check(Requirements.resolve([Requirements.consumer(compact("b","b"))],hydrated,requests,"test.glb").mode==Requirements.ALL,"different definition SHA cannot borrow a none policy")
	var different:=compact("b");different.rmmo_ref.uri="map.gltf.resources/elsewhere.rmres"
	check(Requirements.resolve([Requirements.consumer(different)],hydrated,requests,"test.glb").mode==Requirements.ALL,"same SHA at another reference URI is conservative until verified")
	check(Requirements.resolve(consumers,hydrated,requests,"another.glb").mode==Requirements.ALL,"different asset source cannot lend a record policy")
	check(Requirements.resolve(consumers).mode==Requirements.ALL,"unresolved compact collection stays all-geometry")
	check(Requirements.resolve([]).mode==Requirements.ALL,"missing consumer census stays conservative")
	check(Requirements.resolve([{"mode":false}]).mode==Requirements.ALL,"invalid policy type cannot suppress collision")
	var many:Array=[];many.resize(Requirements.MAX_CONSUMERS+1)
	check(Requirements.resolve(many).mode==Requirements.ALL,"oversized census falls back without allocating proof tables")
	check(Requirements.needs_geometry({},Requirements.AUTHORED) and Requirements.needs_geometry({"rmmo_collision":"future"},Requirements.AUTHORED),"unknown node collision still needs geometry")
	check(not Requirements.needs_geometry({"rmmo_collision":"none"},Requirements.AUTHORED),"authored none may skip optional geometry")
	check(Requirements.needs_geometry({"rmmo_collision":"none"},Requirements.ALL),"record force cannot be defeated by authored none")
	var q:=Deferred.new();q.pending=[{"path":"test.glb","record":a},{"path":"test.glb","record":b}]
	check(q._geometry_coverage_current("test.glb",{"collision_geometry_mode":Requirements.NONE,"collision_definitions":resolved.definitions}),"acceptance resolves matching validated definition facts")
	q.pending.append({"path":"test.glb","record":record("new","walk")})
	check(not q._geometry_coverage_current("test.glb",{"collision_geometry_mode":Requirements.NONE,"collision_definitions":resolved.definitions}),"acceptance rejects a newly stronger consumer")
	q.pending.pop_back();q._remember_geometry_definitions("test.glb",{"collision_definitions":resolved.definitions})
	check(q._collision_definition_count==1 and q._collision_definition_bytes>0,"definition memo has explicit retained accounting")
	q._collision_definition_bytes=Requirements.MAX_DEFINITION_BYTES
	q._remember_geometry_definitions("test.glb",{"collision_definitions":{Requirements.definition_key(compact("other","b")):Requirements.NONE}})
	check(q._collision_definition_count==1 and q._collision_definition_bytes==Requirements.MAX_DEFINITION_BYTES,"byte ceiling rejects another retained definition even below count ceiling")
	var previous_map:=Node3D.new();previous_map.set_meta("extras",{"rmmo_records":[record("a","none")]});q._map=previous_map
	q.pending=[{"path":"test.glb","record":record("a","block")}]
	check(Requirements.resolve(q._geometry_consumers("test.glb")).mode==Requirements.ALL,"new pending override wins over an old published record with the same UUID")
	previous_map.free()
	q.configure_references({},"map.gltf","root")
	check(q._collision_definition_modes.is_empty() and q._collision_definition_bytes==0,"map context reset removes prior definition proofs")
	q.free()

func geometry()->void:
	for reverse in [false,true]:
		var t:=triangle();var holder:=Node3D.new();var solid:=visual(t.mesh,"block");var decorative:=visual(t.mesh,"none")
		if reverse:holder.add_child(solid);holder.add_child(decorative)
		else:holder.add_child(decorative);holder.add_child(solid)
		decorative.visibility_range_begin=100.;decorative.visibility_range_end=200.
		var result:=Deferred._capture_static_meshes(holder,true,null,Requirements.AUTHORED)
		check(result.error.is_empty() and result.captured_meshes==1 and result.skipped_geometry_nodes==1,"shared mesh OR keeps one solid capture in either node order "+str(reverse))
		check(t.cpu._collision_faces==PackedVector3Array([Vector3.FORWARD,Vector3.ZERO,Vector3.RIGHT]),"base collision face order survives render LOD filtering "+str(reverse))
		holder.free()
	var holder:=Node3D.new();var unneeded:=ArrayMesh.new();var node:=visual(unneeded,"none");holder.add_child(node)
	var skipped:=Deferred._capture_static_meshes(holder,true,null,Requirements.AUTHORED)
	check(skipped.captured_meshes==0 and skipped.face_bytes==0 and not unneeded.has_meta("ground_cpu_cache"),"decorative capture does not read arrays or manufacture a CPU cache")
	var spec:=Stream._spec(node)
	check(spec.mesh==unneeded and not spec.has("collision_mesh") and not unneeded.has_meta("ground_cpu_cache"),"main adoption retains render mesh without redoing skipped collision capture")
	check(Stream._make_body(null,spec)==null,"none body semantics remain unchanged")
	var cancelled:=Deferred.Drainer.CancelToken.new();cancelled.cancel()
	check(Deferred._capture_static_meshes(holder,true,cancelled,Requirements.AUTHORED).get("cancelled",false),"cancellation still stops a no-geometry traversal")
	holder.free()
	var t:=triangle();node=visual(t.mesh,"none");holder=Node3D.new();holder.add_child(node)
	var forced:=Deferred._capture_static_meshes(holder,true,null,Requirements.ALL)
	check(forced.captured_meshes==1 and forced.face_bytes==36,"forced override retains complete base triangles")
	node.set_meta("extras",{"rmmo_collision":"block"});node.transform=Transform3D(Basis(Vector3.UP,.4).scaled(Vector3(-2,3,4)),Vector3(1,2,3))
	spec=Stream._spec(node)
	check(spec.collision_mesh==t.cpu and spec.transform==node.transform,"adoption preserves negative scale, rotation and solid CPU identity")
	holder.free()
	var cached:=template()
	check(Deferred._reuse_face_offer(cached.packed,Requirements.AUTHORED).ok,"decorative native template needs no CPU readback for reuse")
	check(not Deferred._reuse_face_offer(cached.packed,Requirements.ALL).ok,"stronger consumer cannot reuse an uncaptured decorative template")
	Requirements.enabled=false
	check(Requirements.needs_adopted_collision({"rmmo_collision":"none"}),"disabled candidate retains baseline adoption policy")
	Requirements.enabled=true

func queue_paths(path:String,digest:String)->void:
	var t:=template();Assets.cache_packed(path,t.packed,digest)
	var f:=fixture(path,digest);var q:GatedQueue=f.queue
	q._refresh_demanded();q._dispatch_jobs(self)
	check(q._jobs.has(path) and q._jobs[path].stage=="reuse_reference","actual queue dispatch reuses decorative template without GLB import")
	if q._jobs.has(path):
		check(q._jobs[path].estimate.geometry_workspace_bytes>0 and q._admission.reserved_bytes==q._jobs[path].estimate.estimated_bytes,"policy workspace stays in the actual task reservation")
		# Change demand while the real worker is blocked, then allow its actual
		# source hash to complete. Acceptance must not publish the weaker packet.
		f.item.record.collision="block";q.gate.post()
		while q._jobs[path].worker.is_alive():await process_frame
		q._admission.worker_limit=0;q._process(0)
		check(q.profile.get("geometry_requirement_retries",0)==1 and q._jobs.is_empty() and q._admission.reserved_bytes==0,"joined obsolete policy is disposed and releases its original lease")
		check(f.document.calls==0 and not q._prepared_paths.has(path),"stronger demand cannot publish a weak cached result")
	else:q.gate.post()
	f.map.free()
	# A stronger future demand must wait for FULL admission, not allocate missing
	# arrays in the 16 MiB hash reuse envelope. No parseable source is provided.
	f=fixture(path,digest,"block");q=f.queue
	q._admission.reserve("sibling",{"estimated_bytes":80*1024*1024,"exclusive":false})
	q._refresh_demanded();q._dispatch_jobs(self)
	check(q.profile.get("reuse_face_fallbacks",0)==1 and not q._prepared_paths.has(path) and not q._jobs.has(path),"missing CPU capture re-enters complete model admission")
	check(q._admission.reserved_bytes==80*1024*1024 and not t.mesh.has_meta("ground_cpu_cache"),"blocked upgrade never fills arrays or manufactures available credit")
	q._admission.release("sibling");f.map.free()
	f=fixture(path,digest);q=f.queue;q._refresh_demanded();q._dispatch_jobs(self)
	if q._jobs.has(path):q._jobs[path].token.cancel()
	q.gate.post();await q.quiesce()
	check(q._jobs.is_empty() and q._admission.reserved_bytes==0,"real dispatch cancellation joins and returns every task lease")
	f.map.free()
	var corrupted:=FileAccess.open(path,FileAccess.WRITE);corrupted.store_buffer(PackedByteArray([4,3,2,1]));corrupted.close()
	var invalid:=Deferred._prepare_job(path,digest,null,{},false,Paths.external_root(),{},"",[],false,false,null,{"filter_collision_geometry":true,"geometry_consumers":[{"mode":Requirements.NONE}],"geometry_mode":Requirements.NONE})
	check(not invalid.error.is_empty() and not invalid.get("reused_model",false),"none geometry policy never bypasses final source SHA")
	Assets.evict_cached_scene(path)

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var previous:=Requirements.enabled;Requirements.enabled=true
	policies();geometry()
	var folder:=Paths.cache_directory("collision_requirements_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("cached.glb");var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3,4]));file.close()
	await queue_paths(path,FileAccess.get_sha256(path))
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(folder)
	Requirements.enabled=previous
	check(logger.errors.is_empty(),"no engine errors during focused CPU regressions")
	OS.remove_logger(logger)
	print("MODEL_COLLISION_REQUIREMENTS passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
