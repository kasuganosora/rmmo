extends RefCounted
## Disposable exact CPU collision data. No Mesh, Material, PhysicsServer, scene
## or GPU access. A disk hit remains a PRIVATE candidate until the enclosing
## reference transaction completes its existing source + closure verification.
## Stream must only receive Product, never this reader's candidate Dictionary.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const VERSION="1"
const RULE="exact_local_source_v1"
const MAGIC="RMMOCP01"
const HEADER_BYTES=56
const MAX_META_BYTES=16384
const MAX_OUTPUT_BYTES=16*1024*1024
# Source faces are already charged to their geometry job. This additional
# lease covers binary copies/checksum/read/write workspace, not the source.
const WORKSPACE_BYTES=4*MAX_OUTPUT_BYTES+8*1024*1024
const MAX_SOURCES=8
const MAX_CACHE_BYTES=1024*1024*1024
static var enabled:=false # Exact-data experiment; retains the original entry gate.
static var _publish_mutex:=Mutex.new()

class Product extends RefCounted:
	var _kind:=""
	var _faces:=PackedVector3Array()
	var _box:=Vector3.ZERO
	var _identity:Dictionary={}
	var _sealed:=false
	func kind()->String:return _kind if _sealed else ""
	func faces()->PackedVector3Array:return _faces if _sealed else PackedVector3Array()
	func box_size()->Vector3:return _box if _sealed else Vector3.ZERO
	func identity()->Dictionary:return _identity.duplicate(true) if _sealed else {}
	func retained_bytes()->int:return _faces.size()*(24 if OS.has_feature("double") else 12)

static func _sha(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for ch in value:
		if ch not in "0123456789abcdef":return false
	return true

static func _cancelled(token:RefCounted)->bool:return token!=null and token.is_cancelled()
static func _worker()->bool:return OS.get_thread_caller_id()!=OS.get_main_thread_id()
static func directory(root:String)->String:return root.path_join("cache/world3d/collision_products_v1")
static func _digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()

static func generator()->String:
	var values:Array=[VERSION,RULE,Engine.get_version_info(),OS.has_feature("double")]
	for path:String in ["collision_product_cache.gd","house_prefab.gd","runtime_mesh_cache.gd","ground_cpu_mesh.gd","flat_terrain_collision.gd","terrain_collision_preparer.gd"]:
		values.append(FileAccess.get_sha256("res://scripts/world3d/"+path))
	return JSON.stringify(values).sha256_text()

static func identity(sources:Dictionary,selector:String,root:String)->Dictionary:
	if root.is_empty() or sources.is_empty() or sources.size()>MAX_SOURCES or selector.is_empty() or selector.length()>1024:return {}
	var keys:Array=sources.keys();keys.sort();var ordered:Dictionary={}
	for path:Variant in keys:
		if not path is String or not _sha(sources[path]) or not Paths.allowed(path,root):return {}
		ordered[path]=sources[path]
	return {"version":VERSION,"rule":RULE,"generator":generator(),"selector":selector,"sources":ordered}

static func _valid_identity(value:Dictionary,root:String)->bool:
	if value.size()!=5 or not value.get("sources") is Dictionary or not value.get("selector") is String:return false
	return value==identity(value.sources,value.selector,root)

static func path_for(value:Dictionary,root:String)->String:
	return directory(root).path_join(JSON.stringify(value).sha256_text()+".rmcp")

static func _miss(reason:String)->Dictionary:return {"ok":false,"reason":reason,"source_unverified":true}

static func read_candidate(value:Dictionary,root:String,token:RefCounted=null)->Dictionary:
	var began:=Time.get_ticks_usec()
	if not _worker():return _miss("worker_required")
	if _cancelled(token) or not _valid_identity(value,root):return _miss("identity_or_cancel")
	var path:=path_for(value,root)
	if not Paths.allowed(path,directory(root)):return _miss("path")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return _miss("absent")
	var length:int=file.get_length()
	if length<HEADER_BYTES or length>HEADER_BYTES+MAX_META_BYTES+MAX_OUTPUT_BYTES:return _miss("bounded_length")
	var header:=file.get_buffer(HEADER_BYTES)
	if header.size()!=HEADER_BYTES or header.slice(0,8).get_string_from_ascii()!=MAGIC or header.decode_u32(8)!=1:return _miss("header")
	var meta_length:int=header.decode_u32(12);var raw_length:int=header.decode_u64(16)
	if meta_length<=0 or meta_length>MAX_META_BYTES or raw_length<0 or raw_length>MAX_OUTPUT_BYTES or HEADER_BYTES+meta_length+raw_length!=length:return _miss("declared_length")
	var meta_bytes:=file.get_buffer(meta_length)
	var meta:Variant=JSON.parse_string(meta_bytes.get_string_from_utf8())
	if not meta is Dictionary or meta.size()!=4 or meta.get("identity")!=value or meta.get("kind") not in ["faces","box"]:return _miss("metadata")
	var stride:int=24 if OS.has_feature("double") else 12
	var count_value:Variant=meta.get("count")
	if not (count_value is int or count_value is float) or not is_finite(float(count_value)) or count_value!=floor(float(count_value)) or count_value<0 or count_value>MAX_OUTPUT_BYTES/stride:return _miss("count")
	var count_:int=int(count_value)
	if meta.kind=="faces" and (count_<=0 or count_%3!=0 or raw_length!=count_*stride):return _miss("face_length")
	if meta.kind=="box" and (count_!=0 or raw_length!=0):return _miss("box_length")
	if not meta.get("box") is Array or meta.box.size()!=3:return _miss("box")
	for number:Variant in meta.box:
		if not (number is int or number is float) or not is_finite(float(number)):return _miss("box")
	var box:=Vector3(meta.box[0],meta.box[1],meta.box[2])
	if meta.kind=="box" and (box.x<=0 or box.y<=0 or box.z<=0):return _miss("box")
	if meta.kind=="faces" and box!=Vector3.ZERO:return _miss("box")
	var raw:=file.get_buffer(raw_length);file.close()
	if raw.size()!=raw_length or _cancelled(token) or not Paths.allowed(path,directory(root)):return _miss("read_or_cancel")
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(meta_bytes)
	if not raw.is_empty():hash.update(raw)
	if hash.finish()!=header.slice(24,56):return _miss("checksum")
	var faces:=raw.to_vector3_array()
	for vertex:Vector3 in faces:
		if not vertex.is_finite():return _miss("nonfinite_faces")
	Trace.elapsed("collision_product.read",began,{"bytes":length,"selector":value.selector})
	return {"ok":true,"source_unverified":true,"identity":value.duplicate(true),"kind":meta.kind,"faces":faces,"box":box,"bytes":raw_length}

static func _seal_after_reference_validation(candidate:Dictionary,verified_sources:Dictionary)->Product:
	# Internal handoff ONLY: ChunkReferencePreparation calls this after its final
	# Store.verify_dependencies + map SHA transaction. A public prepared flag or
	# a disk filename cannot grant this authority; consumers require this type.
	if not candidate.get("ok",false) or candidate.get("source_unverified")!=true:return null
	var bound:Dictionary=candidate.get("identity",{}).get("sources",{})
	if bound.is_empty():return null
	for path:String in bound:
		if verified_sources.get(path)!=bound[path]:return null
	var product:=Product.new();product._kind=candidate.kind;product._faces=candidate.faces;product._box=candidate.box;product._identity=candidate.identity.duplicate(true);product._sealed=true
	return product

static func make_candidate(value:Dictionary,faces:PackedVector3Array,box:Vector3=Vector3.ZERO)->Dictionary:
	# Uses already owned CPU source geometry; no resource capture or GPU readback.
	var stride:int=24 if OS.has_feature("double") else 12
	if faces.size()*stride>MAX_OUTPUT_BYTES:return _miss("output_limit")
	if box!=Vector3.ZERO:
		if not faces.is_empty() or not box.is_finite() or box.x<=0 or box.y<=0 or box.z<=0:return _miss("box")
	elif faces.is_empty() or faces.size()%3!=0:return _miss("faces")
	for vertex:Vector3 in faces:
		if not vertex.is_finite():return _miss("nonfinite_faces")
	return {"ok":true,"source_unverified":true,"identity":value.duplicate(true),"kind":"box" if box!=Vector3.ZERO else "faces","faces":faces,"box":box,"bytes":faces.size()*stride}

static func store_validated(product:Product,root:String,admitted_workspace:int,token:RefCounted=null)->Dictionary:
	if not _worker() or product==null or not product._sealed:return _miss("worker_or_proof")
	return _store_bound_candidate(make_candidate(product._identity,product._faces,product._box),root,admitted_workspace,token)

static func _store_bound_candidate(candidate:Dictionary,root:String,admitted_workspace:int,token:RefCounted=null)->Dictionary:
	# Internal offline/Chunk writer. Its caller already read a SHA-verified rmres
	# definition. Persistence grants NO physics proof; the normal final source
	# transaction still runs after this optional IO, before sealing any product.
	var began:=Time.get_ticks_usec()
	if not _worker() or not candidate.get("ok",false):return _miss("worker_or_proof")
	if admitted_workspace<WORKSPACE_BYTES:return _miss("workspace_not_admitted")
	if _cancelled(token) or not _valid_identity(candidate.identity,root):return _miss("identity_or_cancel")
	var raw:PackedByteArray=candidate.faces.to_byte_array()
	if raw.size()>MAX_OUTPUT_BYTES:return _miss("output_limit")
	var meta:Dictionary={"identity":candidate.identity,"kind":candidate.kind,"count":candidate.faces.size(),"box":[candidate.box.x,candidate.box.y,candidate.box.z]}
	var meta_bytes:=JSON.stringify(meta).to_utf8_buffer()
	if meta_bytes.is_empty() or meta_bytes.size()>MAX_META_BYTES:return _miss("metadata_limit")
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(meta_bytes)
	if not raw.is_empty():hash.update(raw)
	var header:=PackedByteArray();header.resize(HEADER_BYTES)
	for at:int in 8:header[at]=MAGIC.to_ascii_buffer()[at]
	header.encode_u32(8,1);header.encode_u32(12,meta_bytes.size());header.encode_u64(16,raw.size())
	var checksum:=hash.finish()
	for at:int in 32:header[24+at]=checksum[at]
	var folder:=directory(root);var path:=path_for(candidate.identity,root)
	if not Paths.allowed(folder,root) or not Paths.allowed(path,folder) or DirAccess.make_dir_recursive_absolute(folder)!=OK:return _miss("cache_path")
	var temporary:=path+".%d.%d.%d.tmp"%[OS.get_process_id(),OS.get_thread_caller_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return _miss("write")
	file.store_buffer(header);file.store_buffer(meta_bytes);file.store_buffer(raw);file.flush()
	var valid:bool=file.get_error()==OK and file.get_position()==HEADER_BYTES+meta_bytes.size()+raw.size();file.close()
	if not valid or _cancelled(token) or not Paths.allowed(temporary,folder):DirAccess.remove_absolute(temporary);return _miss("write_or_cancel")
	_publish_mutex.lock()
	var disk_bytes:=0
	for name:String in DirAccess.get_files_at(folder):
		if not name.ends_with(".rmcp") or name==path.get_file():continue
		var existing_path:=folder.path_join(name)
		if not Paths.allowed(existing_path,folder):continue
		var existing:=FileAccess.open(existing_path,FileAccess.READ)
		if existing!=null:disk_bytes+=existing.get_length();existing.close()
	var err:int=ERR_OUT_OF_MEMORY
	if disk_bytes+HEADER_BYTES+meta_bytes.size()+raw.size()<=MAX_CACHE_BYTES and not _cancelled(token) and Paths.allowed(path,folder):
		err=Atomic.publish(temporary,path) if FileAccess.file_exists(path) else DirAccess.rename_absolute(temporary,path)
		if err==OK and FileAccess.file_exists(path+".previous"):DirAccess.remove_absolute(path+".previous")
	_publish_mutex.unlock()
	if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
	Trace.elapsed("collision_product.write",began,{"bytes":raw.size(),"selector":candidate.identity.selector,"ok":err==OK})
	return {"ok":err==OK,"reason":"" if err==OK else "publish_or_capacity","bytes":raw.size()}
