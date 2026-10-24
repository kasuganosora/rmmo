extends RefCounted
## Offline companion of a white native model, not a runtime observation cache.
## Geometry stays byte-identical; bounds and the full fallback memory envelope
## are computed by the exporter and bound to both source and native identities.
const Writer=preload("res://scripts/world3d/white_native_asset_writer.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Bounds=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Memory=preload("res://scripts/world3d/asset_memory_estimate.gd")
const FIELDS=["known","reason","local_bounds","world_bounds","json_sha256","file_length","json_bytes","memory"]
const LIMIT:=16384
const DESCRIPTOR_REVISION:=2
static var enabled:=true
static var _generation:=""
static var _mutex:=Mutex.new()
static func generation()->String:
	_mutex.lock()
	if _generation.is_empty():
		# Reader scheduling/instrumentation is not a serialized format change.
		# Bounds and memory producers remain conservative invalidation inputs.
		var inputs:Array=[DESCRIPTOR_REVISION,Writer.generator()]
		for name:String in ["asset_bounds_manifest","asset_memory_estimate"]:inputs.append(FileAccess.get_sha256("res://scripts/world3d/"+name+".gd"))
		_generation=str(inputs).sha256_text()
	var result:=_generation;_mutex.unlock();return result
static func path_for(path:String,root:String)->String:
	return Writer.index_path(path,root).get_basename()+".metadata.bin"
static func _sha(bytes:PackedByteArray)->String:
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes)
	return hash_.finish().hex_encode()
static func _index(path:String,root:String,timing:Variant=null,file_identities:Variant=null)->Dictionary:
	var began:=Time.get_ticks_usec() if timing!=null else 0
	if not Paths.asset_key_allowed(path,root):return {}
	var path_=Writer.index_path(path,root)
	if not Paths.allowed(path_,root):return {}
	if timing!=null:timing.index_path_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	var file:=FileAccess.open(path_,FileAccess.READ)
	if file==null or file.get_length()>8192:return {}
	if timing!=null:timing.index_open_length_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	var text:String
	if file_identities!=null:
		var bytes:=file.get_buffer(file.get_length());text=bytes.get_string_from_utf8()
		file_identities[path_]=_sha(bytes)
	else:text=file.get_as_text()
	file.close()
	if timing!=null:timing.index_read_close_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	var info:Variant=JSON.parse_string(text)
	if timing!=null:timing.index_json_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	if not info is Dictionary or info.get("generator")!=Writer.generator():return {}
	for field:String in ["source_sha","payload_sha"]:
		if not info.get(field) is String or info[field].length()!=64 or not info[field].is_valid_hex_number(false):return {}
	if not (info.get("bytes") is int or info.get("bytes") is float) or info.bytes<=0 or int(info.bytes)!=info.bytes:return {}
	var key:=path.get_file().get_basename()
	if key.length()==64 and key.is_valid_hex_number(false) and key!=info.source_sha:return {}
	if timing!=null:timing.index_contract_us=Time.get_ticks_usec()-began
	return info
static func read(path:String,root:String,identity:String="",length:int=-1,timing:Variant=null,file_identities:Variant=null)->Dictionary:
	if not enabled or not Writer.active():return {}
	var began:=Time.get_ticks_usec() if timing!=null else 0
	var info:=_index(path,root,timing,file_identities)
	if timing!=null:timing.index_us=Time.get_ticks_usec()-began
	if info.is_empty() or (not identity.is_empty() and info.source_sha!=identity):return {}
	var target:=path_for(path,root)
	if timing!=null:began=Time.get_ticks_usec()
	if not Paths.allowed(target,root):return {}
	if timing!=null:timing.descriptor_path_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	var file:=FileAccess.open(target,FileAccess.READ)
	if file==null or file.get_length()<4 or file.get_length()>LIMIT:return {}
	if timing!=null:timing.descriptor_open_length_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	var bytes:=file.get_buffer(file.get_length());file.close()
	# A prefetch snapshot may need exact file identities. Hash the bytes it
	# already owns instead of reopening both small files after this read.
	if file_identities!=null:file_identities[target]=_sha(bytes)
	if timing!=null:timing.descriptor_read_close_us=Time.get_ticks_usec()-began;timing.descriptor_bytes=bytes.size();began=Time.get_ticks_usec()
	var packet:Variant=bytes_to_var(bytes)
	if timing!=null:timing.descriptor_decode_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	if not packet is Dictionary or packet.get("descriptor_revision")!=DESCRIPTOR_REVISION or packet.get("generation")!=generation() or packet.get("source_sha")!=info.source_sha or packet.get("payload_sha")!=info.payload_sha or packet.get("geometry_generator")!=info.generator:return {}
	var value:Variant=packet.get("observation")
	if not value is Dictionary or value.get("known")!=true or not value.get("file_length") is int or value.file_length<=0 or (length>=0 and value.file_length!=length) or not value.get("local_bounds") is AABB or not value.get("memory") is Dictionary:return {}
	# This is an offline observation, including its historical source size. It
	# must remain sufficient for admission without a fallback source inspection.
	var memory:Dictionary=value.memory
	if not memory.get("estimated_bytes") is int or memory.estimated_bytes<=0 or memory.estimated_bytes>Memory.MAX_ESTIMATE or not memory.get("exclusive") is bool or memory.get("source_bytes")!=value.file_length:return {}
	value.path=path;value.native_metadata_hit=true;value.metadata_cache_hit=false
	value.native_source_sha=info.source_sha;value.native_payload_sha=info.payload_sha
	value.native_product_path=Writer.directory(root).path_join(info.payload_sha+".scn");value.native_product_bytes=int(info.bytes)
	value.native_index_path=Writer.index_path(path,root);value.native_descriptor_path=target
	if timing!=null:timing.descriptor_contract_us=Time.get_ticks_usec()-began
	return value
static func build(path:String,root:String)->Dictionary:
	# Export-time audit only. Runtime trusts the mounted package identities and
	# never rehashes models or walks the GLB to reconstruct this descriptor.
	if not Paths.allowed(path,root):return {"ok":false,"reason":"source_path"}
	var info:=_index(path,root)
	if info.is_empty():return {"ok":false,"reason":"native_product_missing_or_stale"}
	var product:=Writer.directory(root).path_join(str(info.get("payload_sha",""))+".scn")
	if not Paths.allowed(product,root) or FileAccess.get_sha256(product)!=info.get("payload_sha") or FileAccess.get_sha256(path)!=info.get("source_sha"):return {"ok":false,"reason":"source_or_product_changed"}
	var value:=Bounds.read(path)
	if not value.get("known",false):return {"ok":false,"reason":"unsupported_bounds"}
	value.memory=Memory.estimate(path)
	var observation:Dictionary={}
	for key:String in FIELDS:observation[key]=value[key]
	var packet:={"generation":generation(),"descriptor_revision":DESCRIPTOR_REVISION,"geometry_generator":info.generator,"source_sha":info.source_sha,"payload_sha":info.payload_sha,"observation":observation}
	var bytes:=var_to_bytes(packet);var target:=path_for(path,root)
	if bytes.size()>LIMIT or not Paths.allowed(target,root):return {"ok":false,"reason":"descriptor_size_or_path"}
	if FileAccess.get_sha256(path)!=info.source_sha or _index(path,root)!=info:return {"ok":false,"reason":"source_changed_during_export"}
	var staged:=target+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return {"ok":false,"reason":"descriptor_write"}
	file.store_buffer(bytes);file.flush();var error:=file.get_error();file.close()
	if error==OK:error=preload("res://scripts/world3d/atomic_file.gd").publish(staged,target)
	return {"ok":error==OK,"error":error,"source":path,"source_sha":info.source_sha,"product":product,"payload_sha":info.payload_sha,"descriptor":target,"descriptor_sha":FileAccess.get_sha256(target) if error==OK else "","descriptor_bytes":bytes.size(),"observation":observation,"descriptor_revision":DESCRIPTOR_REVISION,"exporter_source_sha":FileAccess.get_sha256("res://scripts/world3d/white_native_asset_metadata.gd")}
