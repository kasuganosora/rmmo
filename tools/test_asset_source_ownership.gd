extends SceneTree
## Small headless source/version and actual native-miss ownership regressions.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var checks:=0
var failed:=0
var products:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failed+=1
	print("PASS " if value else "FAIL ",label)
func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func glb(path:String,label:String,material_extension:bool=false,required:bool=false)->void:
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":label}],"buffers":[{"byteLength":4}]}
	if material_extension:
		data.extensionsUsed=["KHR_materials_unlit"]
		if required:data.extensionsRequired=["KHR_materials_unlit"]
		data.materials=[{"extensions":{"KHR_materials_unlit":{}}}]
	var bytes:=JSON.stringify(data).to_utf8_buffer()
	while bytes.size()%4:bytes.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(32+bytes.size())
	file.store_32(bytes.size());file.store_32(0x4e4f534a);file.store_buffer(bytes)
	file.store_32(4);file.store_32(0x004e4942);file.store_32(0);file.close()
func native_product(path:String,valid:bool)->Dictionary:
	var node:Node=Node3D.new() if valid else Node2D.new()
	node.name="NativeOwner_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var packed:=PackedScene.new();check(packed.pack(node)==OK,"pack isolated native fixture");node.free()
	DirAccess.make_dir_recursive_absolute(Compiled.directory())
	var staging:=Compiled.directory().path_join("ownership_%d_%d.scn"%[OS.get_process_id(),Time.get_ticks_usec()])
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save isolated native fixture")
	packed=null
	var digest:=FileAccess.get_sha256(staging)
	var target:=Compiled.directory().path_join(digest+".scn")
	if FileAccess.file_exists(target):DirAccess.remove_absolute(staging)
	else:
		check(DirAccess.rename_absolute(staging,target)==OK,"publish isolated native fixture")
		products.append(target)
	var file:=FileAccess.open(target,FileAccess.READ);var size:=file.get_length();file.close()
	var manifest:={"version":Compiled.VERSION,"source_sha":FileAccess.get_sha256(path),"payload_sha":digest,"generator":Compiled.generator(),"bytes":size}
	write(Compiled.index_path(path),JSON.stringify(manifest).to_utf8_buffer())
	return {"manifest":manifest,"product":target}
func dispose(node:Node)->void:
	if node!=null:Drainer.dispose_scene(node)

func run()->void:
	var folder:=Paths.cache_directory("asset_source_ownership_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var source:=folder.path_join("model.glb")
	glb(source,"VersionA")
	var source_a:=FileAccess.get_file_as_bytes(source)
	var enabled:=Compiled.enabled;Compiled.enabled=false
	var first:=Library.instantiate(source)
	check(first!=null and first.find_child("VersionA",true,false)!=null,"synchronous raw path loads original source")
	check(Library.has_cached_scene(source,FileAccess.get_sha256(source)),"raw cache carries complete source digest")
	var packed:PackedScene=Library._scenes.get(source)
	var preview:=Library.instantiate_preview(source)
	check(preview!=null and Library._scenes.get(source)==packed,"same-source preview preserves existing template")
	dispose(preview)
	glb(source,"VersionB")
	preview=Library.instantiate_preview(source)
	check(preview!=null and preview.find_child("VersionB",true,false)!=null,"preview rejects stale template after same-path source replacement")
	check(not Library._scenes.has(source),"stale preview evicts only template and does not cache temporary preview")
	check(first!=null and first.find_child("VersionA",true,false)!=null,"existing consumer retains its original instance")
	dispose(preview);dispose(first);packed=null
	var unversioned:=Node3D.new();unversioned.name="Unversioned"
	check(Library.cache_scene(source,unversioned),"legacy unversioned template fixture")
	preview=Library.instantiate_preview(source)
	check(preview!=null and preview.find_child("VersionB",true,false)!=null and not Library._scenes.has(source),"preview never borrows a template without source version")
	dispose(preview)
	var rejected:=Node3D.new();var rejected_id:=rejected.get_instance_id()
	check(not Library.cache_scene(source,rejected,"invalid"),"invalid version rejects cache publication")
	check(not is_instance_id_valid(rejected_id) and not Library._scenes.has(source),"rejected private scene is retired without publishing")
	write(source,source_a);Compiled.enabled=true
	var product:=native_product(source,true)
	var identity:=Library._verified_compiled_identity(source)
	check(not identity.is_empty(),"memo identity requires real source and product hashes")
	Library._compiled_imports[source]=identity
	var reused:=Library._compile_import(source)
	check(reused.ok and reused.reused,"verified memo reuses native product without a graphics build")
	var product_bytes:=FileAccess.get_file_as_bytes(product.product)
	var corrupt:=product_bytes.duplicate();corrupt[corrupt.size()-1]^=1;write(product.product,corrupt)
	check(Library._verified_compiled_identity(source).is_empty(),"same-length native corruption invalidates complete product identity")
	var invalid:=Library._compile_import(source)
	check(not invalid.ok and not Library._compiled_imports.has(source),"corrupt product cannot inherit session success")
	write(product.product,product_bytes)
	Library._compiled_imports[source]=identity
	glb(source,"VersionB")
	invalid=Library._compile_import(source)
	check(not invalid.ok and not Library._compiled_imports.has(source),"same-path source replacement invalidates import memo")
	write(source,source_a)
	Library._compiled_imports[source]=identity
	var changed:Dictionary=product.manifest.duplicate();changed.generator="0".repeat(64)
	write(Compiled.index_path(source),JSON.stringify(changed).to_utf8_buffer())
	invalid=Library._compile_import(source)
	check(not invalid.ok and not Library._compiled_imports.has(source),"generator replacement invalidates import memo")
	write(Compiled.index_path(source),JSON.stringify(product.manifest).to_utf8_buffer())
	Library._compiled_imports[source]=true
	invalid=Library._compile_import(source)
	check(not invalid.ok and not Library._compiled_imports.has(source),"old unbound Boolean memo is not proof")
	var prepared:=Compiled.prepare_source(source)
	Library._compiled_imports[source]=identity
	glb(source,"VersionB")
	invalid=Library._compile_import(source,prepared)
	check(not invalid.ok and invalid.reason=="source_changed" and prepared.disposed,"prepared owner source change fails before memo reuse and disposes state")
	write(source,source_a);Library._compiled_imports.erase(source)
	product=native_product(source,false)
	var worker:=Thread.new()
	check(worker.start(Preparation.parse_gltf.bind(source,Paths.external_root()))==OK,"real legacy reader runs on worker")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish()
	check(packet.error==ERR_INVALID_DATA and packet.cache_reason=="invalid_product" and packet.has("retained_resources"),"real invalid native schema returns owned failure instead of worker raw fallback")
	var resource:WeakRef=weakref(packet.retained_resources[0].retained_resources[0])
	check(resource.get_ref()!=null,"failed native allocation remains alive after worker join")
	Drainer.dispose_result(packet)
	check(packet.is_empty() and resource.get_ref()==null,"main retirement clears all aliases and releases actual failed allocation")
	var raw:=Preparation.parse_gltf(source,Paths.external_root())
	check(raw.error==OK and not raw.compiled and raw.source_digest==FileAccess.get_sha256(source),"main legacy miss retires invalid native then returns source-bound raw fallback")
	Drainer.dispose_result(raw)
	glb(source,"OptionalMaterialExtension",true)
	check(preload("res://scripts/world3d/embedded_glb.gd").can_copy(source),"supported optional material extension follows current raw-copy eligibility")
	# Required extensions deliberately retain the conservative packing route.
	# Use that real rejected contract to exercise native-proof authorization.
	glb(source,"NativeMaterialExtension",true,true)
	product=native_product(source,true)
	var native:=Compiled.read(source)
	check(native.hit and not preload("res://scripts/world3d/embedded_glb.gd").can_copy(source),"real verified native read accepts fixture whose material extension fails raw copy eligibility")
	if native.hit:
		packed=native.packed
		Library.cache_packed(source,packed,native.source_digest)
		preview=Library.instantiate_preview(source)
		check(preview!=null and Library._scenes.get(source)==packed and preview.get_meta("_compiled_resource_owner",null)==packed,"matching source and strict native proof preserve exact preview template with material extension")
		dispose(preview)
		packed.set_meta("compiled_asset_validated",1)
		preview=Library.instantiate_preview(source)
		check(preview!=null and not Library._scenes.has(source),"integer native marker cannot authorize extension-bearing template reuse")
		dispose(preview)
		packed.set_meta("compiled_asset_validated",true)
		Library.cache_packed(source,packed,native.source_digest)
		glb(source,"ChangedMaterialExtension",true,true)
		preview=Library.instantiate_preview(source)
		check(preview!=null and not Library._scenes.has(source) and preview.find_child("ChangedMaterialExtension",true,false)!=null,"native closure proof cannot bypass matching complete source SHA")
		dispose(preview);packed=null
	Drainer.dispose_result(native)
	Compiled.enabled=enabled;Library.evict_cached_scene(source);Library._compiled_imports.erase(source)
	DirAccess.remove_absolute(Compiled.index_path(source))
	for product_path:String in products:DirAccess.remove_absolute(product_path)
	DirAccess.remove_absolute(source);DirAccess.remove_absolute(folder)
	print("ASSET_SOURCE_OWNERSHIP checks=%d failures=%d"%[checks,failed])
	quit(0 if failed==0 else 1)
