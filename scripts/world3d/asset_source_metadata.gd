extends RefCounted
## Small CPU observations of immutable package models. A map edit invalidates
## placement, not model-local bounds or the conservative memory envelope.
## This contains no geometry, materials, textures, nodes or GPU resources.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Memory=preload("res://scripts/world3d/asset_memory_estimate.gd")
const LIMIT:=16384
static var disk_cache_enabled:=true
static var _generation:=""
static var _mutex:=Mutex.new()
static func generation()->String:
	_mutex.lock()
	if _generation.is_empty():
		_generation=(FileAccess.get_sha256("res://scripts/world3d/asset_source_metadata.gd")+FileAccess.get_sha256("res://scripts/world3d/asset_bounds_manifest.gd")+FileAccess.get_sha256("res://scripts/world3d/asset_memory_estimate.gd")+str(Engine.get_version_info().hash)).sha256_text()
	var result:=_generation
	_mutex.unlock()
	return result
static func cache_path(identity:String,root:String,version:String="")->String:
	if identity.length()!=64 or not identity.is_valid_hex_number(false):return ""
	var key:=generation() if version.is_empty() else version.sha256_text()
	return root.path_join("cache/world3d/model_metadata").path_join(key).path_join(identity+".bin")
static func read(path:String,root:String,version:String="",native_only:bool=false,timing:Variant=null)->Dictionary:
	# Optional caller-owned diagnostics; no shared counters, locks or extra I/O.
	# These are nested wall spans, not exclusive CPU or pure disk time.
	if timing!=null:timing.assign({"path_check_us":0,"path_check_count":0,"source_open_length_close_us":0,"source_open_count":0,"source_identity_us":0,"source_identity_count":0,"native_metadata_us":0,"native_metadata_count":0})
	if not Policy.trusted() and not native_only:return _observe(path)
	if native_only:
		# The original GLB is an optional authoring input, not a runtime
		# prerequisite. Resolve both identity and the offline size from the
		# published descriptor, even for a human-readable logical asset name.
		var native_started:=Time.get_ticks_usec() if timing!=null else 0
		var key_allowed:=Paths.asset_key_allowed(path,root)
		if timing!=null:timing.path_check_count=1;timing.path_check_us=Time.get_ticks_usec()-native_started;timing.identity_mode="native_index";native_started=Time.get_ticks_usec()
		if not key_allowed:return Manifest.unknown("metadata_source_path")
		var native_details:Variant={} if timing!=null else null
		var published:=preload("res://scripts/world3d/native_model_product.gd").read(path,root,"",-1,native_details)
		if timing!=null:
			timing.native_metadata_us=Time.get_ticks_usec()-native_started;timing.native_metadata_count=1;timing.native_metadata_hit=not published.is_empty();timing.native_details=native_details
		return published if not published.is_empty() else Manifest.unknown("native_metadata_missing_or_stale")
	var began:=Time.get_ticks_usec() if timing!=null else 0
	var allowed:=Paths.allowed(path,root)
	if timing!=null:timing.path_check_us=Time.get_ticks_usec()-began;timing.path_check_count=1
	if not allowed:return Manifest.unknown("metadata_source_path")
	if timing!=null:began=Time.get_ticks_usec()
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:
		if timing!=null:timing.source_open_length_close_us=Time.get_ticks_usec()-began;timing.source_open_count=1
		return Manifest.unknown("missing_or_short")
	var length:=file.get_length();file.close()
	if timing!=null:
		timing.source_open_length_close_us=Time.get_ticks_usec()-began;timing.source_open_count=1;timing.source_bytes=length
		var name:=path.get_file().get_basename()
		timing.identity_mode="filename_sha" if name.length()==64 and name.is_valid_hex_number(false) else "source_sha_scan"
		began=Time.get_ticks_usec()
	var identity:=Policy.source_identity(path)
	if timing!=null:timing.source_identity_us=Time.get_ticks_usec()-began;timing.source_identity_count=1;began=Time.get_ticks_usec()
	if not disk_cache_enabled:return _observe(path)
	var target:=cache_path(identity,root,version)
	if target.is_empty() or not Paths.allowed(target,root):return _observe(path)
	file=FileAccess.open(target,FileAccess.READ)
	if file!=null and file.get_length()>=4 and file.get_length()<=LIMIT:
		var value:Variant=bytes_to_var(file.get_buffer(file.get_length()))
		file.close()
		if value is Dictionary and value.get("known")==true and value.get("file_length")==length and value.get("local_bounds") is AABB and value.get("memory") is Dictionary and value.get("json_sha256") is String:
			value.path=path;value.metadata_cache_hit=true
			return value
	var observed:=_observe(path)
	if not observed.get("known",false):return observed
	# Keep the same admission estimate; native file size is not resident memory.
	var payload:Dictionary={}
	for key:String in ["known","reason","local_bounds","world_bounds","json_sha256","file_length","json_bytes","memory"]:payload[key]=observed[key]
	var bytes:=var_to_bytes(payload)
	if bytes.size()<=LIMIT and DirAccess.make_dir_recursive_absolute(target.get_base_dir())==OK and Paths.allowed(target,root):
		var temporary:=target+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
		file=FileAccess.open(temporary,FileAccess.WRITE)
		if file!=null:
			file.store_buffer(bytes);file.flush();var error:=file.get_error();file.close()
			if error!=OK or DirAccess.rename_absolute(temporary,target)!=OK:DirAccess.remove_absolute(temporary)
	observed.metadata_cache_hit=false
	return observed
static func _observe(path:String)->Dictionary:
	var result:=Manifest.read(path)
	if result.get("known",false):result.memory=Memory.estimate(path)
	return result
