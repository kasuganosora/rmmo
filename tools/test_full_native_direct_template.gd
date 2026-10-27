extends "res://tools/test_full_native_without_source.gd"
## Opt-in direct-template contract on temporary full native products.
## GPU only; the source GLBs are deleted before any runtime queue test.
class DirectQueue extends Deferred:
	var dispatches:Array=[]
	var original_owners:Dictionary={}
	var flip_after_second:=false
	var reject_start:=false
	func _start_worker(worker:RefCounted,task:Callable)->Error:
		for path:String in _jobs:
			if _jobs[path].worker==worker:
				dispatches.append({"path":path,"direct":_jobs[path].get("direct_template_reuse",false),"prepack":_jobs[path].get("worker_prepack",false),"estimate":int(_jobs[path].estimate.estimated_bytes),"total":_admission.reserved_bytes,"stage":_jobs[path].stage})
				if flip_after_second and dispatches.size()==2:Deferred.full_native_template_reuse_enabled=false
		if reject_start:return ERR_CANT_CREATE
		return super._start_worker(worker,task)
	func _poll_jobs(required:Dictionary)->void:
		super._poll_jobs(required)
		for path:String in _jobs:
			var job:Dictionary=_jobs[path]
			if not job.has("worker") and job.has("result"):
				var owner:Variant=job.result.get("native_packet",{}).get("packed")
				if owner is PackedScene and not original_owners.has(path):original_owners[path]=weakref(owner)

func classifier_fixture(local_mesh:bool,local_material:bool,local_texture:bool,grass:bool,scripted:bool=false)->Dictionary:
	var scene:=Node3D.new();var part:=MeshInstance3D.new();scene.add_child(part);part.owner=scene
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var mesh:=ArrayMesh.new();mesh.resource_local_to_scene=local_mesh;mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=StandardMaterial3D.new();material.resource_local_to_scene=local_material
	var img:=Image.create(2,2,false,Image.FORMAT_RGBA8);img.fill(Color.RED)
	var tex:=ImageTexture.create_from_image(img);tex.resource_local_to_scene=local_texture;material.albedo_texture=tex
	mesh.surface_set_material(0,material);part.mesh=mesh
	if grass:part.set_meta("extras",{"rmmo_grass":true})
	if scripted:
		var script:=GDScript.new();script.source_code="extends MeshInstance3D\n";script.reload();part.set_script(script)
	var packed:=PackedScene.new();var code:=packed.pack(scene);packed.set_meta("compiled_asset_validated",true)
	var observed:Dictionary={};var stats:Dictionary=FullFootprint.measure(packed,observed)
	Drainer.dispose_scene(scene);return {"code":code,"stats":stats,"reuse":observed}

func make_queue(values:Array,require_native:bool=true)->Dictionary:
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[]);map.set_meta("extras",{"rmmo_records":[]})
	var index:Dictionary=preload("res://scripts/world3d/stream_index.gd").build([])
	for key:String in index:map.set_meta(key,index[key])
	var queue:=DirectQueue.new();queue._doc=preload("res://scripts/world3d/world_document.gd").new();queue.require_native_products=require_native
	var pending:Array=[]
	for i:int in values.size():
		var sample:Dictionary=values[i];var record:Dictionary={"uuid":"direct_%d"%i,"kind":"asset","asset_path":sample.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
		pending.append({"record":record,"path":sample.path,"bounds":AABB(Vector3(-2,-2,-2),Vector3(4,5,5)),"digest":sample.sha,"memory":sample.observation.memory,"manifest":sample.observation})
	queue.pending=pending;map.add_child(queue);queue.activate(map);queue.set_demand("test",AABB(Vector3(-4,-4,-4),Vector3(8,8,8)))
	return {"map":map,"queue":queue}

func count_trace(trace:Dictionary,label:String)->int:
	var amount:=0
	for stat:Dictionary in trace.get("stats",[]):
		if stat.label==label:amount+=int(stat.count)
	return amount

func check_offline_refresh()->void:
	var path:=directory.path_join("refresh_fixture.glb");write(path,data());created.append(path)
	var sha:=FileAccess.get_sha256(path);var built:=FullCompiled.build(path)
	check(built.get("ok",false),"offline refresh source product built")
	if not built.get("ok",false):return
	var index_path:=FullCompiled.index_path(path,directory);var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index_path))
	var product:=FullCompiled.directory(directory).path_join(str(index.payload_sha)+".scn");var descriptor:=FullFootprint.descriptor_path(path,directory)
	for item:String in [index_path,product,descriptor]:created.append(item)
	var generated:=FullFootprint.build(path,directory);check(generated.get("ok",false),"offline refresh baseline descriptor built")
	if not generated.get("ok",false):return
	var envelope:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor));var body:Dictionary=JSON.parse_string(envelope.body);var bounds:Variant=body.model_metadata
	body.erase("direct_template_reuse");check(FullFootprint._publish(body,descriptor,directory)==OK,"old descriptor intentionally lacks direct flag")
	var before_product:=FileAccess.get_sha256(product)
	check(DirAccess.remove_absolute(path)==OK and not FileAccess.file_exists(path),"offline direct classification does not require authoring GLB")
	var refreshed:=FullFootprint.refresh_direct_template_reuse(path,directory)
	check(refreshed.get("ok",false) and refreshed.get("safe",false),"offline refresh classifies fixed product without rebuilding it")
	check(not FileAccess.file_exists(path) and FileAccess.get_sha256(product)==before_product,"offline refresh never restores source and leaves native product untouched")
	var after_envelope:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor));var after_body:Dictionary=JSON.parse_string(after_envelope.body)
	check(after_body.get("model_metadata")==bounds and after_body.get("source_sha")==sha and after_body.get("payload_sha")==before_product,"offline refresh preserves model metadata and source/payload binding")

func check_descriptor_gate(sample:Dictionary)->void:
	var filename:String=sample.descriptor;var original:=FileAccess.get_file_as_bytes(filename)
	var envelope:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(filename));var body:Dictionary=JSON.parse_string(envelope.body)
	for marker:Variant in [null,{"version":2,"safe":true},{"version":1,"safe":"true"},{"version":1,"safe":false}]:
		if marker==null:body.erase("direct_template_reuse")
		else:body.direct_template_reuse=marker
		check(FullFootprint._publish(body,filename,directory)==OK,"private descriptor variant published")
		var candidate:Dictionary=FullFootprint.candidate(sample.path,directory,sample.sha,true)
		check(not candidate.get("direct_template_reuse_safe",false),"missing, unknown or false direct marker falls back")
	FileAccess.open(filename,FileAccess.WRITE).store_buffer(original)
	check(FullFootprint.candidate(sample.path,directory,sample.sha,true).get("direct_template_reuse_safe",false),"restored descriptor remains product-bound and safe")

func check_direct_intern(sample:Dictionary)->void:
	var candidate:Dictionary=sample.observation.native_candidate
	var packet:Dictionary=await worker_result(Deferred._prepare_fixed_scene.bind(sample.path,sample.sha,null,sample.observation,true,directory,candidate,Deferred.CollisionGeometry.ALL,true,false))
	var scene:Variant=packet.get("scene");var owner:Variant=packet.get("native_packet",{}).get("packed")
	if not scene is Node or not owner is PackedScene:check(false,"direct intern fixture prepared");Drainer.dispose_result(packet);return
	var meshes:Array=preload("res://scripts/world3d/surface_materials.gd").meshes(scene)
	var material:StandardMaterial3D=meshes[0].get_active_material(0) if not meshes.is_empty() else null
	if material==null or material.albedo_texture==null:check(false,"direct intern textured material");Drainer.dispose_result(packet);return
	var cache=preload("res://scripts/world3d/model_texture_cache.gd")
	var img:=material.albedo_texture.get_image();var key:String=cache.pixel_key(img);var seed:=ImageTexture.create_from_image(img);seed.set_meta(cache.PIXEL_KEY,key);cache._textures.clear();cache._remember(key,seed)
	check(Library.cache_direct_native_scene(sample.path,scene,owner,sample.sha),"direct native owner accepted after main texture interning")
	packet.erase("scene");scene=null
	var first:=Library.instantiate(sample.path,true);var second:=Library.instantiate(sample.path,true)
	if first==null or second==null:check(false,"direct intern two instances")
	else:
		var a:MeshInstance3D=preload("res://scripts/world3d/surface_materials.gd").meshes(first)[0];var b:MeshInstance3D=preload("res://scripts/world3d/surface_materials.gd").meshes(second)[0]
		var ma:StandardMaterial3D=a.get_active_material(0);var mb:StandardMaterial3D=b.get_active_material(0)
		check(ma.albedo_texture==seed and mb.albedo_texture==seed and ma.albedo_texture.get_rid()==mb.albedo_texture.get_rid(),"direct instances share main-interned texture RID")
	if first!=null:Drainer.dispose_scene(first)
	if second!=null:Drainer.dispose_scene(second)
	owner=null;material=null;meshes.clear();Drainer.dispose_result(packet);Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()

func check_ready_cancellation(sample:Dictionary)->void:
	Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()
	Deferred.full_native_template_reuse_enabled=true;Deferred.full_native_worker_prepack_enabled=false
	var holder:=make_queue([sample]);var queue:DirectQueue=holder.queue;queue.set_process(false)
	queue._refresh_demanded();queue._dispatch_deadline=Time.get_ticks_usec()+100000;queue._dispatch_jobs(self);queue._dispatch_deadline=0
	var until:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<until:
		queue._poll_jobs(queue._demanded_by_path)
		if queue._jobs.has(sample.path) and queue._jobs[sample.path].has("result") and not queue._jobs[sample.path].has("worker"):break
		await process_frame
	var job:Dictionary=queue._jobs.get(sample.path,{})
	check(job.has("result") and not job.get("accepted",false) and job.get("direct_template_reuse",false),"actual fixed-native direct job reached ready before acceptance")
	if job.has("result"):
		var node:Variant=job.result.get("scene");var original:Variant=job.result.get("native_packet",{}).get("packed")
		if node is Node and original is PackedScene:
			var node_ref:WeakRef=weakref(node);var owner_ref:WeakRef=weakref(original);node=null;original=null
			check(queue._admission.reserved_bytes>=sample.footprint_bytes,"ready direct owner remains fully charged")
			queue._poll_jobs({});job={}
			for frame:int in 30:await process_frame
			check(node_ref.get_ref()==null and owner_ref.get_ref()==null and queue._admission.reserved_bytes==0,"real ready cancellation clears owners and full lease")
		else:check(false,"ready direct fixture retains private scene and original owner")
	var ledger:RefCounted=queue._admission;queue.shutdown();holder.map.queue_free();Drainer.synchronize_transfer()
	check(ledger.reserved_bytes==0,"cancelled queue leaves no reservation")

func check_two_jobs(values:Array,direct:bool)->void:
	for sample:Dictionary in values:Library.evict_cached_scene(sample.path)
	Drainer.synchronize_transfer();Deferred.full_native_template_reuse_enabled=direct;Deferred.full_native_worker_prepack_enabled=direct
	var holder:=make_queue(values);var queue:DirectQueue=holder.queue;queue.flip_after_second=direct
	var trace=preload("res://scripts/world3d/load_trace.gd");trace.start()
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline and queue.error.is_empty():
		if queue.dispatches.size()==2 and int(queue.profile.get("models",0))>=2:break
		await process_frame
	var observed:Dictionary=trace.stop()
	check(queue.dispatches.size()==2 and int(queue.profile.get("models",0))>=2,"two real source-free model jobs accepted")
	var dispatched:=queue.dispatches.size()==2
	for d:Dictionary in queue.dispatches:dispatched=dispatched and d.direct==direct and not d.prepack and d.stage=="fixed_native"
	check(dispatched,"dispatch freezes direct selection and excludes worker pack")
	check(count_trace(observed,"asset_library.cache_pack")== (0 if direct else 2),"main pack count matches direct selection")
	check(count_trace(observed,"deferred.worker_native_pack")==0,"direct and off baseline never use worker prepack")
	check(int(queue.profile.get("full_native_reused_templates",0))==(2 if direct else 0),"direct acceptance counter matches")
	if direct:
		check(not Deferred.full_native_template_reuse_enabled,"global flag flip does not change in-flight decisions")
		for sample:Dictionary in values:
			var owner:WeakRef=queue.original_owners.get(sample.path)
			check(owner!=null and Library._scenes.get(sample.path)==owner.get_ref(),"published template is same fixed native owner")
	for sample:Dictionary in values:
		var instance:=Library.instantiate(sample.path,true)
		check(instance!=null and has_textured_material(instance),"source-free published template keeps textured material")
		if instance!=null:Drainer.dispose_scene(instance)
	var ledger:RefCounted=queue._admission;queue.shutdown();holder.map.queue_free()
	for sample:Dictionary in values:Library.evict_cached_scene(sample.path)
	Drainer.synchronize_transfer();for frame:int in 30:await process_frame
	check(ledger.reserved_bytes==0,"two jobs release full admission ledger")

func check_negative_dispatch(sample:Dictionary,white:bool,editor:bool,white_material:bool=false)->void:
	Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()
	Deferred.full_native_template_reuse_enabled=true;Deferred.full_native_worker_prepack_enabled=true
	var before:bool=Controls.native_geometry_only;var before_material:bool=Controls.white_materials
	Controls.native_geometry_only=white;Controls.white_materials=white_material
	var holder:=make_queue([sample],not editor);var queue:DirectQueue=holder.queue;queue.set_process(false);queue.reject_start=true
	queue._refresh_demanded();queue._dispatch_deadline=Time.get_ticks_usec()+100000;queue._dispatch_jobs(self);queue._dispatch_deadline=0
	check(queue.dispatches.size()==1 and not queue.dispatches[0].direct and not queue.dispatches[0].prepack,"white/editor never dispatch either full native candidate")
	queue.shutdown();holder.map.queue_free();Controls.native_geometry_only=before;Controls.white_materials=before_material

func run()->void:
	create_timer(180).timeout.connect(func():printerr("DIRECT_NATIVE_CONTRACT timed out");quit(2))
	if DisplayServer.get_name()=="headless":check(false,"direct contract requires private GPU desktop");quit(1);return
	gpu=true;Policy.verify_packages=false;Controls.white_materials=false;Controls.native_geometry_only=false;Controls.discard_map_textures=false
	directory="D:/code/rmmo_runtime/review_artifacts/direct_native_contract_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()];DirAccess.make_dir_recursive_absolute(directory)
	var manager:=root.get_node("AssetManager");var previous_root:String=manager.content_root_override;manager.content_root_override=directory
	for options:Array in [[false,false,false,false],[true,false,false,false],[false,true,false,false],[false,false,true,false],[false,false,false,true]]:
		var classification:=classifier_fixture(options[0],options[1],options[2],options[3]);check(classification.code==OK and not classification.stats.is_empty(),"fixture classification succeeded")
		check(classification.reuse.get("safe",false)==(not options[0] and not options[1] and not options[2] and not options[3]),"offline classifier excludes local mesh, material, texture or grass")
	var scripted:=classifier_fixture(false,false,false,false,true)
	check(scripted.stats.is_empty() and not scripted.reuse.get("safe",false),"script-bearing native input is rejected by offline classification")
	check_offline_refresh()
	var seed:=directory.path_join("identity_seed.glb");write(seed,data());var sha:=FileAccess.get_sha256(seed);DirAccess.remove_absolute(seed)
	for path:String in [directory.path_join(sha+".glb"),directory.path_join("named_model.glb")]:
		var sample:=make_sample(path)
		if not sample.is_empty():samples.append(sample)
	check(samples.size()==2,"two native products built and sources removed")
	for sample:Dictionary in samples:check(sample.observation.native_candidate.get("direct_template_reuse_safe",false),"offline footprint marks safe full native product")
	if samples.size()==2:
		check_descriptor_gate(samples[0])
		await check_direct_intern(samples[0])
		await check_two_jobs(samples,false)
		await check_ready_cancellation(samples[0])
		await check_two_jobs(samples,true)
		check_negative_dispatch(samples[0],true,false)
		check_negative_dispatch(samples[0],false,false,true)
		check_negative_dispatch(samples[0],false,true)
	for sample:Dictionary in samples:Library.evict_cached_scene(sample.path)
	Drainer.synchronize_transfer();manager.content_root_override=previous_root;Deferred.full_native_template_reuse_enabled=false;Deferred.full_native_worker_prepack_enabled=false
	for item:String in created:
		if FileAccess.file_exists(item):DirAccess.remove_absolute(item)
	print("DIRECT_NATIVE_CONTRACT passed=",passed," failures=",failures);quit(1 if failures else 0)
