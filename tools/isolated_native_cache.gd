extends RefCounted
## Offline fixture helper. This file is not used by game/editor loading.
## Caller owns a private, new temporary root and must serialize calls to it.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Writer=preload("res://scripts/world3d/white_native_asset_writer.gd")
const Metadata=preload("res://scripts/world3d/white_native_asset_metadata.gd")
const ARTIFACT_ROOT:="D:/code/rmmo_runtime/review_artifacts"

static func _fail(reason:String)->Dictionary:return {"ok":false,"reason":reason}

static func rekey(original_model:String,temp_model:String,old_root:String,temp_root:String)->Dictionary:
	# The new root is a caller-owned fixture only; it is never the formal pack.
	# Original logical keys identify native products; the corresponding GLB is
	# intentionally neither opened nor copied by this operation.
	if not Thread.is_main_thread():return _fail("main_thread_required")
	if temp_root.replace("\\","/").simplify_path()==ARTIFACT_ROOT or not Paths.allowed(temp_root,ARTIFACT_ROOT) or not DirAccess.dir_exists_absolute(temp_root):return _fail("temporary_root")
	if old_root.replace("\\","/").simplify_path()==temp_root.replace("\\","/").simplify_path():return _fail("same_root")
	if not Paths.asset_key_allowed(original_model,old_root) or not Paths.asset_key_allowed(temp_model,temp_root):return _fail("logical_path")
	if original_model.get_file()!=temp_model.get_file():return _fail("source_name_changed")
	if not Writer.active():return _fail("native_geometry_mode_required")
	var meta:Dictionary=Metadata.read(original_model,old_root)
	if meta.is_empty():return _fail("native_metadata_missing_or_stale")
	var source_sha:String=meta.native_source_sha;var payload_sha:String=meta.native_payload_sha
	var original_index:=Writer.index_path(original_model,old_root)
	var original_descriptor:=Metadata.path_for(original_model,old_root)
	var original_product:=Writer.directory(old_root).path_join(payload_sha+".scn")
	var target_index:=Writer.index_path(temp_model,temp_root)
	var target_descriptor:=Metadata.path_for(temp_model,temp_root)
	var target_product:=Writer.directory(temp_root).path_join(payload_sha+".scn")
	var pairs:Array=[{"kind":"payload","source":original_product,"target":target_product},
		{"kind":"metadata","source":original_descriptor,"target":target_descriptor},
		{"kind":"index","source":original_index,"target":target_index}]
	for pair:Dictionary in pairs:
		if not Paths.allowed(pair.source,old_root) or not Paths.allowed(pair.target,temp_root) or not FileAccess.file_exists(pair.source):return _fail("file_path_or_source")
		var file:=FileAccess.open(pair.source,FileAccess.READ)
		if file==null:return _fail("source_open")
		pair.bytes=file.get_length();file.close()
		pair.sha256=FileAccess.get_sha256(pair.source)
		if pair.sha256.is_empty():return _fail("source_hash")
		pair.reused=FileAccess.file_exists(pair.target)
		if pair.reused and FileAccess.get_sha256(pair.target)!=pair.sha256:return _fail("target_conflict")
	if pairs[0].sha256!=payload_sha or int(pairs[0].bytes)!=int(meta.native_product_bytes):return _fail("native_product_identity")
	if not ResourceLoader.get_dependencies(original_product).is_empty():return _fail("native_external_dependencies")
	if DirAccess.make_dir_recursive_absolute(Writer.directory(temp_root))!=OK:return _fail("target_directory")
	for pair:Dictionary in pairs:
		if not pair.reused:
			# No other process may write this explicitly private fixture root.
			# Payload and descriptor precede index so incomplete copies do not
			# expose a complete native index to the test loader.
			if FileAccess.file_exists(pair.target):return _fail("target_appeared")
			if DirAccess.copy_absolute(pair.source,pair.target)!=OK:return _fail("copy_failed")
		if FileAccess.get_sha256(pair.target)!=pair.sha256 or FileAccess.get_sha256(pair.source)!=pair.sha256:return _fail("copy_identity_changed")
	var relocated:Dictionary=Metadata.read(temp_model,temp_root,source_sha)
	if relocated.is_empty() or relocated.native_payload_sha!=payload_sha:return _fail("relocated_metadata")
	var reused:=0
	for pair:Dictionary in pairs:reused+=int(pair.reused)
	return {"ok":true,"reason":"","source_sha256":source_sha,"payload_sha256":payload_sha,
		"product_bytes":int(meta.native_product_bytes),"original_model":original_model,"temp_model":temp_model,
		"files":pairs,"reused":reused,"contract":"Offline private fixture root; native product has no external ResourceLoader dependencies; GLB is not opened or copied."}
