extends RefCounted
## Published native model metadata, never an import operation.
## Full products use the same footprint identity and reservation as their reader.
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")

static func read(path:String,root:String,identity:String="",length:int=-1,timing:Variant=null,file_identities:Variant=null)->Dictionary:
	var began:=Time.get_ticks_usec() if timing!=null else 0
	var descriptor:Dictionary={}
	var candidate:=Footprint.candidate(path,root,identity,true,"",descriptor,file_identities)
	if timing!=null:timing.candidate_us=Time.get_ticks_usec()-began
	if candidate.is_empty():return {}
	var source:Variant=descriptor.get("model_metadata")
	if not source is Dictionary or source.get("version")!=1:return {}
	var raw:Variant=source.get("local_bounds")
	if not raw is Array or raw.size()!=6:return {}
	for value:Variant in raw:
		if not (value is int or value is float) or not is_finite(float(value)):return {}
	if float(raw[3])<0 or float(raw[4])<0 or float(raw[5])<0:return {}
	if not Footprint._integer(source.get("file_length"),4294967295,28) or source.file_length!=descriptor.get("source_bytes") or (length>=0 and source.file_length!=length):return {}
	if not Footprint._integer(source.get("json_bytes"),4194304,4) or not Compiled._sha(source.get("json_sha256")):return {}
	var box:=AABB(Vector3(float(raw[0]),float(raw[1]),float(raw[2])),Vector3(float(raw[3]),float(raw[4]),float(raw[5])))
	var source_length:int=int(source.file_length)
	var memory:={"estimated_bytes":candidate.estimated_bytes,"resident_bytes":candidate.resident_bytes,"exclusive":candidate.exclusive,"source_bytes":source_length,"known":true,"reason":"published_full_native_footprint","native_product_kind":"full"}
	return {"known":true,"reason":"source_accessor_bounds","path":path,"local_bounds":box,"world_bounds":box,
		"json_sha256":source.json_sha256,"file_length":source_length,"json_bytes":int(source.json_bytes),"memory":memory,
		"native_metadata_hit":true,"metadata_cache_hit":false,"native_source_sha":candidate.source_sha,
		"native_payload_sha":candidate.payload_sha,"native_product_path":candidate.product,"native_product_bytes":candidate.bytes,
		"native_index_path":Compiled.index_path(path,root),"native_descriptor_path":Footprint.descriptor_path(path,root),"native_candidate":candidate}
