extends SceneTree
## CPU-only exact sidecar envelope/proof checks. No author map or GPU resource.
const Cache=preload("res://scripts/world3d/collision_product_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
const Base=preload("res://tools/test_prefab_texture_preparation.gd")
const Chunk=preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var passed:=0
var failed:=0
var folder:=""
var created:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func worker(callable:Callable)->Dictionary:
	var thread:=Thread.new();var error:int=thread.start(callable)
	if error!=OK:return {"ok":false,"reason":"test_thread"}
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()
func run()->void:
	var errors:=Errors.new();OS.add_logger(errors)
	folder=Paths.cache_directory("collision_product_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var source:=folder.path_join("source.rmres");created.append(source)
	var file:=FileAccess.open(source,FileAccess.WRITE);file.store_buffer(PackedByteArray([0,1,2,3,4,5,6,7]));file.close()
	var sources:Dictionary={source:FileAccess.get_sha256(source)}
	var identity:=Cache.identity(sources,"frozen/source/1",folder)
	check(not identity.is_empty() and Cache.identity({source:"bad"},"frozen/source/1",folder).is_empty(),"identity requires complete source SHA and explicit collision selector")
	check(Cache.identity(sources,"",folder).is_empty() and Cache.identity({"C:/outside.rmres":"a".repeat(64)},"x",folder).is_empty(),"empty selectors and paths outside the source root are rejected")
	var faces:=PackedVector3Array([Vector3(0,0,0),Vector3(0,0,1),Vector3(1,0,0),Vector3(2,0,0),Vector3(2,0,1),Vector3(3,0,0)])
	var candidate:=Cache.make_candidate(identity,faces)
	check(candidate.ok and candidate.source_unverified and Cache._seal_after_reference_validation(candidate,{})==null,"an unverified disk/CPU dictionary never becomes a physics product without matching final source proof")
	var product:=Cache._seal_after_reference_validation(candidate,sources)
	check(product!=null and product.faces()==faces and product.kind()=="faces","sealed product preserves the exact local faces and gap")
	check(Cache.store_validated(product,folder,Cache.WORKSPACE_BYTES).reason=="worker_or_proof","cache writes cannot run on the scene thread")
	var missing:=await worker(Cache.read_candidate.bind(identity,folder))
	check(not missing.ok and missing.reason=="absent","missing cache remains an ordinary fallback")
	var denied:=await worker(Cache.store_validated.bind(product,folder,Cache.WORKSPACE_BYTES-1))
	check(not denied.ok and denied.reason=="workspace_not_admitted","cold serialization requires its separate complete workspace lease")
	var written:=await worker(Cache.store_validated.bind(product,folder,Cache.WORKSPACE_BYTES));var path:=Cache.path_for(identity,folder);created.append(path);created.append(path+".previous")
	check(written.ok and FileAccess.file_exists(path),"bounded worker product publishes atomically in the derived directory")
	var restored:=await worker(Cache.read_candidate.bind(identity,folder))
	check(restored.ok and restored.source_unverified and restored.faces==faces,"roundtrip retains exact float bytes without turning payload validity into a source proof")
	check(Cache._seal_after_reference_validation(restored,{source:"b".repeat(64)})==null,"same-path replacement rejects the old product identity")
	var other:=Cache.identity(sources,"frozen/render/0",folder)
	check(Cache.path_for(other,folder)!=path,"painted/render source selector cannot alias the solid product")
	var box_id:=Cache.identity(sources,"primitive/box",folder);var box:=Vector3(2,3,4)
	var box_product:=Cache._seal_after_reference_validation(Cache.make_candidate(box_id,PackedVector3Array(),box),sources)
	var box_written:=await worker(Cache.store_validated.bind(box_product,folder,Cache.WORKSPACE_BYTES))
	var box_read:=await worker(Cache.read_candidate.bind(box_id,folder));created.append(Cache.path_for(box_id,folder));created.append(Cache.path_for(box_id,folder)+".previous")
	check(box_written.ok and box_read.ok and box_read.kind=="box" and box_read.faces.is_empty() and box_read.box==box,"box primitive remains a primitive descriptor, never an approximate triangle replacement")
	var bytes:=FileAccess.get_file_as_bytes(path)
	file=FileAccess.open(path,FileAccess.WRITE);var corrupt:=bytes.duplicate();corrupt[corrupt.size()-1]^=1;file.store_buffer(corrupt);file.close()
	var broken:=await worker(Cache.read_candidate.bind(identity,folder));check(not broken.ok and broken.reason=="checksum","payload corruption is isolated as a cache miss")
	corrupt=bytes.duplicate();corrupt.encode_u64(16,Cache.MAX_OUTPUT_BYTES+1)
	file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(corrupt);file.close()
	broken=await worker(Cache.read_candidate.bind(identity,folder));check(not broken.ok and broken.reason=="declared_length","forged raw length is rejected before payload allocation")
	var token:=Drainer.CancelToken.new();token.cancel()
	broken=await worker(Cache.store_validated.bind(product,folder,Cache.WORKSPACE_BYTES,token));check(not broken.ok and broken.reason=="identity_or_cancel","cancelled output cannot publish a new product")
	check(not Cache.make_candidate(identity,PackedVector3Array([Vector3(INF,0,0),Vector3.ZERO,Vector3.ONE])).ok,"non-finite collision geometry never enters a cache product")
	await reference_test()
	for item:String in created:
		if FileAccess.file_exists(item):DirAccess.remove_absolute(item)
	for directory:String in [Cache.directory(folder),folder.path_join("cache/world3d"),folder.path_join("cache"),folder]:DirAccess.remove_absolute(directory)
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script/engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_PRODUCT_CACHE passed=",passed," failures=",failed);quit(0 if failed==0 else 1)

func reference_test()->void:
	var fixture:=Base.new();fixture.files=Base.Files.new();fixture.files.content_root=Paths.external_root();fixture.files.folder=Paths.cache_directory("collision_reference_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(fixture.files.folder)
	var record:Dictionary=fixture.bridge("product_bridge",100,{"name":"stone","color":[.7,.7,.7,1],"roughness":.9})
	var source:Dictionary=fixture.files.fixture("product",[record],Base.Fixture.metadata([record]))
	check(Index.build(source.path,fixture.files.content_root,[record]).ok,"private frozen reference index builds")
	var index:=Index.read(source.path,fixture.files.content_root);var requests:Array=Index.select(index,[]).deferred_entries
	var ordinary:=await worker(Chunk.prepare.bind(index,requests,source.path,fixture.files.content_root))
	var prepared:=await worker(Chunk.prepare.bind(index,requests,source.path,fixture.files.content_root,null,null,{}, {},Cache.WORKSPACE_BYTES))
	var key:String=record.house_prefab.sha256;var decoded:=Prefab.decode(record.house_prefab);var slot:int=decoded.entries[0][1][1]
	check(prepared.error.is_empty() and prepared.read_profile.collision_products.writes==1,"cold exact product builds inside the ordinary verified reference transaction")
	var product:Cache.Product=prepared.prefab_cpu[key].collision_products[slot]
	check(product.faces()==ordinary.prefab_cpu[key].collision_faces[slot] and product.identity().selector.ends_with("/source:"+str(slot)),"handoff selects the original collision solid and exactly matches the old extraction")
	var warm:=await worker(Chunk.prepare.bind(index,requests,source.path,fixture.files.content_root,null,null,{}, {},Cache.WORKSPACE_BYTES))
	check(warm.error.is_empty() and warm.read_profile.collision_products.hits==1 and warm.read_profile.collision_products.writes==0 and warm.prefab_cpu[key].collision_faces[slot]==product.faces(),"warm reference consumes the exact product without recooking or rewriting")
	var unfunded:=await worker(Chunk.prepare.bind(index,requests,source.path,fixture.files.content_root,null,null,{}, {},Cache.WORKSPACE_BYTES-1))
	check(unfunded.error.is_empty() and unfunded.read_profile.collision_products.hits==0 and not unfunded.prefab_cpu[key].has("collision_products"),"unfunded optional product work takes the original bounded path")
	var queue:=Deferred.new();queue.configure_references(index,source.path,fixture.files.content_root);Cache.enabled=true
	var estimate:=queue._estimate_job({"path":"reference:product","native_reference":true},requests)
	check(estimate.collision_workspace_bytes==Cache.WORKSPACE_BYTES,"dispatch explicitly charges the cold/read collision workspace")
	queue.free();Cache.enabled=false
	var compact:Dictionary=index.extras.rmmo_records[0];var resource_path:String=Chunk.Store._location(compact.rmmo_ref.uri,compact.rmmo_ref.sha256,source.path,fixture.files.content_root)
	var saved:=FileAccess.get_file_as_bytes(resource_path)
	var file:=FileAccess.open(resource_path,FileAccess.WRITE);file.store_buffer(saved+PackedByteArray([42]));file.close()
	var changed:=await worker(Chunk.prepare.bind(index,requests,source.path,fixture.files.content_root,null,null,{}, {},Cache.WORKSPACE_BYTES))
	check(not changed.error.is_empty() and not changed.has("prefab_cpu"),"a changed native source cannot publish even when an older collision product exists")
	file=FileAccess.open(resource_path,FileAccess.WRITE);file.store_buffer(saved);file.close()
	var product_path:=Cache.path_for(product.identity(),fixture.files.content_root)
	if FileAccess.file_exists(product_path):DirAccess.remove_absolute(product_path)
	for path:String in fixture.files.created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(fixture.files.folder)
	fixture.files.free();fixture.free()
