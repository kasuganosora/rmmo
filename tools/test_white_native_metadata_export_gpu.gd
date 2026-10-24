extends "res://tools/test_asset_bounds_manifest.gd"
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Metadata=preload("res://scripts/world3d/white_native_asset_metadata.gd")
func run()->void:
	check(DisplayServer.get_name()!="headless","real isolated GPU context")
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd");controls.enable_white_materials();controls.discard_map_textures=true
	var directory:=Paths.cache_directory("native_metadata_export_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("fixture.glb");write(path,data())
	var source_sha:=FileAccess.get_sha256(path);var expected:=Manifest.read(path);var memory:=Metadata.Memory.estimate(path)
	var result:=Native.build(path,directory)
	check(result.ok and result.has("metadata"),"actual native writer exports geometry and its source-bound descriptor together")
	if not result.ok:print(result);quit(1);return
	var read:=Native.read(path,source_sha,directory,false)
	check(read.hit,"saved native product reopens with checksum verification")
	var index_path:=Native.index_path(path,directory)
	var stale:Dictionary=result.manifest.duplicate(true);stale.generator="old_incompatible_contract"
	FileAccess.open(index_path,FileAccess.WRITE).store_string(JSON.stringify(stale))
	var rejected:=Native.read(path,source_sha,directory,true)
	check(not rejected.hit and rejected.reason=="white_native_version","old or changed product contracts cannot silently reuse an existing payload")
	var length:=FileAccess.open(path,FileAccess.READ).get_length()
	check(Metadata.read(path,directory,source_sha,length).is_empty(),"metadata companion rejects the same incompatible product contract")
	var provenance:Dictionary=result.manifest.duplicate(true)
	provenance.exporter_provenance.sources.ground_cpu_mesh="unrelated retirement edit"
	provenance.exporter_provenance.sources.white_native_asset_writer="unrelated diagnostics edit"
	FileAccess.open(index_path,FileAccess.WRITE).store_string(JSON.stringify(provenance))
	var reused:=Native.read(path,source_sha,directory,false)
	check(reused.hit,"export audit provenance does not invalidate a compatible native product")
	check(not Metadata.read(path,directory,source_sha,length).is_empty(),"export audit provenance does not invalidate the metadata companion")
	check(FileAccess.get_sha256(result.product)==result.manifest.payload_sha,"changing audit provenance never rewrites product bytes")
	FileAccess.open(index_path,FileAccess.WRITE).store_string(JSON.stringify(result.manifest))
	var node:Node=read.packed.instantiate()
	check(node!=null and node.find_children("*","MeshInstance3D",true,false).size()==1,"reopened native model retains its actual mesh hierarchy")
	var source=preload("res://scripts/world3d/asset_source_metadata.gd");source.disk_cache_enabled=false
	var observed:=source.read(path,directory)
	check(observed.get("native_metadata_hit",false) and observed.local_bounds==expected.local_bounds and observed.memory==memory,"production metadata reader uses exact exported bounds and unchanged full memory envelope")
	check(FileAccess.get_sha256(path)==source_sha and FileAccess.get_sha256(result.product)==result.manifest.payload_sha,"source and native identities still match after independent reopening")
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(node)
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	print("WHITE_NATIVE_METADATA_EXPORT_GPU passed=",passed," failures=",failures);quit(1 if failures else 0)
