extends "res://tools/test_native_without_source.gd"
## Real full-material native product integration on a private content root.
## Run only on the private GPU desktop: tools/run_godot_background.py.
const FullCompiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const FullFootprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const FullProduct=preload("res://scripts/world3d/native_model_product.gd")
class CountingReferenceLoader extends "res://scripts/world3d/map_loader.gd":
	var metadata_reads:=0
	func _native_model_manifest(path:String,timing:Variant=null)->Dictionary:
		metadata_reads+=1
		return super._native_model_manifest(path,timing)

func write(path:String,value:Dictionary)->void:
	# Generate a real embedded image and material. Geometry bounds remain the
	# parent fixture's triangle so the same exact-bounds checks are meaningful.
	var png_image:=Image.create(2,2,false,Image.FORMAT_RGBA8)
	png_image.set_pixel(0,0,Color.RED);png_image.set_pixel(1,0,Color.GREEN)
	png_image.set_pixel(0,1,Color.BLUE);png_image.set_pixel(1,1,Color.WHITE)
	var png:=png_image.save_png_to_buffer()
	var binary:=PackedFloat32Array([-1,0,-2,1,4,2,0,1,0]).to_byte_array()
	binary.append_array(PackedFloat32Array([0.8944272,0,-0.4472136,0.8944272,0,-0.4472136,0.8944272,0,-0.4472136]).to_byte_array())
	binary.append_array(PackedFloat32Array([0,0,1,0,0.5,1]).to_byte_array())
	var image_offset:=binary.size();binary.append_array(png)
	while binary.size()%4:binary.append(0)
	var gltf:=value.duplicate(true)
	gltf.buffers=[{"byteLength":binary.size()}]
	gltf.bufferViews=[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},{"buffer":0,"byteOffset":72,"byteLength":24},{"buffer":0,"byteOffset":image_offset,"byteLength":png.size()}]
	gltf.accessors.append({"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"})
	gltf.accessors.append({"bufferView":2,"componentType":5126,"count":3,"type":"VEC2"})
	gltf.meshes[0].primitives[0].attributes.NORMAL=1
	gltf.meshes[0].primitives[0].attributes.TEXCOORD_0=2
	gltf.images=[{"bufferView":3,"mimeType":"image/png"}]
	gltf.textures=[{"source":0}]
	gltf.materials=[{"name":"fixture_textured","pbrMetallicRoughness":{"baseColorFactor":[0.2,0.6,0.85,1.0],"baseColorTexture":{"index":0},"metallicFactor":0.0,"roughnessFactor":0.6}}]
	gltf.meshes[0].primitives[0].material=0
	var json_bytes:=JSON.stringify(gltf).to_utf8_buffer()
	while json_bytes.size()%4:json_bytes.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(12+8+json_bytes.size()+8+binary.size())
	file.store_32(json_bytes.size());file.store_32(0x4e4f534a);file.store_buffer(json_bytes)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.close()

func make_sample(path:String,source_data:Dictionary={})->Dictionary:
	write(path,data() if source_data.is_empty() else source_data)
	var sha:=FileAccess.get_sha256(path)
	var expected:=Manifest.read(path)
	var built:=FullCompiled.build(path)
	check(built.get("ok",false),"offline compiler builds the embedded-image full material product")
	if not built.get("ok",false):print("FULL_BUILD_ERROR ",built);return {}
	var index_path:=FullCompiled.index_path(path,directory)
	var index:Variant=JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not index is Dictionary:check(false,"offline compiler wrote a valid index");return {}
	var product:=FullCompiled.directory(directory).path_join(str(index.payload_sha)+".scn")
	var footprint:=FullFootprint.build(path,directory)
	check(footprint.get("ok",false),"offline footprint and bounds descriptor build before source deletion")
	if not footprint.get("ok",false):print("FULL_FOOTPRINT_ERROR ",footprint);return {}
	var descriptor:=FullFootprint.descriptor_path(path,directory)
	var native_candidate:Dictionary=footprint.get("candidate",{})
	var amount:=int(native_candidate.get("estimated_bytes",0))
	check(amount>0 and int(native_candidate.get("resident_bytes",0))==amount,"full material admission has a nonzero matching native footprint")
	for item:String in [path,product,index_path,descriptor]:
		if not created.has(item):created.append(item)
	check(DirAccess.remove_absolute(path)==OK and not FileAccess.file_exists(path),"source GLB physically removed before full runtime checks")
	var observation:=FullProduct.read(path,directory,"",-1)
	return {"path":path,"sha":sha,"expected":expected,"product":product,"index":index,"descriptor":descriptor,"observation":observation,"footprint_bytes":amount}

func run()->void:
	create_timer(180).timeout.connect(func():printerr("FULL_NATIVE_WITHOUT_SOURCE timed out");quit(2))
	if DisplayServer.get_name()=="headless":check(false,"full native test requires private GPU desktop");quit(1);return
	gpu=true
	Policy.verify_packages=false;Controls.white_materials=false;Controls.native_geometry_only=false;Controls.discard_map_textures=false
	directory="D:/code/rmmo_runtime/review_artifacts/full_native_without_source_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	var manager:=root.get_node("AssetManager");var previous_root:String=manager.content_root_override
	manager.content_root_override=directory
	var seed:=directory.path_join("identity_seed.glb");write(seed,data())
	var sha:=FileAccess.get_sha256(seed);DirAccess.remove_absolute(seed)
	for path:String in [directory.path_join(sha+".glb"),directory.path_join("named_model.glb")]:
		var sample:=make_sample(path)
		if not sample.is_empty():samples.append(sample)
	check(samples.size()==2,"both digest-named and human-named full products built")
	for sample:Dictionary in samples:check_full_metadata(sample)
	if samples.size()==2:
		check_cold_hints()
		check_remaining_source_signatures()
		check_full_target_prefetch()
		check_full_far_registration()
		for sample:Dictionary in samples:await check_full_runtime(sample)
		await check_full_preparation_without_injected_estimates()
		await check_initial_loader_without_source()
		check_full_kits()
		await check_full_missing(samples[0])
	for sample:Dictionary in samples:
		check(not FileAccess.file_exists(sample.path),"all runtime paths leave the source GLB absent")
		Library.evict_cached_scene(sample.path)
	Drainer.synchronize_transfer();manager.content_root_override=previous_root
	for item:String in created:
		if FileAccess.file_exists(item):DirAccess.remove_absolute(item)
	print("FULL_NATIVE_WITHOUT_SOURCE passed=",passed," failures=",failures," fixture=",directory)
	quit(1 if failures else 0)

func check_full_metadata(sample:Dictionary)->void:
	var observed:Dictionary=FullProduct.read(sample.path,directory,"",-1)
	check(observed.get("known",false) and observed.get("native_metadata_hit",false),"full native product supplies source-free bounds metadata")
	check(observed.get("local_bounds")==sample.expected.local_bounds,"full native bounds match original exact geometry")
	var candidate:Dictionary=observed.get("native_candidate",{})
	check(int(candidate.get("estimated_bytes",0))==sample.footprint_bytes and int(candidate.get("resident_bytes",0))==sample.footprint_bytes,"full product retains its own budget and does not borrow a white footprint")
	check(observed.get("native_source_sha")==sample.sha and observed.get("native_product_path")==sample.product,"full native metadata binds source and actual published product")

func has_textured_material(scene:Node)->bool:
	for item:Node in scene.find_children("*","MeshInstance3D",true,false):
		var node:=item as MeshInstance3D
		if node==null or node.mesh==null:continue
		for i:int in node.mesh.get_surface_count():
			var material:Material=node.get_active_material(i)
			if material is BaseMaterial3D and material.albedo_texture!=null and material.albedo_texture.get_width()==2 and material.albedo_texture.get_height()==2:return true
	return false

func check_full_runtime(sample:Dictionary)->void:
	Library.evict_cached_scene(sample.path)
	var first:=Library.instantiate(sample.path,true);var second:=Library.instantiate(sample.path,true)
	check(first!=null and second!=null,"full native cold AssetLibrary load and cached reuse work without source")
	if first!=null and second!=null:
		var meshes_a:=first.find_children("*","MeshInstance3D",true,false);var meshes_b:=second.find_children("*","MeshInstance3D",true,false)
		check(meshes_a.size()==1 and meshes_b.size()==1 and meshes_a[0].mesh==meshes_b[0].mesh,"full product repeated instances share the same mesh owner")
		check(has_textured_material(first) and has_textured_material(second),"cold and reused instances retain the real embedded material and image")
	if first!=null:Drainer.dispose_scene(first)
	if second!=null:Drainer.dispose_scene(second)
	var preview:=Library.instantiate_preview(sample.path,true)
	check(preview!=null and has_textured_material(preview),"full native preview accepts its cached template and retains texture")
	if preview!=null:Drainer.dispose_scene(preview)
	Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()
	preview=Library.instantiate_preview(sample.path,true)
	check(preview!=null and has_textured_material(preview),"full native preview cold read retains the actual texture")
	if preview!=null:Drainer.dispose_scene(preview)
	var prepared:Dictionary=await worker_result(Deferred.prepare_scene.bind(sample.path,"",null,sample.observation,true,directory,false,Deferred.CollisionGeometry.ALL,true,true,true))
	var ok:bool=str(prepared.get("error","unknown")).is_empty() and prepared.get("compiled",false) and (prepared.has("packed") or prepared.has("scene"))
	check(ok,"deferred cold return uses the full product without GLB")
	if not ok:print("FULL_DEFERRED_ERROR ",prepared.get("error","")," keys=",prepared.keys())
	var weak:WeakRef=weakref(prepared.resource_owners.packed) if prepared.has("resource_owners") and prepared.resource_owners.packed is Resource else null
	if ok:
		# Match the real deferred publication: full products currently return a
		# captured scene, while white products can return a direct template.
		var cached:bool
		if prepared.has("packed"):
			cached=Library.cache_packed(sample.path,prepared.packed,sample.sha)
			if cached and prepared.has("resource_owners"):prepared.resource_owners.transfer_template(prepared.packed)
		else:
			cached=Library.cache_scene(sample.path,prepared.scene,sample.sha)
			prepared.erase("scene") # cache_scene consumes/frees this node.
		check(cached,"full deferred result transfers into the shared library")
		if cached:
			var published:PackedScene=Library._scenes.get(sample.path)
			var reused:=Library.instantiate(sample.path,true)
			check(reused!=null and has_textured_material(reused),"returned full native template is reusable with its material")
			check(Library._scenes.get(sample.path)==published,"full deferred accepted template is actually reused, without a second native read")
			published=null
			if reused!=null:Drainer.dispose_scene(reused)
	var preflight:=Deferred._preflight_reused_source(sample.path,sample.sha,directory,null,true)
	var verification:=Deferred._verify_reused_source(sample.path,sample.sha,directory,null,true)
	check(preflight.error.is_empty() and verification.error.is_empty(),"full native deferred template preflight and reuse verification succeed without source")
	Drainer.dispose_result(prepared);Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()
	check(prepared.is_empty() and (weak==null or weak.get_ref()==null),"deferred result and cached owners release after eviction")

func check_full_preparation_without_injected_estimates()->void:
	var controller:=Preparation.new();controller.require_native_products=true;controller.prepare_static_scenes=true
	# No injected parser, estimator, cache reader, candidate provider, metadata
	# table or verified-source map. One duplicate tests the real dedupe path.
	var paths:Array=[samples[0].path,samples[1].path,samples[0].path]
	var prepared:Dictionary=await worker_result(controller.run.bind(paths,Callable(),2,Callable(),directory,{}))
	check(prepared.get("error",FAILED)==OK and prepared.get("unique_count",0)==2 and prepared.get("native_cache_hits",0)==2,"initial ModelParse performs two native jobs for three records without injected estimator")
	var stages:Dictionary=prepared.get("admission_profile",{}).get("stages",{})
	check(not stages.has("raw_import") and prepared.get("native_cache_misses",-1)==0,"initial ModelParse schedules no raw fallback")
	var budget_ok:=true
	for sample:Dictionary in samples:
		var task:Dictionary=prepared.get("admission_profile",{}).get("tasks",{}).get(sample.path,{})
		budget_ok=budget_ok and int(task.get("memory",{}).get("compiled_read_reservation_bytes",0))==sample.footprint_bytes
	check(budget_ok,"initial ModelParse charges full material footprint for each unique native job")
	check(prepared.get("inflight_jobs_at_return",-1)==0 and prepared.get("inflight_reserved_at_return",-1)==0,"initial coordinator joins all tasks and returns no inflight admission")
	Drainer.dispose_result(prepared);Drainer.synchronize_transfer()
	check(prepared.is_empty(),"initial result packet is released by the coordinator owner")

func check_full_far_registration()->void:
	var sample:Dictionary=samples[0]
	var observation:Dictionary=sample.observation
	var original:Dictionary=observation.get("memory",{})
	check(original.get("native_product_kind")=="full","new full footprint identifies its own budget kind")
	for kind:String in ["full","white","unknown"]:
		var loader:=CountingReferenceLoader.new()
		loader._content_root=directory;loader._model_preparation.require_native_products=true
		var stored:Dictionary={"file_length":observation.get("file_length"),"memory":original.duplicate(true)}
		if kind=="white":
			stored.memory.native_product_kind="white";stored.memory.estimated_bytes=123
		if kind=="unknown":
			stored.memory.native_product_kind="full";stored.memory.source_bytes=-1
		loader._dependency_index={"models":{sample.path:stored}}
		var entries:Array=[]
		for i:int in 2:
			entries.append({"asset_path":sample.path,"record_index":i,"compact_record":{"uuid":"far_%d"%i},"bounds":AABB(Vector3(500+i*10,0,0),Vector3.ONE),"group_id":"","memory_bytes":65536})
		loader._register_reference_pending(entries)
		var expected_reads:=0 if kind=="full" else 1
		var safe:bool=loader._error==OK and loader._deferred_assets.size()==2 and loader.metadata_reads==expected_reads
		for pending:Dictionary in loader._deferred_assets:
			safe=safe and int(pending.memory.get("estimated_bytes",0))==sample.footprint_bytes and pending.memory.get("native_product_kind")=="full"
		check(safe,"far full registration uses warm budget or one real helper for "+kind+" metadata; no duplicate product read")
		loader.free()

func check_full_target_prefetch()->void:
	var source:=directory.path_join("prefetch_map.gltf");save_bytes(source,"private prefetch map".to_utf8_buffer());created.append(source)
	var sample:Dictionary=samples[0]
	var records:Array=[{"uuid":"one","kind":"asset","asset_path":sample.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}]
	var another:Dictionary=records[0].duplicate(true);another.uuid="two";records.append(another)
	var plan:Dictionary=TargetPrefetch.plan(records,directory,source,FileAccess.get_sha256(source),{})
	check(not plan.is_empty(),"target prefetch plans a full native model with no source GLB")
	if plan.is_empty():return
	var files:Dictionary=plan.files
	check(int(plan.estimated_bytes)==512*1024*1024+sample.footprint_bytes*2,"target prefetch counts one full-material budget for repeated model instances")
	var item:Variant=files.get(sample.product)
	check(not files.has(sample.path) and files.has(FullCompiled.index_path(sample.path,directory)) and files.has(sample.descriptor) and item is Dictionary and item.get("native_product",false) and item.get("sha256")==sample.index.payload_sha and int(item.get("length",0))==int(sample.index.bytes),"target prefetch tracks full index, footprint and actual native product, not GLB")
	check(TargetPrefetch.verify(files,directory),"target prefetch verifies source-free full native identity")
	if not item is Dictionary:return
	var wrong:=files.duplicate(true);wrong[sample.product].length+=1
	check(not TargetPrefetch.verify(wrong,directory),"target prefetch rejects an incorrect full product length")
	var outside:=directory.path_join("outside_native_folder.scn");save_bytes(outside,FileAccess.get_file_as_bytes(sample.product));created.append(outside)
	wrong=files.duplicate(true);wrong[outside]=wrong[sample.product];wrong.erase(sample.product)
	check(not TargetPrefetch.verify(wrong,directory),"target prefetch rejects native identity outside its product directory")

func check_full_kits()->void:
	var fortification:=Fortification.new()
	for kind:String in ["bridge","fortification"]:
		var names:Array=["arch","pier","abutment","deck","parapet","post"] if kind=="bridge" else Fortification.MODULES.duplicate()
		var sample:=make_sample(directory.path_join("full_"+kind+"_modules.glb"),kit_source_data(names))
		if sample.is_empty():continue
		var path:String=sample.path
		Bridge.kits.erase(path);Fortification.kits.erase(path);Library.evict_cached_scene(path)
		var preview:=Library.instantiate_preview(path,true)
		check(preview!=null and has_textured_material(preview),kind+" native preview decodes its actual embedded material with no source")
		if preview!=null:Drainer.dispose_scene(preview)
		var pieces:Dictionary=Bridge.kit(path,true) if kind=="bridge" else fortification.kit(path,true)
		check(check_kit_geometry(pieces,names),kind+" native kit has every named module and transform")
		var materials_ok:=not pieces.is_empty()
		for name_ in pieces:
			var mesh:Mesh=pieces[name_].mesh
			var material:Material=mesh.surface_get_material(0)
			materials_ok=materials_ok and material is BaseMaterial3D and material.albedo_texture!=null
		check(materials_ok,kind+" native kit preserves material/texture references")
		var again:Dictionary=Bridge.kit(path,true) if kind=="bridge" else fortification.kit(path,true)
		var shared:=not pieces.is_empty() and again.size()==pieces.size()
		for name_ in pieces:shared=shared and again.get(name_,{}).get("mesh")==pieces[name_].mesh
		check(shared,kind+" repeated kit calls reuse the actual mesh owner")
		if kind=="fortification":check_document_fortification_identity(sample)
		Bridge.kits.erase(path);Fortification.kits.erase(path);Library.evict_cached_scene(path)
		pieces.clear();again.clear()
	Drainer.synchronize_transfer()

func check_document_fortification_identity(sample:Dictionary)->void:
	var document:=preload("res://scripts/world3d/world_document.gd").new()
	document.load_require_native_products=true;document.load_box_meshes={};document.load_model_signatures={}
	var art:Dictionary={"asset_path":sample.path,"module":"wall"}
	var record:Dictionary={"uuid":"fortification_identity","kind":"box","size":[4,2,1],"position":[0,0,0],"rotation":[0,0,0],"fortification_art":art,"fortification_materials":{},"surface_paint":[]}
	# Seed the actual fortification mesh cache to keep this assertion focused on
	# the production signature/key branch; kit geometry is tested separately.
	var key:Array=["fortification",record.size,{},[],{},record.fortification_art,record.fortification_materials,record.surface_paint,sample.sha]
	var sentinel:=BoxMesh.new();document.load_box_meshes[key]={"mesh":sentinel,"source":sentinel}
	var visual:MeshInstance3D=document._mesh(record,true)
	check(document.load_model_signatures.get(sample.path)==sample.sha and document.load_box_hits==1 and visual.mesh==sentinel,"world document fortification uses native source SHA in its existing cache key")
	Drainer.dispose_scene(visual);document.load_box_meshes.clear();Fortification.cache.clear()

func check_full_missing(sample:Dictionary)->void:
	Library.evict_cached_scene(sample.path);Drainer.synchronize_transfer()
	var payload:=FileAccess.get_file_as_bytes(sample.product)
	DirAccess.remove_absolute(sample.product)
	check(FullProduct.read(sample.path,directory,"",-1).is_empty(),"missing full native product cannot authorize model metadata")
	check(Library.instantiate(sample.path,true)==null,"missing full native product fails cold library load without GLB fallback")
	var controller:=Preparation.new();controller.require_native_products=true;controller.prepare_static_scenes=true
	var rejected:Dictionary=await worker_result(controller.run.bind([sample.path],Callable(),1,Callable(),directory,{}))
	check(rejected.get("error",OK)!=OK and not rejected.get("admission_profile",{}).get("stages",{}).has("raw_import"),"missing full product fails initial model preparation without raw fallback")
	Drainer.dispose_result(rejected)
	var deferred:Dictionary=await worker_result(Deferred.prepare_scene.bind(sample.path,"",null,sample.observation,true,directory,false,Deferred.CollisionGeometry.ALL,true,true,true))
	check(not str(deferred.get("error","")).is_empty() or not deferred.get("compiled",false),"missing full product fails deferred preparation without raw fallback")
	Drainer.dispose_result(deferred)
	var map:=directory.path_join("missing_prefetch.gltf");save_bytes(map,"missing product test".to_utf8_buffer());created.append(map)
	var records:Array=[{"uuid":"missing","kind":"asset","asset_path":sample.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}]
	check(TargetPrefetch.plan(records,directory,map,FileAccess.get_sha256(map),{}).is_empty(),"missing full native product rejects target prefetch")
	save_bytes(sample.product,payload)
	var descriptor:=FileAccess.get_file_as_bytes(sample.descriptor);DirAccess.remove_absolute(sample.descriptor)
	check(FullProduct.read(sample.path,directory,"",-1).is_empty(),"missing full footprint cannot authorize source-free metadata")
	save_bytes(sample.descriptor,descriptor);Drainer.synchronize_transfer()
