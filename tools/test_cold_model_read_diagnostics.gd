extends "res://tools/test_asset_bounds_manifest.gd"
## Only generated tiny GLBs and metadata descriptors under an isolated root.
## No real map, textures, native scene decoding or GPU work is needed.
const Source=preload("res://scripts/world3d/asset_source_metadata.gd")
const Native=preload("res://scripts/world3d/white_native_asset_metadata.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
var created:Array[String]=[]

func prepare_descriptor(path:String,directory:String,payload_sha:String)->void:
	var info:={"generator":Native.Writer.generator(),"source_sha":FileAccess.get_sha256(path),"payload_sha":payload_sha,"bytes":4}
	var index:=Native.Writer.index_path(path,directory)
	FileAccess.open(index,FileAccess.WRITE).store_string(JSON.stringify(info));created.append(index)
	var built:=Native.build(path,directory)
	check(built.ok,"private native metadata descriptor is built")
	if built.ok:created.append(built.descriptor)

func run()->void:
	Policy.verify_packages=false
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	controls.enable_white_materials();controls.discard_map_textures=true
	var directory:=Paths.cache_directory("cold_read_diagnostics_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var named:=directory.path_join("model.glb");write(named,data());created.append(named)
	var sha:=FileAccess.get_sha256(named)
	var hashed:=directory.path_join(sha+".glb");write(hashed,data());created.append(hashed)
	var payload:=PackedByteArray([1,2,3,4]);var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(payload)
	var payload_sha:=hash_.finish().hex_encode()
	var native_dir:=Native.Writer.directory(directory);DirAccess.make_dir_recursive_absolute(native_dir)
	var product:=native_dir.path_join(payload_sha+".scn");FileAccess.open(product,FileAccess.WRITE).store_buffer(payload);created.append(product)
	prepare_descriptor(named,directory,payload_sha);prepare_descriptor(hashed,directory,payload_sha)
	for path:String in [named,hashed]:
		check(DirAccess.remove_absolute(path)==OK,"diagnostic fixture removes the authoring GLB before runtime reads")
		var plain:=Source.read(path,directory,"",true)
		var timing:={};var observed:=Source.read(path,directory,"",true,timing)
		check(observed==plain and observed.get("native_metadata_hit",false),"optional timings preserve the native metadata result")
		check(timing.path_check_count==1 and timing.source_open_count==0 and timing.source_identity_count==0 and timing.native_metadata_count==1,"native metadata lookup performs no original-source open or identity scan")
		check(timing.identity_mode=="native_index","hashed and named logical keys resolve identity from the native index")
		check(observed.get("file_length",0)>0 and timing.path_check_us>=0 and timing.source_open_length_close_us==0 and timing.source_identity_us==0 and timing.native_metadata_us>=0,"offline source size is preserved while original-source timing remains zero")
	var timing:={};var denied:=Source.read(directory+"/../outside.glb",directory,"",true,timing)
	check(not denied.known and timing.path_check_count==1 and timing.source_open_count==0,"path rejection does not acquire a source file just for diagnostics")
	var absent:=Source.read(directory+"/missing.glb",directory,"",true,timing)
	check(not absent.known and timing.source_open_count==0 and timing.source_identity_count==0 and timing.native_metadata_count==1 and timing.identity_mode=="native_index","missing source and missing descriptor fail through native lookup without scanning GLB")
	var record:={"uuid":"near","kind":"asset","asset_path":named,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	var far:=record.duplicate(true);far.uuid="far";far.position[0]=500
	var other:=record.duplicate(true);other.uuid="other";other.asset_path=hashed
	var records:Array=[record,far,other]
	var loader:=Loader.new();loader._content_root=directory;loader._entry_origin=Vector3.ZERO;loader._model_preparation.require_native_products=true
	Loader.cold_read_diagnostics_enabled=false;Index.classification_path_batching=true
	var baseline:Dictionary=loader._cold_model_hints(records)
	check(not loader._profile.has("cold_model_hints_detail"),"disabled diagnostics do not publish a detail packet")
	Loader.cold_read_diagnostics_enabled=true
	var measured:Dictionary=loader._cold_model_hints(records);var detail:Dictionary=loader._profile.cold_model_hints_detail
	check(measured==baseline and measured.error.is_empty(),"cold-hint diagnostics preserve the selected paths and manifests")
	check(detail.asset_records==3 and detail.paths.size()==2 and detail.outer_path_check_count==2 and detail.metadata_read_count==2 and detail.apply_record_count==3 and detail.closing_path_check_count==2,"batched diagnostics count unique reads separately from instance transforms")
	check(detail.start_us>0 and detail.end_us>=detail.start_us and detail.paths.values().all(func(row):return row.start_us>=detail.start_us and row.end_us<=detail.end_us and row.metadata_read_end_us>=row.metadata_read_start_us),"absolute diagnostic clocks bound each path and its metadata read")
	check(detail.paths[named].records==2 and detail.paths[named].metadata_read_count==1 and detail.paths[named].metadata.identity_mode=="native_index","repeated model instances share one timed native metadata read")
	Index.classification_path_batching=false
	var unbatched:Dictionary=loader._cold_model_hints(records);detail=loader._profile.cold_model_hints_detail
	check(unbatched==baseline and detail.outer_path_check_count==3 and detail.closing_path_check_count==0 and detail.metadata_read_count==2,"diagnostics retain the old unbatched path policy without extra metadata work")
	# Exercise the retention limit using only already-owned manifests. This
	# checks diagnostics memory, without reading or creating 129 source files.
	var bounded:={"paths":{},"paths_truncated":false}
	for i:int in Loader.COLD_READ_DIAGNOSTIC_PATH_LIMIT+2:Loader._cold_hint_detail_row(bounded,"synthetic_%d"%i)
	check(bounded.paths.size()==Loader.COLD_READ_DIAGNOSTIC_PATH_LIMIT and bounded.paths_truncated,"per-path diagnostics retain a bounded number of entries")
	Loader.cold_read_diagnostics_enabled=false;Index.classification_path_batching=true;loader.free()
	for path:String in created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	print("COLD_MODEL_READ_DIAGNOSTICS passed=",passed," failures=",failures)
	quit(1 if failures else 0)
