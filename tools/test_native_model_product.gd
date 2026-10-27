extends "res://tools/test_asset_bounds_manifest.gd"
const Product=preload("res://scripts/world3d/native_model_product.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")

func run()->void:
	var folder:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-root="):folder=arg.trim_prefix("--test-root=")
	var base:="D:/code/rmmo_runtime/review_artifacts"
	if folder.is_empty() or not folder.is_absolute_path() or not Paths.allowed(folder,base) or folder==base:
		check(false,"explicit private test root required");quit(1);return
	DirAccess.make_dir_recursive_absolute(folder)
	var source:=folder.path_join("source.glb");write(source,data())
	var expected:=Manifest.read(source);var source_sha:=FileAccess.get_sha256(source)
	var native_dir:=Compiled.directory(folder);DirAccess.make_dir_recursive_absolute(native_dir)
	# A stand-in file is sufficient for metadata; native decoding is tested elsewhere.
	var payload:=PackedByteArray([1,2,3,4]);var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(payload);var payload_sha:=ctx.finish().hex_encode()
	var product:=native_dir.path_join(payload_sha+".scn");FileAccess.open(product,FileAccess.WRITE).store_buffer(payload)
	var identity:={"source_path":source,"source_sha":source_sha,"payload_sha":payload_sha,"generator":Compiled.generator(),"bytes":payload.size(),"source_bytes":expected.file_length}
	var index:={"version":Compiled.VERSION,"source_sha":source_sha,"payload_sha":payload_sha,"generator":identity.generator,"bytes":payload.size()}
	FileAccess.open(Compiled.index_path(source,folder),FileAccess.WRITE).store_string(JSON.stringify(index))
	var stats:=Footprint.empty_stats();stats.nodes=2;stats.native_uncompressed_bytes=4096
	var estimate:=Footprint.estimate_stats(stats);var descriptor:=identity.duplicate()
	descriptor.merge({"version":Footprint.VERSION,"footprint_generator":Footprint.generator(),"stats":stats,"estimated_bytes":estimate.estimated_bytes,"resident_bytes":estimate.resident_bytes})
	var descriptor_path:=Footprint.descriptor_path(source,folder);var index_path:=Compiled.index_path(source,folder)
	check(Footprint._publish(descriptor,descriptor_path,folder)==OK,"publish pre-existing full native footprint without metadata")
	check(Product.read(source,folder).is_empty(),"old footprint requires explicit offline metadata refresh")
	var refreshed:=Footprint.refresh_bounds(source,folder)
	check(refreshed.get("ok",false),"offline refresh adds bounds without native model regeneration")
	check(FileAccess.get_sha256(source)==source_sha and FileAccess.get_sha256(product)==payload_sha,"offline refresh leaves source and native product bytes unchanged")
	check(DirAccess.rename_absolute(source,source+".held")==OK,"hide authoring source")
	var identities:Dictionary={};var timing:Dictionary={}
	var value:=Product.read(source,folder,"",-1,timing,identities)
	check(not value.is_empty(),"full native metadata available when source GLB is absent")
	if not value.is_empty():
		check(value.get("local_bounds")==expected.local_bounds and value.get("world_bounds")==expected.local_bounds and value.get("json_sha256")==expected.json_sha256,"full bounds and JSON identity from descriptor")
		var memory:Dictionary=value.get("memory",{})
		check(memory.get("estimated_bytes")==estimate.estimated_bytes and memory.get("resident_bytes")==estimate.resident_bytes and memory.get("exclusive")==estimate.exclusive and memory.get("source_bytes")==expected.file_length,"full footprint supplies native budget and offline source length")
		check(value.get("native_source_sha")==source_sha and value.get("native_payload_sha")==payload_sha and value.get("native_product_path")==product and value.get("native_index_path")==index_path and value.get("native_descriptor_path")==descriptor_path,"published metadata binds the exact product, index and descriptor")
		check(value.get("native_candidate",{}).get("estimated_bytes")==estimate.estimated_bytes and value.native_candidate.get("payload_sha")==payload_sha,"full candidate is reusable without a second descriptor read")
		check(identities.get(index_path)==FileAccess.get_sha256(index_path) and identities.get(descriptor_path)==FileAccess.get_sha256(descriptor_path),"optional prefetch identities hash exactly the bytes read")
		var record:={"position":[1,2,3],"rotation":[0,90,0],"size":[1,2,3]}
		var actual_placed:=Manifest.apply_record(value,record);var expected_placed:=Manifest.apply_record(expected,record)
		check(actual_placed.get("known",false) and actual_placed.world_bounds.is_equal_approx(expected_placed.world_bounds),"published local bounds preserve transformed record bounds")
	check(Product.read(source,folder,"f".repeat(64)).is_empty() and Product.read(source,folder,source_sha,expected.file_length+1).is_empty(),"caller identity or source length mismatch fails")
	check(Footprint.candidate(source,folder,source_sha,false).is_empty(),"strict audit still observes the missing source")
	var original_descriptor:=FileAccess.get_file_as_bytes(descriptor_path)
	var original_index:=FileAccess.get_file_as_bytes(index_path)
	index.payload_sha="f".repeat(64);FileAccess.open(index_path,FileAccess.WRITE).store_string(JSON.stringify(index))
	check(Product.read(source,folder).is_empty(),"missing indexed product cannot inherit old metadata")
	FileAccess.open(index_path,FileAccess.WRITE).store_buffer(original_index)
	var envelope:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor_path));var body:Dictionary=JSON.parse_string(envelope.body)
	body.model_metadata.version=2;envelope.body=JSON.stringify(body);envelope.sha256=envelope.body.sha256_text()
	FileAccess.open(descriptor_path,FileAccess.WRITE).store_string(JSON.stringify(envelope))
	check(Product.read(source,folder).is_empty(),"unsupported bounds metadata version fails")
	FileAccess.open(descriptor_path,FileAccess.WRITE).store_buffer(original_descriptor)
	DirAccess.rename_absolute(product,product+".held")
	check(Product.read(source,folder).is_empty(),"missing native product fails")
	DirAccess.rename_absolute(product+".held",product)
	check(DirAccess.rename_absolute(source+".held",source)==OK,"restore source for independent white fixture export")
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	var white=preload("res://scripts/world3d/white_native_asset_metadata.gd")
	var previous_native:bool=controls.native_geometry_only;controls.native_geometry_only=true
	var white_dir:String=white.Writer.directory(folder);DirAccess.make_dir_recursive_absolute(white_dir)
	var white_product:String=white_dir.path_join(payload_sha+".scn");FileAccess.open(white_product,FileAccess.WRITE).store_buffer(payload)
	var white_index:={"generator":white.Writer.generator(),"source_sha":source_sha,"payload_sha":payload_sha,"bytes":payload.size()}
	FileAccess.open(white.Writer.index_path(source,folder),FileAccess.WRITE).store_string(JSON.stringify(white_index))
	var built:Dictionary=white.build(source,folder)
	check(built.get("ok",false),"offline white metadata fixture published")
	var white_result:Dictionary=white.read(source,folder,source_sha,expected.file_length)
	var delegated:Dictionary=Product.read(source,folder,source_sha,expected.file_length)
	check(not white_result.is_empty() and delegated==white_result,"white product helper delegates to existing white metadata unchanged")
	controls.native_geometry_only=previous_native
	print("NATIVE_MODEL_PRODUCT passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
