extends RefCounted
## Object-free offline road geometry. The authored shape determines the key;
## placement, visibility and materials remain instance-owned runtime data.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const MAGIC="RMMORD02"
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
const MAX_BYTES=64*1024*1024
static var enabled:=true
static var prepared_bounds_enabled:=true
static var _version:=""
static var _mutex:=Mutex.new()

static func active()->bool:return enabled and Controls.white_materials and Controls.discard_map_textures

static func version()->String:
	_mutex.lock()
	if _version.is_empty():
		var inputs:Array=[2,Engine.get_version_info().hash]
		for script:String in ["road_array_cache","road_surface","road_surface_arrays","road_kerb","road_kerb_arrays","procedural_surface_bounds"]:inputs.append(FileAccess.get_sha256("res://scripts/world3d/"+script+".gd"))
		_version=str(inputs).sha256_text()
	var result:=_version;_mutex.unlock();return result

static func identity(record:Dictionary,definition_sha:String="")->String:
	# The mounted rmres identity already covers every authored geometry field.
	# Size is the only geometry input overlaid by the compact instance header.
	# Avoid serializing/hashing thousands of kerb coordinates a second time.
	if definition_sha.length()==64 and definition_sha.is_valid_hex_number(false):return str([definition_sha,record.size]).sha256_text()
	# These are exactly the inputs consumed by Road.arrays/local_polygons and
	# Kerb.arrays. In particular elevations, UV origin and terrain grade matter.
	var bytes:=var_to_bytes([record.size,record.road_mesh,record.get("terrain_grade")])
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes)
	return hash_.finish().hex_encode()

static func product_path(key:String,root:String)->String:
	if root.is_empty() or key.length()!=64 or not key.is_valid_hex_number(false):return ""
	var folder:=root.path_join("cache/world3d/road_arrays_v1")
	var path:=folder.path_join(key+"."+version()+".bin")
	return path if Paths.allowed(path,root) else ""

static func read(record:Dictionary,root:String,output_bytes:int,definition_sha:String="")->Dictionary:
	if not active():return {}
	var started:=Time.get_ticks_usec();var key:=identity(record,definition_sha);var path:=product_path(key,root)
	if path.is_empty():return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	var size:=file.get_length()
	if size<=16 or size>MAX_BYTES or file.get_buffer(8).get_string_from_ascii()!=MAGIC:return {}
	var length:=file.get_64()
	# Keep decode workspace inside the existing conservative road admission.
	if length<=0 or length>mini(MAX_BYTES,output_bytes+65536):return {}
	var compressed:=file.get_buffer(size-16)
	if compressed.size()!=size-16:return {}
	var raw:=compressed.decompress(length,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=length:return {}
	var value:Variant=bytes_to_var(raw)
	if not value is Dictionary or value.get("key")!=key or value.get("version")!=version() or not value.get("arrays") is Array:return {}
	if value.arrays.size()!=(4 if record.road_mesh.has("kerbs") else 3):return {}
	# The builder compared complete channels. Runtime only checks the container
	# contract, without repeating per-vertex geometry certification.
	for surface:Variant in value.arrays:
		if not surface is Array or surface.size()!=Mesh.ARRAY_MAX or not surface[Mesh.ARRAY_VERTEX] is PackedVector3Array:return {}
	if not value.get("bounds") is AABB:return {}
	preload("res://scripts/world3d/load_trace.gd").elapsed("road.binary_read",started,{"bytes":size})
	var result:={"arrays":value.arrays,"bytes":size}
	if prepared_bounds_enabled:result.bounds=value.bounds
	return result

static func build(record:Dictionary,root:String,definition_sha:String="")->Dictionary:
	var key:=identity(record,definition_sha);var path:=product_path(key,root)
	if path.is_empty():return {"ok":false,"reason":"path"}
	var arrays:=Road.arrays(record)
	# Exact local bounds belong to the generated immutable arrays. Persist them
	# once instead of rescanning every vertex on every load and return visit.
	var raw:=var_to_bytes({"key":key,"version":version(),"arrays":arrays,"bounds":Bounds.bounds(arrays)})
	if raw.size()>MAX_BYTES:return {"ok":false,"reason":"size"}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var staged:=path+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return {"ok":false,"reason":"write"}
	file.store_buffer(MAGIC.to_ascii_buffer());file.store_64(raw.size());file.store_buffer(raw.compress(FileAccess.COMPRESSION_ZSTD));file.flush()
	var error:=file.get_error();var bytes:=file.get_length();file.close()
	if error==OK:
		if not FileAccess.file_exists(path):error=DirAccess.rename_absolute(staged,path)
		else:error=preload("res://scripts/world3d/atomic_file.gd").publish(staged,path)
	return {"ok":error==OK,"key":key,"path":path,"bytes":bytes,"raw_bytes":raw.size()}
