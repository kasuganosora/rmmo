extends "res://tools/test_asset_bounds_manifest.gd"
## Default: headless metadata/hint regression with a private stand-in payload.
## --gpu: actual native writer, loader workers, library and deferred templates.
## Every GLB is generated here, exported, then deleted before runtime checks.
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Metadata=preload("res://scripts/world3d/white_native_asset_metadata.gd")
const Source=preload("res://scripts/world3d/asset_source_metadata.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const TargetPrefetch=preload("res://scripts/world3d/target_scene_prefetch.gd")
const CrossPrefetch=preload("res://scripts/world3d/cross_map_prefetch.gd")
const DependencyIndex=preload("res://scripts/world3d/map_dependency_index.gd")
const ResourceStore=preload("res://scripts/world3d/map_resource_store.gd")
const Location=preload("res://scripts/world3d/world_location.gd")
const Bridge=preload("res://scripts/world3d/bridge_mesh.gd")
const Fortification=preload("res://scripts/world3d/fortification_art.gd")
class SourceHashTrap extends "res://scripts/world3d/model_source_hashes.gd":
	var calls:=0
	func run(_paths:Array,_root:String,_workers:int=4,_starter:Callable=Callable(),_reader:Callable=Callable())->Dictionary:
		calls+=1
		return {"error":ERR_BUG,"reason":"native route dispatched authoring-source hasher","error_path":"","elapsed_us":0,"signatures":{}}
var created:Array[String]=[]
var samples:Array[Dictionary]=[]
var directory:=""
var gpu:=false

func save_bytes(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes);file.close()

func save_index(path:String,info:Dictionary)->void:
	save_bytes(Native.index_path(path,directory),JSON.stringify(info).to_utf8_buffer())

func make_sample(path:String,source_data:Dictionary={})->Dictionary:
	write(path,data() if source_data.is_empty() else source_data);created.append(path)
	var sha:=FileAccess.get_sha256(path)
	var expected:=Manifest.read(path);var memory:=Metadata.Memory.estimate(path)
	var built:Dictionary
	if gpu:
		built=Native.build(path,directory)
	else:
		# No ResourceLoader or Mesh API in the headless branch. This only tests
		# the exported descriptor contract; --gpu covers actual native decoding.
		var bytes:=PackedByteArray([1,2,3,4]);var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes)
		var digest:=hash_.finish().hex_encode();var product:=Native.directory(directory).path_join(digest+".scn")
		save_bytes(product,bytes)
		var info:={"generator":Native.generator(),"source_sha":sha,"payload_sha":digest,"bytes":bytes.size()}
		save_index(path,info)
		var descriptor:=Metadata.build(path,directory)
		built={"ok":descriptor.ok,"product":product,"manifest":info,"metadata":descriptor}
	check(built.get("ok",false),"offline fixture exports before the original GLB is removed")
	if not built.get("ok",false):print(built);return {}
	for target:String in [built.product,Native.index_path(path,directory),built.metadata.descriptor]:
		if not created.has(target):created.append(target)
	check(DirAccess.remove_absolute(path)==OK and not FileAccess.file_exists(path),"runtime fixture physically has no original GLB: "+path.get_file())
	return {"path":path,"sha":sha,"expected":expected,"memory":memory,"product":built.product,"index":built.manifest,"descriptor":built.metadata.descriptor,"observation":built.metadata.observation}

func run()->void:
	gpu="--gpu" in OS.get_cmdline_user_args()
	if gpu and DisplayServer.get_name()=="headless":
		check(false,"--gpu requires the isolated graphics desktop");quit(1);return
	Policy.verify_packages=false;Controls.enable_white_materials();Controls.discard_map_textures=true
	directory=Paths.cache_directory("native_without_source_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(Native.directory(directory))
	var manager:=root.get_node("AssetManager");var previous_root:String=manager.content_root_override
	manager.content_root_override=directory
	# The temporary seed exists only to choose a real content-addressed key.
	var seed:=directory.path_join("identity_seed.glb");write(seed,data())
	var source_sha:=FileAccess.get_sha256(seed);DirAccess.remove_absolute(seed)
	for path:String in [directory.path_join(source_sha+".glb"),directory.path_join("named_model.glb")]:
		var sample:=make_sample(path)
		if not sample.is_empty():samples.append(sample)
	for sample:Dictionary in samples:check_metadata_without_source(sample)
	check_cold_hints()
	check_remaining_source_signatures()
	check_target_prefetch()
	check_cold_cross_map_prefetch()
	if gpu:
		for sample:Dictionary in samples:await check_runtime_without_source(sample)
		await check_preparation_without_source()
		await check_initial_loader_without_source()
		check_kits_without_source()
	for sample:Dictionary in samples:
		check_missing_or_changed_metadata(sample)
		if gpu:check_missing_or_changed_product(sample)
		check(not FileAccess.file_exists(sample.path),"no runtime check recreated or restored the original GLB")
	for sample:Dictionary in samples:Library.evict_cached_scene(sample.path)
	if gpu:Drainer.synchronize_transfer()
	manager.content_root_override=previous_root
	for path:String in created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	print("NATIVE_WITHOUT_SOURCE mode=",("gpu" if gpu else "headless_metadata")," passed=",passed," failures=",failures)
	quit(1 if failures else 0)

func check_metadata_without_source(sample:Dictionary)->void:
	var observed:=Source.read(sample.path,directory,"",true)
	check(observed.get("known",false) and observed.get("native_metadata_hit",false),"native-only metadata survives absent "+sample.path.get_file())
	check(observed.get("local_bounds")==sample.expected.local_bounds and observed.get("memory")==sample.memory,"offline exact bounds and conservative memory survive without inspecting the GLB")
	if observed.get("known",false):
		check(Metadata.Memory.from_manifest(sample.path,observed)==sample.memory,"admission reuses exported memory instead of falling back to GLB estimation")

func check_cold_hints()->void:
	var records:Array=[];var expected:Array=[]
	for sample:Dictionary in samples:
		expected.append(sample.path)
		var record:={"uuid":"near_%d"%records.size(),"kind":"asset","asset_path":sample.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
		records.append(record)
		var far:=record.duplicate(true);far.uuid+="_far";far.position[0]=500;records.append(far)
	var loader:=Loader.new();loader._content_root=directory;loader._entry_origin=Vector3.ZERO;loader._model_preparation.require_native_products=true
	var hints:Dictionary=loader._cold_model_hints(records)
	check(hints.error.is_empty() and hints.paths==expected and hints.manifests.size()==samples.size(),"cold-loader hints classify repeated near/far instances without any original GLB")
	loader.free()

func check_remaining_source_signatures()->void:
	var loader:=Loader.new();loader._content_root=directory;loader._model_preparation.require_native_products=true
	var trap:=SourceHashTrap.new();loader._source_hash_preparation=trap
	var paths:Array=[];var expected:={}
	for sample:Dictionary in samples:paths.append(sample.path);expected[sample.path]=sample.sha
	var observed:Dictionary=loader._prepare_source_signatures(paths)
	check(observed.get("error",FAILED)==OK and observed.get("signatures",{})==expected and observed.get("mode")=="native_product_index","remaining fortification/art identities resolve from native package descriptors")
	check(trap.calls==0 and observed.get("source_reads",-1)==0,"native identity collection never dispatches the original-source hash coordinator")
	var missing:=paths.duplicate();missing.append(directory.path_join("no_native_product.glb"))
	var rejected:Dictionary=loader._prepare_source_signatures(missing)
	check(rejected.get("error",OK)!=OK and rejected.get("signatures",{}).is_empty() and trap.calls==0,"missing remaining native identity fails atomically without source hashing")
	loader.free()

func check_target_prefetch()->void:
	var map_path:=directory.path_join("prefetch_identity.gltf")
	save_bytes(map_path,"isolated prefetch identity fixture".to_utf8_buffer());created.append(map_path)
	var records:Array=[]
	for sample:Dictionary in samples:
		records.append({"uuid":"prefetch_%d"%records.size(),"kind":"asset","asset_path":sample.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]})
	var plan:=TargetPrefetch.plan(records,directory,map_path,FileAccess.get_sha256(map_path),{})
	check(not plan.is_empty(),"target prefetch plans absent-source native models from offline memory descriptors")
	if plan.is_empty():return
	var files:Dictionary=plan.files;var structure_ok:=true
	for sample:Dictionary in samples:
		var product:Variant=files.get(sample.product)
		structure_ok=structure_ok and not files.has(sample.path) and files.get(Native.index_path(sample.path,directory)) is String and files.get(sample.descriptor) is String
		structure_ok=structure_ok and product is Dictionary and product.get("native_product",false) and product.get("sha256")==sample.index.payload_sha and int(product.get("length",-1))==int(sample.index.bytes)
	check(structure_ok,"prefetch files include native index/descriptor and structured product length/SHA, never GLB")
	var metadata_hashes_match:=true
	for sample:Dictionary in samples:
		for metadata_path:String in [Native.index_path(sample.path,directory),sample.descriptor]:
			var actual_bytes:=FileAccess.get_file_as_bytes(metadata_path)
			var oracle:=HashingContext.new();oracle.start(HashingContext.HASH_SHA256);oracle.update(actual_bytes)
			metadata_hashes_match=metadata_hashes_match and files.get(metadata_path)==oracle.finish().hex_encode()
	check(metadata_hashes_match,"prefetch metadata identities exactly match independent SHA256 of the original index and descriptor bytes")
	check(TargetPrefetch.verify(files,directory),"trusted target verification succeeds with every original GLB absent")
	if samples.is_empty():return
	var sample:Dictionary=samples[0];var incorrect:=files.duplicate(true)
	if not incorrect.get(sample.product) is Dictionary:return
	incorrect[sample.product].length+=1
	check(not TargetPrefetch.verify(incorrect,directory),"target verification rejects a mismatched native product length")
	var product_bytes:=FileAccess.get_file_as_bytes(sample.product)
	var outside:=directory.path_join("outside_native_folder.scn");save_bytes(outside,product_bytes);created.append(outside)
	incorrect=files.duplicate(true);incorrect[outside]=incorrect[sample.product];incorrect.erase(sample.product)
	check(not TargetPrefetch.verify(incorrect,directory),"structured native identity cannot authorize an identical file outside the native product directory")
	Policy.verify_packages=true
	check(TargetPrefetch.verify(files,directory),"explicit verification authenticates native payload SHA without a GLB dependency")
	var altered:=product_bytes.duplicate();altered[altered.size()-1]=altered[altered.size()-1]^1;save_bytes(sample.product,altered)
	check(not TargetPrefetch.verify(files,directory),"explicit verification rejects same-length native payload changes")
	save_bytes(sample.product,product_bytes);Policy.verify_packages=false

func write_reference_fixture(path:String,records:Array)->bool:
	# Use the same immutable reference writer as a saved native map. A document
	# save would correctly require its authoring GLB, which this runtime no longer has.
	var stored:=ResourceStore.write_records(records,path,directory)
	if not stored.get("ok",false):return false
	var extras:={"rmmo_format":Location.FORMAT,"rmmo_version":Location.FORMAT_VERSION,"rmmo_storage":Location.STORAGE,"rmmo_unit":"m","rmmo_records":stored.records,"rmmo_resource_dependencies":stored.dependencies,"spawn":[0,1,0]}
	var contents:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extras}]}
	save_bytes(path,JSON.stringify(contents).to_utf8_buffer());created.append(path)
	created.append(DependencyIndex.cache_path(path,directory))
	for uri:String in stored.dependencies:created.append(path.get_base_dir().path_join(uri))
	return true

func check_cold_cross_map_prefetch()->void:
	if samples.size()!=2:return
	# A human-readable key and two instances expose both source hash fallbacks
	# and the accidental conversion of every far instance into a global row.
	var sample:Dictionary=samples[1]
	var path:=directory.path_join("cold_native_target.gltf")
	var near:={"uuid":"near_native","kind":"asset","asset_path":sample.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"surface_id":"model","collision":"none"}
	var far:Dictionary=near.duplicate(true);far.uuid="far_native";far.position[0]=500
	var saved:=write_reference_fixture(path,[near,far])
	check(saved,"cold cross-map fixture writes a real map and deduplicated immutable model references")
	if not saved:return
	var cache:=DependencyIndex.cache_path(path,directory)
	var source_sha:=FileAccess.get_sha256(path)
	check(not FileAccess.file_exists(sample.path) and not FileAccess.file_exists(cache),"cross-map preparation starts without an authoring GLB or a dependency directory")
	var prepared:=CrossPrefetch.prepare(path,Vector3(1,.9,1),directory,Drainer.CancelToken.new(),CrossPrefetch.LEASE_BYTES)
	var packet:Variant=prepared.get("packet")
	check(packet!=null,"cold cross-map preparation produces a native packet with the original GLB absent")
	if packet!=null:
		check(packet.selected==[0] and packet.restored.extras.rmmo_records.size()==1 and packet.restored.extras.rmmo_records[0].uuid==near.uuid,"cold native classification selects the near instance and leaves the distant duplicate deferred")
		check(not packet.scene_plan.is_empty() and not packet.scene_plan.files.has(sample.path) and packet.scene_plan.files.has(sample.product),"cold cross-map scene plan covers the native product without any GLB dependency")
	var index:=DependencyIndex.read(path,directory,source_sha,DependencyIndex.Snapshot.RETAIN_LIMIT,DependencyIndex.MAX_BYTES,1,true)
	var spatial:bool=index.get("ok",false) and index.get("models",{}).size()==1 and index.get("rows",[]).size()==2
	if spatial:
		spatial=index.models.has(sample.path) and index.models[sample.path].local_bounds==sample.expected.local_bounds
		for i:int in 2:
			var expected:AABB=Transform3D(Basis.IDENTITY,Vector3(i*500,0,0))*sample.expected.local_bounds
			spatial=spatial and index.rows[i].classification=="spatial" and index.rows[i].reason=="model_accessor_bounds" and index.rows[i].bounds==expected
	check(spatial,"cold directory persists exact native bounds for both instances instead of raw-source global degradation")
	for handoff:bool in [false,true]:
		if FileAccess.file_exists(cache):DirAccess.remove_absolute(cache)
		# Both public build APIs can be called without the main loader's private
		# manifest hint table (e.g. optional post-load directory construction).
		var built:Dictionary=DependencyIndex.build_for_loading(path,directory,[near,far],source_sha,1,DependencyIndex.Snapshot.RETAIN_LIMIT,true) if handoff else DependencyIndex.build(path,directory,[near,far],source_sha,1,DependencyIndex.Snapshot.RETAIN_LIMIT,true)
		var observed:Dictionary=built.get("index",{}) if handoff else built
		var valid:bool=built.get("ok",false) and observed.get("models",{}).size()==1 and observed.get("models",{}).has(sample.path) and observed.get("rows",[]).size()==2
		if valid:
			valid=observed.models[sample.path].local_bounds==sample.expected.local_bounds and observed.rows.all(func(row):return row.classification=="spatial" and row.reason=="model_accessor_bounds")
		check(valid,("build_for_loading" if handoff else "build")+" resolves one native model for two spatial rows without supplied manifests or GLB")
	# Force a second independent cold build. Missing native metadata must decline
	# speculation, not publish a global directory derived from a missing GLB.
	if FileAccess.file_exists(cache):DirAccess.remove_absolute(cache)
	var descriptor:=FileAccess.get_file_as_bytes(sample.descriptor);DirAccess.remove_absolute(sample.descriptor)
	var rejected:=CrossPrefetch.prepare(path,Vector3(1,.9,1),directory,Drainer.CancelToken.new(),CrossPrefetch.LEASE_BYTES)
	check(rejected.is_empty(),"cold cross-map preparation declines missing native metadata without raw fallback")
	check(not FileAccess.file_exists(cache),"missing native metadata cannot publish a falsely complete dependency directory")
	for handoff:bool in [false,true]:
		if FileAccess.file_exists(cache):DirAccess.remove_absolute(cache)
		var built:Dictionary=DependencyIndex.build_for_loading(path,directory,[near,far],source_sha,1,DependencyIndex.Snapshot.RETAIN_LIMIT,true) if handoff else DependencyIndex.build(path,directory,[near,far],source_sha,1,DependencyIndex.Snapshot.RETAIN_LIMIT,true)
		check(not built.get("ok",false),("build_for_loading" if handoff else "build")+" rejects missing native metadata instead of silently downgrading models")
		check(not FileAccess.file_exists(cache),("build_for_loading" if handoff else "build")+" failure publishes no dependency directory")
	save_bytes(sample.descriptor,descriptor)
	check(FileAccess.get_sha256(path)==source_sha and not FileAccess.file_exists(sample.path),"cold speculative preparation leaves the authored map unchanged and the GLB absent")

func worker_result(task:Callable)->Dictionary:
	var worker:=Thread.new();var error:=worker.start(task)
	check(error==OK,"private native preparation worker starts")
	if error!=OK:return {"error":error}
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish();Drainer.synchronize_transfer()
	return result

func check_runtime_without_source(sample:Dictionary)->void:
	# Empty declared digest is intentional: even non-SHA logical asset keys
	# must resolve from the native package, without source_identity scanning GLB.
	var packet:=Native.read(sample.path,"",directory,true)
	check(packet.get("hit",false) and packet.get("source_digest")==sample.sha,"native cache resolves an absent source's logical key from its native index")
	if packet.get("hit",false):
		var instance:Node=packet.packed.instantiate()
		check(instance!=null and instance.find_children("*","MeshInstance3D",true,false).size()==1,"native decode retains the actual exported mesh hierarchy")
		if instance!=null:Drainer.dispose_scene(instance)
	Drainer.dispose_result(packet);Drainer.synchronize_transfer()
	Library.evict_cached_scene(sample.path)
	var first:=Library.instantiate(sample.path,true);var second:=Library.instantiate(sample.path,true)
	check(first!=null and second!=null,"AssetLibrary native-only cold lookup and cached reuse do not require original GLB existence")
	if first!=null and second!=null:check_shared_mesh(first,second)
	if first!=null:Drainer.dispose_scene(first)
	if second!=null:Drainer.dispose_scene(second)
	Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()
	var prepared:Dictionary=await worker_result(Deferred.prepare_scene.bind(sample.path,"",null,sample.observation,true,directory,false,Deferred.CollisionGeometry.ALL,true,true,true))
	check(str(prepared.get("error","unknown")).is_empty() and prepared.get("compiled",false) and prepared.has("packed") and not prepared.has("scene"),"deferred native-only preparation hands off a template without raw fallback or repacking")
	if prepared.has("packed"):
		check(Library.cache_packed(sample.path,prepared.packed,sample.sha),"library accepts the exact deferred native template")
		if prepared.has("resource_owners"):prepared.resource_owners.transfer_template(prepared.packed)
		var reused:=Library.instantiate(sample.path,true)
		check(reused!=null,"deferred template remains instantiable after the source was removed")
		if reused!=null:Drainer.dispose_scene(reused)
	var preflight:=Deferred._preflight_reused_source(sample.path,sample.sha,directory,null,true)
	var verification:=Deferred._verify_reused_source(sample.path,sample.sha,directory,null,true)
	check(preflight.error.is_empty() and verification.error.is_empty(),"trusted deferred template reuse does not reject an absent authoring source")
	Drainer.dispose_result(prepared);Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()

func check_shared_mesh(first:Node,second:Node)->void:
	var a:=first.find_children("*","MeshInstance3D",true,false);var b:=second.find_children("*","MeshInstance3D",true,false)
	check(a.size()==1 and b.size()==1 and a[0].mesh==b[0].mesh and a[0].mesh.get_meta("ground_cpu_cache")==b[0].mesh.get_meta("ground_cpu_cache"),"repeated native instances share the same GPU mesh and CPU geometry owners")

func kit_source_data(names:Array)->Dictionary:
	# The kit wrappers require named mesh modules, not particular building
	# dimensions. Reuse the tiny triangle buffer with distinct local poses.
	var value:=data();var children:Array=[];var nodes:Array=[{"name":"kit_fixture","children":children}]
	for i in names.size():
		children.append(i+1)
		nodes.append({"name":names[i],"mesh":0,"translation":[i*2,0,0]})
	value.nodes=nodes
	return value

func check_kit_geometry(pieces:Dictionary,names:Array)->bool:
	if pieces.size()!=names.size():return false
	for i in names.size():
		var piece:Dictionary=pieces.get(names[i],{})
		var mesh:Mesh=piece.get("mesh")
		if mesh==null or mesh.get_surface_count()!=1:return false
		if piece.get("transform")!=Transform3D(Basis.IDENTITY,Vector3(i*2,0,0)):return false
	return true

func check_kits_without_source()->void:
	var fortification:=Fortification.new()
	for kind:String in ["bridge","fortification"]:
		var names:Array=["arch","pier","abutment","deck","parapet","post"] if kind=="bridge" else Fortification.MODULES.duplicate()
		var sample:=make_sample(directory.path_join(kind+"_modules.glb"),kit_source_data(names))
		if sample.is_empty():continue
		var path:String=sample.path
		# Start with both wrapper and library caches cold. The authoring route
		# still requires its source; only the explicit native route may use SCN.
		Bridge.kits.erase(path);Fortification.kits.erase(path);Library.evict_cached_scene(path)
		var authoring:Dictionary=Bridge.kit(path,false) if kind=="bridge" else fortification.kit(path,false)
		check(authoring.is_empty(),kind+" authoring kit still rejects an absent GLB")
		var pieces:Dictionary=Bridge.kit(path,true) if kind=="bridge" else fortification.kit(path,true)
		check(not pieces.is_empty(),kind+" native-only kit loads actual modules after its GLB has been deleted")
		check(check_kit_geometry(pieces,names),kind+" native-only kit retains every required named mesh and local transform")
		var reused:Dictionary=Bridge.kit(path,true) if kind=="bridge" else fortification.kit(path,true)
		var same_meshes:=not pieces.is_empty() and reused.size()==pieces.size()
		for key in pieces:
			same_meshes=same_meshes and reused.get(key,{}).get("mesh")==pieces[key].mesh
		check(same_meshes,kind+" repeated native kit lookup reuses the exported mesh resources")
		check(not FileAccess.file_exists(path),kind+" kit lookup never restores an authoring source or uses a raw fallback")
		Bridge.kits.erase(path);Fortification.kits.erase(path);Library.evict_cached_scene(path)
		pieces.clear();reused.clear()
	Drainer.synchronize_transfer()

func check_preparation_without_source()->void:
	var controller:=Preparation.new();controller.require_native_products=true;controller.prepare_static_scenes=true
	var paths:Array=[]
	for sample:Dictionary in samples:paths.append(sample.path);controller.static_scene_paths[sample.path]=sample.observation
	var prepared:Dictionary=await worker_result(controller.run.bind(paths,Callable(),2,Callable(),directory,{}))
	check(prepared.get("error",FAILED)==OK and prepared.get("native_cache_hits",0)==samples.size(),"initial model preparation completes every absent-source native model")
	var stages:Dictionary=prepared.get("admission_profile",{}).get("stages",{})
	check(not stages.has("raw_import") and prepared.get("serial_fallbacks",-1)==0 and prepared.get("native_cache_misses",-1)==0,"native-only preparation never schedules a raw GLTF fallback")
	Drainer.dispose_result(prepared);Drainer.synchronize_transfer()

func check_initial_loader_without_source()->void:
	if samples.size()!=2:return
	var model:Dictionary=samples[0];var art:Dictionary=samples[1]
	var loader:=Loader.new();loader._content_root=directory;loader.near_first=true
	# Empty terrain preparation stays synchronous; model decoding still uses
	# the real coordinator. This is the real entry method, without a map/GPU scene.
	loader.background_preload=true;loader._model_preparation.require_native_products=true;loader._model_preparation.prepare_static_scenes=true
	loader._record_meta={"rmmo_records":[
		{"uuid":"initial_asset","kind":"asset","asset_path":model.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]},
		{"uuid":"remaining_art","kind":"box","fortification_art":{"asset_path":art.path},"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}]}
	var trap:=SourceHashTrap.new();loader._source_hash_preparation=trap
	# No dependency directory is supplied: exercise the actual cold fallback.
	var result:Dictionary=await worker_result(func()->Dictionary:
		loader._prepare_record_assets_inner()
		return {"error":loader._error,"reason":loader._failure_reason})
	check(result.error==OK and loader._model_signatures.get(model.path)==model.sha and loader._model_signatures.get(art.path)==art.sha,"initial loader prepares an asset plus remaining fortification identity with no GLB or warm directory")
	check(loader._asset_states.has(model.path) and loader._asset_states[model.path].get("compiled",false),"initial loader retains the actual native model preparation result")
	check(trap.calls==0 and loader._profile.get("source_hash_profile",{}).get("source_reads",-1)==0,"initial loader's remaining fortification path performs zero source hashing")
	# This isolated off-tree loader owns all returned resources and any worker.
	loader._exit_tree();loader.free();Drainer.synchronize_transfer()

func check_missing_or_changed_metadata(sample:Dictionary)->void:
	var descriptor_bytes:=FileAccess.get_file_as_bytes(sample.descriptor)
	DirAccess.remove_absolute(sample.descriptor)
	check(not Source.read(sample.path,directory,"",true).get("known",false),"missing native metadata fails without falling back to GLB")
	save_bytes(sample.descriptor,descriptor_bytes)
	var stale:Dictionary=sample.index.duplicate(true);stale.generator="incompatible_native_product"
	save_index(sample.path,stale)
	check(not Source.read(sample.path,directory,"",true).get("known",false),"metadata for an incompatible native product remains rejected")
	save_index(sample.path,sample.index)

func check_missing_or_changed_product(sample:Dictionary)->void:
	Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()
	var bytes:=FileAccess.get_file_as_bytes(sample.product)
	DirAccess.remove_absolute(sample.product)
	var absent:=Native.read(sample.path,"",directory,true)
	check(not absent.get("hit",false) and Library.instantiate(sample.path,true)==null,"missing native product remains an error even when the source is optional")
	save_bytes(sample.product,PackedByteArray([1,2,3,4]))
	var corrupt:=Native.read(sample.path,"",directory,true)
	check(not corrupt.get("hit",false),"truncated native product cannot pass as a valid absent-source model")
	save_bytes(sample.product,bytes)
	Drainer.dispose_result(absent);Drainer.dispose_result(corrupt);Drainer.synchronize_transfer()
