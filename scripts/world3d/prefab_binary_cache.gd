extends RefCounted
## Offline, object-free projection of a frozen prefab. Authored source remains
## authoritative; only white geometry trials consume this derived product.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Faces=preload("res://scripts/world3d/prefab_face_arrays.gd")
const MAGIC="RMMOPFB1"
const MAX_BYTES=32*1024*1024
static var enabled:=true
static var directory_override:="" # Isolated regression fixtures only.
static var _directory:=""
static var _version:=""
static var _version_mutex:=Mutex.new()

static func active()->bool:
	return enabled and Controls.white_materials and Controls.discard_map_textures and preload("res://scripts/world3d/runtime_package_policy.gd").trusted()

static func directory()->String:
	if not directory_override.is_empty():return directory_override
	_version_mutex.lock();var result:=_directory;_version_mutex.unlock();return result

static func configure(root:String)->void:
	assert(Thread.is_main_thread())
	# Resolve autoload/settings ownership before dispatch. Workers only consume
	# this path snapshot, never discover content_root through the live tree.
	var folder:=root.path_join("cache/world3d/prefab_binary_v1") if not root.is_empty() else ""
	if not folder.is_empty() and not Paths.allowed(folder,root):folder=""
	_version_mutex.lock();_directory=folder;_version_mutex.unlock()

static func version()->String:
	_version_mutex.lock()
	if _version.is_empty():
		_version=str([1,Engine.get_version_info().hash,FileAccess.get_sha256("res://scripts/world3d/ground_cpu_mesh.gd"),FileAccess.get_sha256("res://scripts/world3d/prefab_binary_cache.gd"),FileAccess.get_sha256("res://scripts/world3d/prefab_face_arrays.gd")]).sha256_text()
	var result:=_version;_version_mutex.unlock();return result

static func product_path(digest:String)->String:
	if digest.length()!=64 or not digest.is_valid_hex_number(false):return ""
	var folder:=directory()
	if folder.is_empty():return ""
	var result:=folder.path_join(digest+"."+version()+".bin")
	return result if Paths.allowed(result,folder) else ""

static func read(digest:String,length:int)->Dictionary:
	if not active():return {}
	var located:=Time.get_ticks_usec()
	var path:=product_path(digest)
	preload("res://scripts/world3d/load_trace.gd").elapsed("prefab.binary_locate",located)
	if path.is_empty():return {}
	var opened:=Time.get_ticks_usec()
	var file:=FileAccess.open(path,FileAccess.READ)
	preload("res://scripts/world3d/load_trace.gd").elapsed("prefab.binary_open",opened)
	if file==null:return {}
	var began:=Time.get_ticks_usec();var size:=file.get_length()
	if size<=16 or size>MAX_BYTES or file.get_buffer(8).get_string_from_ascii()!=MAGIC:return {}
	var raw_length:=file.get_64()
	if raw_length<=0 or raw_length>MAX_BYTES:return {}
	var compressed:=file.get_buffer(size-16)
	if compressed.size()!=size-16:return {}
	var raw:=compressed.decompress(raw_length,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=raw_length:return {}
	var value:Variant=bytes_to_var(raw) # Never instantiate Objects from disk.
	if not value is Dictionary or value.get("sha256")!=digest or value.get("length")!=length or value.get("version")!=version():return {}
	if not value.get("data") is Dictionary or not value.get("geometry_keys") is Array:return {}
	if not value.data.get("meshes") is Array or value.geometry_keys.size()!=value.data.meshes.size():return {}
	if not value.data.get("materials") is Array or not value.data.get("entries") is Array or value.data.entries.size()!=1:return {}
	if not value.get("collision_faces") is Array or value.collision_faces.size()!=value.data.meshes.size():return {}
	for faces:Variant in value.collision_faces:
		if not faces is PackedVector3Array:return {}
	preload("res://scripts/world3d/load_trace.gd").elapsed("prefab.binary_read",began,{"sha256":digest,"bytes":size})
	return value

static func build(value:Dictionary)->Dictionary:
	# Offline conversion authenticates once. Runtime consumes the same trusted
	# package identity without repeating the geometry hash or Base64 conversion.
	var digest:String=value.get("sha256","");var length:=int(value.get("length",0))
	var path:=product_path(digest)
	if path.is_empty() or length<=0 or length>16*1024*1024:return {"ok":false,"reason":"identity"}
	var raw:=Marshalls.base64_to_raw(value.data).decompress(length,FileAccess.COMPRESSION_ZSTD)
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(raw)
	if raw.size()!=length or hash_.finish().hex_encode()!=digest:return {"ok":false,"reason":"source"}
	var data:Variant=bytes_to_var(raw)
	if not data is Dictionary or not data.get("meshes") is Array:return {"ok":false,"reason":"schema"}
	var keys:Array=[];var faces:Array=[]
	for mesh:Dictionary in data.meshes:
		keys.append(Cpu.geometry_signature(mesh.surfaces,mesh.get("lods",[])));faces.append(Faces.build(mesh))
	var payload:=var_to_bytes({"version":version(),"sha256":digest,"length":length,"data":data,"geometry_keys":keys,"collision_faces":faces})
	if payload.size()>MAX_BYTES:return {"ok":false,"reason":"size"}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var staged:=path+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return {"ok":false,"reason":"write"}
	file.store_buffer(MAGIC.to_ascii_buffer());file.store_64(payload.size());file.store_buffer(payload.compress(FileAccess.COMPRESSION_ZSTD));file.flush()
	var error:=file.get_error();var bytes:=file.get_length();file.close()
	# This generation/content-addressed name is normally new. A same-directory
	# rename publishes it atomically without starting a PowerShell per prefab.
	# Rebuilding an existing/corrupt product retains the replacement transaction.
	if error==OK:
		if not FileAccess.file_exists(path):error=DirAccess.rename_absolute(staged,path)
		else:error=preload("res://scripts/world3d/atomic_file.gd").publish(staged,path)
	return {"ok":error==OK,"path":path,"bytes":bytes,"sha256":digest,"version":version(),"meshes":keys.size()}
