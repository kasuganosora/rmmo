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
static var enabled:=true
static var _generation:=""
static var _mutex:=Mutex.new()
static func generation()->String:
	_mutex.lock()
	if _generation.is_empty():
		var inputs:Array=[1,Engine.get_version_info().hash]
		for name:String in ["white_native_asset_metadata","asset_bounds_manifest","asset_memory_estimate"]:inputs.append(FileAccess.get_sha256("res://scripts/world3d/"+name+".gd"))
		_generation=str(inputs).sha256_text()
	var result:=_generation;_mutex.unlock();return result
static func path_for(path:String,root:String)->String:
	return Writer.index_path(path,root).get_basename()+".metadata.bin"
static func _index(path:String,root:String)->Dictionary:
	var path_=Writer.index_path(path,root)
	if not Paths.allowed(path_,root):return {}
	var file:=FileAccess.open(path_,FileAccess.READ)
	if file==null or file.get_length()>8192:return {}
	var info:Variant=JSON.parse_string(file.get_as_text())
	return info if info is Dictionary and info.get("generator")==Writer.generator() else {}
static func read(path:String,root:String,identity:String,length:int)->Dictionary:
	if not enabled or not Writer.active():return {}
	var info:=_index(path,root)
	if info.is_empty() or info.get("source_sha")!=identity:return {}
	var target:=path_for(path,root)
	if not Paths.allowed(target,root):return {}
	var file:=FileAccess.open(target,FileAccess.READ)
	if file==null or file.get_length()<4 or file.get_length()>LIMIT:return {}
	var packet:Variant=bytes_to_var(file.get_buffer(file.get_length()))
	if not packet is Dictionary or packet.get("generation")!=generation() or packet.get("source_sha")!=identity or packet.get("payload_sha")!=info.get("payload_sha") or packet.get("geometry_generator")!=info.generator:return {}
	var value:Variant=packet.get("observation")
	if not value is Dictionary or value.get("known")!=true or value.get("file_length")!=length or not value.get("local_bounds") is AABB or not value.get("memory") is Dictionary:return {}
	value.path=path;value.native_metadata_hit=true;value.metadata_cache_hit=false
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
	var packet:={"generation":generation(),"geometry_generator":info.generator,"source_sha":info.source_sha,"payload_sha":info.payload_sha,"observation":observation}
	var bytes:=var_to_bytes(packet);var target:=path_for(path,root)
	if bytes.size()>LIMIT or not Paths.allowed(target,root):return {"ok":false,"reason":"descriptor_size_or_path"}
	if FileAccess.get_sha256(path)!=info.source_sha or _index(path,root)!=info:return {"ok":false,"reason":"source_changed_during_export"}
	var staged:=target+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return {"ok":false,"reason":"descriptor_write"}
	file.store_buffer(bytes);file.flush();var error:=file.get_error();file.close()
	if error==OK:error=preload("res://scripts/world3d/atomic_file.gd").publish(staged,target)
	return {"ok":error==OK,"error":error,"source":path,"source_sha":info.source_sha,"product":product,"payload_sha":info.payload_sha,"descriptor":target,"descriptor_sha":FileAccess.get_sha256(target) if error==OK else "","descriptor_bytes":bytes.size(),"observation":observation}
