extends SceneTree
## Real native SCN decode and production split coordinator retirement probe,
## with an injected reader return gate. No map hydration or GPU rendering claim.
const Target=preload("res://scripts/world3d/target_scene_prefetch.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Metadata=preload("res://scripts/world3d/native_model_product.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const MiB=1024*1024
var output:String
var checks:=0
var failures:Array[String]=[]
var frames:=0
var samples:Dictionary={}

class GatedNativeReader extends RefCounted:
	var gate:=Semaphore.new()
	var mutex:=Mutex.new()
	var file:String
	var entered:=false
	var owner:WeakRef
	var caller_thread:=0
	func read(_path:String,_candidate:Dictionary)->Dictionary:
		var packed:=ResourceLoader.load(file,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		mutex.lock();owner=weakref(packed);entered=true;caller_thread=OS.get_thread_caller_id();mutex.unlock()
		gate.wait()
		return {"error":OK if packed!=null else ERR_FILE_CORRUPT,"packed":packed,"compiled":true,"source_digest":"b".repeat(64)}
	func has_entered()->bool:
		mutex.lock();var value:=entered;mutex.unlock();return value
	func alive()->bool:
		mutex.lock();var value:bool=owner!=null and owner.get_ref()!=null;mutex.unlock();return value
	func release_later()->void:
		OS.delay_msec(250);gate.post()

class ControlledMapLoader extends "res://scripts/world3d/map_loader.gd":
	var probe_root:String
	var probe_key:String
	func _parse()->void:
		# Replace only map discovery; start(), native scheduler and all teardown
		# remain production code. The injected reader performs actual SCN decode.
		var result:Dictionary=_model_preparation.run([probe_key],Callable(),_initial_model_workers(),Callable(),probe_root)
		_native_texture_scope=result.get("native_texture_scope")
		for entry:Dictionary in result.entries:_asset_states[entry.path]=entry
		_error=result.error

class GatedVerifier extends RefCounted:
	var gate:=Semaphore.new()
	var mutex:=Mutex.new()
	var entered:=false
	func verify(files:Dictionary,content_root:String)->bool:
		var valid:=Target.verify(files,content_root)
		mutex.lock();entered=true;mutex.unlock()
		gate.wait()
		return valid
	func has_entered()->bool:
		mutex.lock();var value:=entered;mutex.unlock();return value

func _initialize()->void:
	process_frame.connect(func():frames+=1)
	run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func write_json(path:String,value:Variant)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value));file.close()

func empty_native_fixture()->Dictionary:
	var table:={"version":1,"textures":{},"image_bytes":0}
	var encoded:=JSON.stringify(table);var digest:=encoded.sha256_text()
	write_json(output.path_join("cache/world3d/compiled_assets_v1/texture_tables_v1/"+digest+".json"),table)
	var scene:=Node3D.new();scene.set_meta(Binding.TABLE_META,digest)
	var part:=MeshInstance3D.new();part.name="NativeGeometry";scene.add_child(part);part.owner=scene
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,StandardMaterial3D.new());part.mesh=mesh
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack tiny real native geometry fixture")
	scene.free();var filename:=output.path_join("native.scn")
	check(ResourceSaver.save(packed,filename)==OK,"save external SCN for real worker decode")
	return {"file":filename,"candidate":{"estimated_bytes":64*MiB,"exclusive":false,"source_sha":"b".repeat(64),"texture_table":{"version":1,"sha256":digest,"bytes":encoded.to_utf8_buffer().size(),"textures":0,"image_bytes":0}}}

func admitted_job(world:Node,label:String)->Dictionary:
	var prefetch:=Target.for_world(world)
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=Target.LEASE_BYTES
	prefetch._token=Drainer.CancelToken.new();prefetch._lease="prefetch_audit:"+label;prefetch._ledger=ledger
	prefetch._path=output.path_join("logical_map.gltf");prefetch._touched=Time.get_ticks_msec()
	check(ledger.reserve_background(prefetch._lease,Target.LEASE_BYTES,prefetch._token.cancel,2),label+": production outer speculative lease admitted")
	return {"prefetch":prefetch,"ledger":ledger}

func private_scene(prefetch:Node,fixture:Dictionary)->WeakRef:
	var packed:=ResourceLoader.load(fixture.file,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	prefetch._scene=packed.instantiate()
	var mesh:Mesh=prefetch._scene.get_node("NativeGeometry").mesh
	prefetch._warm.append(mesh)
	return weakref(mesh)

func retirement_case(label:String,fixture:Dictionary,destroy:bool,shutdown:bool=false)->void:
	var world:=Node3D.new();root.add_child(world)
	var job:=admitted_job(world,label);var prefetch:Node=job.prefetch;var ledger:RefCounted=job.ledger
	check(Target.for_world(world)==prefetch and prefetch.get_parent()==Drainer.for_tree(self),label+": same world reuses one root-owned job")
	var reader:=GatedNativeReader.new();reader.file=fixture.file
	var loader:=ControlledMapLoader.new();loader.background_preload=true
	loader.probe_root=output;loader.probe_key=output.path_join("logical_model.glb")
	loader._model_preparation.inflight_byte_limit=Target.LEASE_BYTES/2
	loader._model_preparation.memory_estimator=func(_key:String)->Dictionary:return {"estimated_bytes":64*MiB,"exclusive":false}
	loader._model_preparation.candidate_provider=func(_key:String)->Dictionary:return fixture.candidate
	loader._model_preparation.candidate_reader=reader.read
	prefetch._loader=loader;prefetch.add_child(loader);loader.start(prefetch._path)
	var deadline:=Time.get_ticks_msec()+5000
	while not reader.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(reader.has_entered() and reader.alive() and reader.caller_thread!=OS.get_main_thread_id(),label+": real native owner exists on gated native worker")
	if not reader.has_entered():reader.gate.post();world.free();return
	var releaser:=Thread.new();check(releaser.start(reader.release_later)==OK,label+": independent CPU gate releaser started")
	var before_frames:=frames;var began:=Time.get_ticks_usec()
	if shutdown:prefetch.get_parent().free()
	elif destroy:world.free()
	else:prefetch.cancel()
	var call_us:=Time.get_ticks_usec()-began
	var sample:={"call_us":call_us,"frames_during_call":frames-before_frames,"owner_alive_at_return":reader.alive(),"outer_bytes_at_return":ledger.reserved_bytes,"release_delay_ms":250}
	check(call_us>=200000 if shutdown else call_us<50000,label+": only final lifetime-owner shutdown waits for live native worker")
	if not shutdown:check(reader.alive() and ledger.reserved_bytes==Target.LEASE_BYTES,label+": cancelled live owner retains its outer lease")
	deadline=Time.get_ticks_msec()+5000
	while (reader.alive() or ledger.reserved_bytes>0 or releaser.is_alive()) and Time.get_ticks_msec()<deadline:await process_frame
	if not releaser.is_alive():releaser.wait_to_finish()
	sample.frames_until_released=frames-before_frames;sample.owner_alive_after_retirement=reader.alive();sample.outer_bytes_after_retirement=ledger.reserved_bytes
	check(not reader.alive() and ledger.reserved_bytes==0,label+": native identity and full outer lease retire together")
	check(shutdown or sample.frames_until_released>1,label+": frame loop advances while native worker retires")
	await process_frame
	if not destroy and not shutdown:check(is_instance_valid(prefetch) and not prefetch._abandoned,label+": ordinary cancel leaves reusable idle service")
	else:check(not is_instance_valid(prefetch),label+": abandoned or shutdown service is freed after owners retire")
	samples[label]=sample
	if is_instance_valid(world):world.free()
	await process_frame;await process_frame
	check(not is_instance_valid(prefetch),label+": no job survives its consumer after retirement")

func warming_cancel_case(fixture:Dictionary)->void:
	var world:=Node3D.new();root.add_child(world)
	var job:=admitted_job(world,"warming_cancel");var prefetch:Node=job.prefetch
	var ledger:RefCounted=job.ledger
	var packed:=ResourceLoader.load(fixture.file,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var scene:=packed.instantiate();packed=null
	var owner:WeakRef=weakref(scene.get_node("NativeGeometry").mesh)
	var frames_clock:RefCounted=preload("res://scripts/util/frame_presentation.gd").clock()
	var completed:int=frames_clock.completed
	prefetch._loaded(scene,"","");scene=null
	for _tick in 3:await process_frame
	check(prefetch._warming and not prefetch._gpu_ready and frames_clock.completed==completed,"warming: process frames cannot impersonate two rendered serials")
	var began:=Time.get_ticks_usec();world.free();var elapsed:=Time.get_ticks_usec()-began
	check(elapsed<50000 and owner.get_ref()!=null and ledger.reserved_bytes==Target.LEASE_BYTES,"warming: consumer exits promptly while suspended warm stack remains charged")
	var deadline:=Time.get_ticks_msec()+5000
	while is_instance_valid(prefetch) and Time.get_ticks_msec()<deadline:await process_frame
	check(not is_instance_valid(prefetch) and owner.get_ref()==null and ledger.reserved_bytes==0,"warming: cancellation unwinds without another draw and retires scene and lease")
	samples.warming_cancel={"call_us":elapsed,"completed_draws_before":completed,"completed_draws_after":frames_clock.completed,"reserved_after":ledger.reserved_bytes,"owner_alive_after":owner.get_ref()!=null}

func verify_and_two_worlds_case(fixture:Dictionary)->void:
	var first:=Node3D.new();var second:=Node3D.new();root.add_child(first);root.add_child(second)
	var a:=admitted_job(first,"verify_cancel");var b:=admitted_job(second,"independent_ready")
	var prefetch:Node=a.prefetch;var other:Node=b.prefetch
	var owner:=private_scene(prefetch,fixture);var other_owner:=private_scene(other,fixture)
	other._gpu_ready=true;b.ledger.park(other._lease)
	check(prefetch!=other and a.ledger.reserved_bytes==Target.LEASE_BYTES and b.ledger.reserved_bytes==Target.LEASE_BYTES,"two worlds: independent jobs retain each ready result's full admission")
	var gate:=GatedVerifier.new()
	prefetch._root=output;prefetch._manifest={fixture.file:FileAccess.get_sha256(fixture.file)}
	prefetch._verify=Thread.new()
	prefetch._verify_ticket=preload("res://scripts/world3d/cpu_worker_retirement.gd").watch(prefetch._verify,self,[prefetch._manifest])
	check(prefetch._verify.start(gate.verify.bind(prefetch._manifest,output))==OK,"verify: real manifest verification worker starts")
	var deadline:=Time.get_ticks_msec()+5000
	while not gate.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(gate.has_entered(),"verify: worker remains live before consumer exit")
	var began:=Time.get_ticks_usec();first.free();prefetch.abandon();prefetch.abandon();var elapsed:=Time.get_ticks_usec()-began
	check(elapsed<50000 and owner.get_ref()!=null and a.ledger.reserved_bytes==Target.LEASE_BYTES,"verify: repeated abandon never joins live verifier or releases its scene early")
	check(not prefetch.request(prefetch._path,prefetch._destination,a.ledger,null) and prefetch.take(prefetch._path,prefetch._destination)==null,"verify: abandoned job rejects new request and adoption")
	for _tick in 3:await process_frame
	check(not other._abandoned and other._gpu_ready and other_owner.get_ref()!=null and b.ledger.reserved_bytes==Target.LEASE_BYTES,"two worlds: one exit cannot cancel or uncharge the other ready result")
	gate.gate.post();deadline=Time.get_ticks_msec()+5000
	while is_instance_valid(prefetch) and Time.get_ticks_msec()<deadline:await process_frame
	check(not is_instance_valid(prefetch) and owner.get_ref()==null and a.ledger.reserved_bytes==0,"verify: completed cancelled result retires scene and original lease")
	var ready_path:String=other._path;var ready_destination:Vector3=other._destination
	second.free()
	check(other.take(ready_path,ready_destination)==null,"ready: consumer exit rejects adoption of the previously ready result")
	await process_frame;await process_frame
	check(not is_instance_valid(other) and other_owner.get_ref()==null and b.ledger.reserved_bytes==0,"two worlds: independent ready result retires on its own consumer exit")
	samples.verify_cancel={"call_us":elapsed,"first_reserved_after":a.ledger.reserved_bytes,"second_reserved_after":b.ledger.reserved_bytes}

func idle_case()->void:
	var owner:Node=Drainer.for_tree(self);var children:=owner.get_child_count()
	var world:=Node3D.new()
	check(Target.for_world(null)==null and Target.for_world(world)==null and owner.get_child_count()==children,"idle: invalid or detached consumer cannot create a root job")
	root.add_child(world)
	var service:=Target.for_world(world)
	check(service==Target.for_world(world),"idle: factory is idempotent before dispatch")
	root.remove_child(world)
	check(Target.for_world(world)==null and owner.get_child_count()==children+1,"idle: exited consumer cannot create or reacquire a root job")
	world.free();await process_frame;await process_frame
	check(not is_instance_valid(service),"idle: unused job frees without leaving a root child")

func split_envelope_case(fixture:Dictionary)->void:
	# Valid published scalar layout; intentionally no 1 GiB pixel allocation.
	# Only the planner/table/pool admission protocol is exercised here.
	var path:=output.path_join("budget_model.glb")
	var texture_bytes:=1024*MiB
	var table:={"version":1,"textures":{ID:{"file":"cache/world3d/model_textures_v1/"+ID+".stex","pixel_sha":ID,"width":16384,"height":16384,"format":Image.FORMAT_RGBA8,"mip_sizes":[texture_bytes],"bytes":texture_bytes,"file_bytes":texture_bytes+52,"alpha":false,"normal_xy":false}},"image_bytes":texture_bytes}
	var encoded:=JSON.stringify(table);var table_sha:=encoded.sha256_text()
	var descriptor:={"version":1,"sha256":table_sha,"bytes":encoded.to_utf8_buffer().size(),"textures":1,"image_bytes":texture_bytes}
	write_json(output.path_join("cache/world3d/compiled_assets_v1/texture_tables_v1/"+table_sha+".json"),table)
	var template:=ResourceLoader.load(fixture.file,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var native_scene:=template.instantiate();native_scene.set_meta(Binding.TABLE_META,table_sha)
	var part:MeshInstance3D=native_scene.get_node("NativeGeometry")
	part.mesh.surface_get_material(0).set_meta(Binding.BINDINGS_META,{"albedo_texture":{"id":ID,"normal":false}})
	var native:=PackedScene.new();check(native.pack(native_scene)==OK,"pack matching split table/material metadata")
	native_scene.free();var native_file:=output.path_join("budget_native.scn")
	check(ResourceSaver.save(native,native_file)==OK,"save matching image-free native geometry")
	var payload_sha:=FileAccess.get_sha256(native_file)
	var product:=Compiled.directory(output).path_join(payload_sha+".scn")
	check(DirAccess.copy_absolute(native_file,product)==OK,"budget fixture uses real native product bytes")
	var length:=FileAccess.get_file_as_bytes(product).size()
	var manifest:={"version":1,"generator":"cpu-audit-published-contract","source_sha":"b".repeat(64),"payload_sha":payload_sha,"bytes":length,"texture_table":descriptor}
	write_json(Compiled.index_path(path,output),manifest)
	var body:={"version":1,"source_path":path,"source_sha":manifest.source_sha,"payload_sha":payload_sha,"generator":manifest.generator,"bytes":length,"estimated_bytes":64*MiB,"resident_bytes":64*MiB,"source_bytes":28,"model_metadata":{"version":1,"local_bounds":[0,0,0,1,1,1],"file_length":28,"json_bytes":4,"json_sha256":ID}}
	var body_text:=JSON.stringify(body);write_json(Footprint.descriptor_path(path,output),{"version":1,"body":body_text,"sha256":body_text.sha256_text()})
	var metadata:Dictionary=Metadata.read(path,output)
	check(not metadata.is_empty() and metadata.native_candidate.has("texture_table"),"actual metadata reader accepts published split contract")
	var plan:Dictionary=Target.plan([{"asset_path":path}],output,output.path_join("logical_map.gltf"),ID,{})
	var texture_plan:Dictionary=Binding.candidate_plan(metadata.native_candidate,output,{})
	check(texture_plan.ok,"actual texture table reader accepts declared native layout")
	var pool:=Pool.new();var offer:Dictionary=pool.offer(texture_plan.plan)
	var inner:=Admission.new();inner.worker_limit=1;inner.byte_limit=Target.LEASE_BYTES/2
	var accepted:bool=inner.reserve_bundle("initial_pixels:budget",{"estimated_bytes":offer.scratch_bytes,"exclusive":false,"stage":"initial_pixels"},offer.retained)
	samples.split_envelope={"outer_lease_bytes":Target.LEASE_BYTES,"plan_bytes":plan.get("estimated_bytes",0),"split_output_bytes":texture_bytes,"inner_working_limit":inner.byte_limit,"inner_admitted_bytes":inner.reserved_bytes,"inner_accepted":accepted,"pixel_payload_allocated":false}
	check(plan.is_empty() or int(plan.estimated_bytes)>=inner.reserved_bytes,"speculative envelope covers the split-native pixel reservation before admission")
	inner.release("initial_pixels:budget")
	for key:String in offer.retained:inner.release(key)

func run()->void:
	output=OS.get_environment("RMMO_PREFETCH_REVIEW_OUT").replace("\\","/")
	if output.is_empty() or not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var fixture:=empty_native_fixture()
	await retirement_case("ordinary_cancel",fixture,false)
	await retirement_case("world_destroy",fixture,true)
	await warming_cancel_case(fixture)
	await verify_and_two_worlds_case(fixture)
	await idle_case()
	await retirement_case("final_shutdown",fixture,false,true)
	if "--cancel-only" not in OS.get_cmdline_user_args():split_envelope_case(fixture)
	write_json(output.path_join("result.json"),{"checks":checks,"failures":failures,"samples":samples,"scope":"Headless CPU: real SCN decoder plus production split scheduler/teardown with a controlled reader return gate. Budget test is scalar admission only, no pixel allocation or actual GPU/map run."})
	print("TARGET_PREFETCH_CPU ",JSON.stringify({"checks":checks,"failures":failures,"samples":samples}))
	quit(0 if failures.is_empty() else 1)
