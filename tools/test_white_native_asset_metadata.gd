extends "res://tools/test_asset_bounds_manifest.gd"
const Metadata=preload("res://scripts/world3d/white_native_asset_metadata.gd")
const Source=preload("res://scripts/world3d/asset_source_metadata.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
func run()->void:
	Policy.verify_packages=false
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd");controls.enable_white_materials();controls.discard_map_textures=true
	var directory:=Paths.cache_directory("native_metadata_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("model.glb");write(path,data())
	var sha:=FileAccess.get_sha256(path);var length:=FileAccess.open(path,FileAccess.READ).get_length()
	var expected:=Manifest.read(path);var memory:=Metadata.Memory.estimate(path)
	var folder:=Metadata.Writer.directory(directory);DirAccess.make_dir_recursive_absolute(folder)
	# Descriptor tests exercise identity binding with a private stand-in payload;
	# actual PackedScene decoding is covered by the native GPU and real-map tests.
	var bytes:=PackedByteArray([1,2,3,4]);var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes);var payload_sha:=hash_.finish().hex_encode()
	var product:=folder.path_join(payload_sha+".scn");FileAccess.open(product,FileAccess.WRITE).store_buffer(bytes)
	var info:={"generator":Metadata.Writer.generator(),"source_sha":sha,"payload_sha":payload_sha,"bytes":bytes.size()}
	var index:=Metadata.Writer.index_path(path,directory);FileAccess.open(index,FileAccess.WRITE).store_string(JSON.stringify(info))
	var built:=Metadata.build(path,directory);check(built.ok,"offline descriptor export succeeds")
	var value:=Metadata.read(path,directory,sha,length)
	check(value.local_bounds==expected.local_bounds and value.memory==memory and value.json_sha256==expected.json_sha256,"exact bounds and full memory estimate survive independent binary save and reopen")
	check(FileAccess.get_sha256(product)==payload_sha and FileAccess.get_sha256(path)==sha,"descriptor export leaves source and native payload bytes unchanged")
	value.memory.estimated_bytes=1
	check(Metadata.read(path,directory,sha,length).memory==memory,"each reader owns its tiny metadata dictionaries")
	Source.disk_cache_enabled=false;var trace=preload("res://scripts/world3d/load_trace.gd");trace.minimum_event_us=0;trace.start()
	var actual:=Source.read(path,directory);var events:Array=trace.stop().events
	check(actual.native_metadata_hit and not actual.metadata_cache_hit and actual.memory==memory,"offline native descriptor is available with all runtime observation caches disabled")
	check(events.all(func(e):return e.label!="model.bounds_manifest"),"native descriptor lookup does not parse or traverse GLB JSON")
	check(Metadata.read(path,directory,"0".repeat(64),length).is_empty() and Metadata.read(path,directory,sha,length+1).is_empty(),"changed source identity and length reject stale descriptors")
	var packet:Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(built.descriptor))
	for field:String in ["generation","geometry_generator","source_sha","payload_sha"]:
		var changed:=packet.duplicate(true);changed[field]="stale"
		FileAccess.open(built.descriptor,FileAccess.WRITE).store_buffer(var_to_bytes(changed))
		check(Metadata.read(path,directory,sha,length).is_empty(),"stale descriptor rejects "+field)
	FileAccess.open(built.descriptor,FileAccess.WRITE).store_buffer(var_to_bytes(packet))
	info.payload_sha="1".repeat(64);FileAccess.open(index,FileAccess.WRITE).store_string(JSON.stringify(info))
	check(Metadata.read(path,directory,sha,length).is_empty(),"replaced native product cannot inherit the old descriptor")
	info.payload_sha=payload_sha;FileAccess.open(index,FileAccess.WRITE).store_string(JSON.stringify(info))
	Policy.verify_packages=true;check(not Source.read(path,directory).has("native_metadata_hit"),"explicit diagnostic mode retains source observation")
	Policy.verify_packages=false;controls.discard_map_textures=false
	check(Metadata.read(path,directory,sha,length).is_empty(),"ordinary textured loading retains its existing policy")
	for item:String in [path,product,index,built.descriptor]:DirAccess.remove_absolute(item)
	print("WHITE_NATIVE_ASSET_METADATA passed=",passed," failures=",failures);quit(1 if failures else 0)
