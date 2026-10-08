extends RefCounted
## Immutable authored CPU definitions. No models/images are loaded or exported.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const FIELDS=["uuid","position","rotation","size"]
const STATE_FIELDS=["building","fortification","fixture","event","editor_group","editor_group_name","editor_name","editor_hidden","editor_locked"]
const MAGIC="RMMORES1"
const MAX_RAW_BYTES=64*1024*1024
const MAX_FILE_BYTES=65*1024*1024
const MAX_RECORDS=100000
const CACHE_BYTES=32*1024*1024
const IDENTITY_CACHE_ENTRIES=16384
static var _cache:Dictionary={}
static var _cache_size:=0
# Metadata only: no mutable definitions, raw payloads, paths, or compressed
# payloads. Eviction of the large hot cache does not discard content identity.
static var _identities:Dictionary={}
static var _mutex:=Mutex.new()
static var _serial:=0
static func _temporary(prefix:String)->String:
	while true:
		_mutex.lock();_serial+=1;var serial:=_serial;_mutex.unlock()
		var value:String=prefix+".%d.%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec(),serial]
		if not FileAccess.file_exists(value) and not DirAccess.dir_exists_absolute(value):return value
	return ""

static func _fail(reason:String,error:int=ERR_INVALID_DATA)->Dictionary:
	return {"ok":false,"error":error,"reason":reason,"records":[],"dependencies":{},"resources_written":0,"resources_reused":0,"bytes_written":0}
static func _sha(bytes:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes)
	return context.finish().hex_encode()
static func _digest(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for character in value:
		if not character in "0123456789abcdef":return false
	return true
static func _integer(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value))
static func _base(path:String,content_root:String)->bool:
	return path.get_extension().to_lower()=="gltf" and not path.get_file().contains("%") and Paths.allowed(path,content_root) and Paths.allowed(path+".resources",content_root)
static func _location(uri:Variant,digest:Variant,path:String,content_root:String)->String:
	if not _base(path,content_root) or not _digest(digest) or not uri is String:return ""
	if uri!=path.get_file()+".resources/"+digest+".rmres":return ""
	var result:=path.get_base_dir().path_join(uri)
	return result if Paths.allowed(result,content_root) else ""
static func _path_batch(path:String,content_root:String)->Dictionary:
	# Every resource is a strict direct child of this one directory. Validate
	# the entire ancestor chain once, then each unique leaf without reopening
	# all ancestors. This context never survives a single public API call.
	if not _base(path,content_root):return {}
	return {"path":path,"root":content_root,"folder":path+".resources","directory":DirAccess.open(path+".resources"),"leaves":{}}
static func _batch_leaf(context:Dictionary,leaf:String)->bool:
	if context.is_empty() or context.directory==null or leaf.is_empty() or leaf.get_file()!=leaf or leaf.contains("\\") or leaf.contains(":"):return false
	if not context.leaves.has(leaf):
		if context.directory.is_link(leaf):return false
		context.leaves[leaf]=true
	return true
static func _batch_location(context:Dictionary,uri:Variant,digest:Variant)->String:
	if context.is_empty() or not _digest(digest) or not uri is String:return ""
	var leaf:String=digest+".rmres"
	if uri!=context.path.get_file()+".resources/"+leaf or not _batch_leaf(context,leaf):return ""
	return context.folder.path_join(leaf)
static func _finish_paths(context:Dictionary)->bool:
	# Reopen and repeat authority checks after IO, including leaves, so a
	# cached path decision cannot bless a directory or file replaced by a link.
	if context.is_empty() or not _base(context.path,context.root):return false
	var directory:=DirAccess.open(context.folder)
	if directory==null:return context.leaves.is_empty()
	for leaf in context.leaves:
		if directory.is_link(leaf):return false
	return true
static func _shape(record:Variant,compact:bool=false)->bool:
	if not record is Dictionary or not record.get("uuid") is String or record.uuid.is_empty() or record.uuid.length()>1024:return false
	for index in record.uuid.length():
		if record.uuid.unicode_at(index)==0:return false
	for field in ["position","rotation","size"]:
		var value:Variant=record.get(field)
		if not value is Array or value.size()!=3:return false
		for number in value:
			if not (number is int or number is float) or not is_finite(float(number)):return false
			if field=="size" and float(number)<=0:return false
	if compact:
		if record.size()!=6 or not record.get("rmmo_ref") is Dictionary or not _state_shape(record.get("rmmo_state")):return false
	elif record.has("rmmo_ref") or record.has("rmmo_state"):return false
	return true
static func _state_shape(value:Variant)->bool:
	if not value is Dictionary:return false
	for field in value:
		if not field in STATE_FIELDS:return false
	return _json_safe(value,[],[2000000])
static func _json_safe(value:Variant,ancestors:Array,budget:Array)->bool:
	budget[0]-=1
	if budget[0]<0 or ancestors.size()>64:return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL:return true
		TYPE_INT:return value>=-9007199254740991 and value<=9007199254740991
		TYPE_FLOAT:return is_finite(value)
		TYPE_STRING:return value.length()<=MAX_RAW_BYTES
		TYPE_ARRAY,TYPE_DICTIONARY:
			for parent in ancestors:
				if is_same(parent,value):return false
			if value is Array and value.is_typed() and value.get_typed_builtin()==TYPE_OBJECT:return false
			if value is Dictionary and value.is_typed() and (value.get_typed_key_builtin()==TYPE_OBJECT or value.get_typed_value_builtin()==TYPE_OBJECT):return false
			ancestors.append(value)
			if value is Dictionary:
				for key in value:
					if not (key is String or key is StringName) or str(key).length()>MAX_RAW_BYTES or not _json_safe(value[key],ancestors,budget):ancestors.pop_back();return false
			else:
				for item in value:
					if not _json_safe(item,ancestors,budget):ancestors.pop_back();return false
			ancestors.pop_back();return true
		_:return false
static func _json_copy(value:Variant)->Variant:
	# Called only after validation. Rebuild containers to normalize StringName
	# keys and avoid retaining typed containers or mutable authoring references.
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=_json_copy(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(_json_copy(item))
		return result
	return value
static func _safe(value:Variant,ancestors:Array,budget:Array)->bool:
	budget[0]-=1
	if budget[0]<0 or ancestors.size()>64:return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_INT:return true
		TYPE_FLOAT:return is_finite(value)
		# The serialized byte cap below is authoritative; a 24 MB ASCII prefab
		# is legal and must not be rejected by a worst-case UTF-32 estimate.
		TYPE_STRING,TYPE_STRING_NAME:return value.length()<=MAX_RAW_BYTES
		TYPE_OBJECT,TYPE_CALLABLE,TYPE_SIGNAL,TYPE_RID:return false
		TYPE_ARRAY,TYPE_DICTIONARY:
			for parent in ancestors:
				if is_same(parent,value):return false
			if value is Array and value.is_typed() and value.get_typed_builtin()==TYPE_OBJECT:return false
			if value is Dictionary and value.is_typed() and (value.get_typed_key_builtin()==TYPE_OBJECT or value.get_typed_value_builtin()==TYPE_OBJECT):return false
			ancestors.append(value)
			if value is Dictionary:
				for key in value:
					if not (key is String or key is StringName) or not _safe(key,ancestors,budget) or not _safe(value[key],ancestors,budget):ancestors.pop_back();return false
			else:
				for item in value:
					if not _safe(item,ancestors,budget):ancestors.pop_back();return false
			ancestors.pop_back();return true
		TYPE_PACKED_STRING_ARRAY:
			for item in value:
				if not _safe(item,ancestors,budget):return false
			return true
		_:
			# Math and packed scalar/vector variants cannot contain executable Objects.
			return typeof(value) in [TYPE_VECTOR2,TYPE_VECTOR2I,TYPE_RECT2,TYPE_RECT2I,TYPE_VECTOR3,TYPE_VECTOR3I,TYPE_TRANSFORM2D,TYPE_VECTOR4,TYPE_VECTOR4I,TYPE_PLANE,TYPE_QUATERNION,TYPE_AABB,TYPE_BASIS,TYPE_TRANSFORM3D,TYPE_PROJECTION,TYPE_COLOR,TYPE_NODE_PATH,TYPE_PACKED_BYTE_ARRAY,TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_VECTOR2_ARRAY,TYPE_PACKED_VECTOR3_ARRAY,TYPE_PACKED_COLOR_ARRAY,TYPE_PACKED_VECTOR4_ARRAY]
static func _definition(record:Dictionary)->Dictionary:
	var value:=record.duplicate()
	for field in FIELDS+STATE_FIELDS:value.erase(field)
	return value
static func _remember_identity(raw_sha:String,raw_length:int,file_sha:String,file_length:int)->void:
	_mutex.lock()
	# Dictionary insertion order supplies a bounded LRU of small identities.
	_identities.erase(raw_sha)
	if _identities.size()>=IDENTITY_CACHE_ENTRIES:_identities.erase(_identities.keys()[0])
	_identities[raw_sha]={"raw_length":raw_length,"sha256":file_sha,"length":file_length}
	_mutex.unlock()
static func _identity(raw_sha:String,raw_length:int)->Dictionary:
	_mutex.lock()
	var result:Dictionary=_identities.get(raw_sha,{})
	if not result.is_empty() and result.raw_length==raw_length:
		_identities.erase(raw_sha);_identities[raw_sha]=result
		result=result.duplicate()
	else:result={}
	_mutex.unlock()
	return result
static func _compressed(raw:PackedByteArray)->PackedByteArray:
	var bytes:=MAGIC.to_ascii_buffer();bytes.resize(16);bytes.encode_u64(8,raw.size());bytes.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return bytes
static func _encode(definition:Dictionary)->Dictionary:
	if not _safe(definition,[],[2000000]):return _fail("Unsafe or excessive resource definition")
	_mutex.lock()
	var has_hot_entries:=not _cache.is_empty()
	_mutex.unlock()
	var key:int=hash(definition) if has_hot_entries else 0
	if has_hot_entries:
		_mutex.lock()
		for entry:Dictionary in _cache.get(key,[]):
			if definition==entry.definition:
				var result:Dictionary={"ok":true,"bytes":entry.bytes,"sha256":entry.sha256,"length":entry.bytes.size(),"cache_hit":true,"identity_hit":false,"serialized_raw_bytes":0,"encoded_raw_bytes":0};_mutex.unlock();return result
		_mutex.unlock()
	# var_to_bytes / bytes_to_var exclude Objects; never use *_with_objects.
	var raw:=var_to_bytes(definition)
	if raw.is_empty() or raw.size()>MAX_RAW_BYTES:return _fail("Resource definition exceeds raw size limit")
	# Rehash the complete current serialization, never a 32-bit Variant hash or
	# an mtime. Nested changes cannot borrow an old compressed-file identity.
	var raw_sha:=_sha(raw)
	var known:=_identity(raw_sha,raw.size())
	if not known.is_empty():
		return {"ok":true,"bytes":PackedByteArray(),"sha256":known.sha256,"length":known.length,"cache_hit":true,"identity_hit":true,"serialized_raw_bytes":raw.size(),"encoded_raw_bytes":0,"raw_sha256":raw_sha,"raw_length":raw.size(),"definition":definition}
	var bytes:=_compressed(raw)
	if bytes.size()<=16 or bytes.size()>MAX_FILE_BYTES:return _fail("Resource exceeds file size limit")
	var digest:=_sha(bytes)
	_remember_identity(raw_sha,raw.size(),digest,bytes.size())
	if raw.size()+bytes.size()<=CACHE_BYTES:
		if not has_hot_entries:key=hash(definition)
		_mutex.lock()
		if _cache_size+raw.size()+bytes.size()>CACHE_BYTES:_cache.clear();_cache_size=0
		if not _cache.has(key):_cache[key]=[]
		_cache[key].append({"definition":definition.duplicate(true),"bytes":bytes,"sha256":digest})
		_cache_size+=raw.size()+bytes.size();_mutex.unlock()
	return {"ok":true,"bytes":bytes,"sha256":digest,"length":bytes.size(),"cache_hit":false,"identity_hit":false,"serialized_raw_bytes":raw.size(),"encoded_raw_bytes":raw.size()}
static func _materialize(encoded:Dictionary)->Dictionary:
	if not encoded.bytes.is_empty():return {"ok":true,"bytes":encoded.bytes,"encoded_raw_bytes":0,"serialized_raw_bytes":0}
	# Save As or a missing destination has no authoritative file to reuse.
	# Rebuild only that resource; changed in-flight input fails explicitly.
	if not _safe(encoded.definition,[],[2000000]):return _fail("Resource definition changed before publication")
	var raw:=var_to_bytes(encoded.definition)
	if raw.size()!=encoded.raw_length or _sha(raw)!=encoded.raw_sha256:return _fail("Resource definition changed before publication")
	var bytes:=_compressed(raw)
	if bytes.size()!=encoded.length or _sha(bytes)!=encoded.sha256:return _fail("Rebuilt resource differs from verified content identity")
	return {"ok":true,"bytes":bytes,"encoded_raw_bytes":raw.size(),"serialized_raw_bytes":raw.size()}
static func _read(file_path:String,digest:String,length:int=-1,decode:bool=true)->Dictionary:
	var trace_started:=Time.get_ticks_usec()
	var file:=FileAccess.open(file_path,FileAccess.READ)
	if file==null:return _fail("Resource is missing or unreadable",ERR_FILE_CANT_READ)
	var size:=file.get_length()
	if size<=16 or size>MAX_FILE_BYTES or (length>=0 and size!=length):return _fail("Resource length mismatch")
	var bytes:=file.get_buffer(size)
	if bytes.size()!=size or _sha(bytes)!=digest:return _fail("Resource content SHA mismatch")
	if preload("res://scripts/world3d/load_trace.gd").enabled:preload("res://scripts/world3d/load_trace.gd").elapsed("resource.read_sha",trace_started,{"bytes":size,"decode":decode})
	if bytes.slice(0,8).get_string_from_ascii()!=MAGIC:return _fail("Invalid resource envelope")
	var raw_length:int=bytes.decode_u64(8)
	if raw_length<=0 or raw_length>MAX_RAW_BYTES:return _fail("Invalid resource decompression length")
	if not decode:return {"ok":true,"error":OK,"length":size}
	var decode_started:=Time.get_ticks_usec()
	var raw:=bytes.slice(16).decompress(raw_length,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=raw_length:return _fail("Resource decompression failed")
	var definition:Variant=bytes_to_var(raw)
	if preload("res://scripts/world3d/load_trace.gd").enabled:preload("res://scripts/world3d/load_trace.gd").elapsed("resource.decompress_variant",decode_started,{"bytes":raw_length})
	var safe_started:=Time.get_ticks_usec()
	if not definition is Dictionary or not _safe(definition,[],[2000000]):return _fail("Unsafe or invalid decoded resource")
	for field in FIELDS+STATE_FIELDS+["rmmo_ref","rmmo_state"]:
		if definition.has(field):return _fail("Definition overrides instance identity or transform")
	if preload("res://scripts/world3d/load_trace.gd").enabled:preload("res://scripts/world3d/load_trace.gd").elapsed("resource.safety",safe_started)
	# Only fully SHA-verified, decoded and safe CPU data seeds a cold-open
	# identity. No path or cached result replaces the next disk verification.
	var identity_started:=Time.get_ticks_usec()
	_remember_identity(_sha(raw),raw.size(),digest,size)
	if preload("res://scripts/world3d/load_trace.gd").enabled:preload("res://scripts/world3d/load_trace.gd").elapsed("resource.identity_sha",identity_started)
	return {"ok":true,"error":OK,"definition":definition,"length":size}

static func _publish(staged:Array,folder:String)->Dictionary:
	if staged.is_empty():return {"error":OK,"written":{}}
	# A single helper per transaction, not one process per resource. File.Move
	# has no replacement option, unlike Godot's Windows rename implementation.
	if OS.get_name()!="Windows":return {"error":ERR_UNAVAILABLE,"written":{}}
	var plan:=_temporary(folder.path_join(".publish"))
	var file:=FileAccess.open(plan,FileAccess.WRITE)
	if file==null:return {"error":FileAccess.get_open_error(),"written":{}}
	file.store_string(JSON.stringify(staged));file.close()
	var command:="$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $items=Get-Content -LiteralPath '%s' -Raw -Encoding UTF8 | ConvertFrom-Json; $written=@(); foreach($item in $items) { if(-not [IO.File]::Exists($item.destination)) { try { [IO.File]::Move($item.staged,$item.destination); $written+=$item.sha256 } catch { if(-not [IO.File]::Exists($item.destination)) { throw } } } }; ConvertTo-Json -InputObject @($written) -Compress"%plan.replace("'","''")
	var output:Array=[];var code:=OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command",command],output,true,false)
	DirAccess.remove_absolute(plan)
	var written:Dictionary={}
	if code!=0:return {"error":ERR_FILE_CANT_WRITE,"written":written}
	var parsed:Variant=JSON.parse_string("".join(output))
	if not parsed is Array:return {"error":ERR_FILE_CANT_WRITE,"written":written}
	for destination in parsed:written[str(destination)]=true
	return {"error":OK,"written":written}

static func write_records(records:Array,path:String,content_root:String,progress:Callable=Callable())->Dictionary:
	if not _base(path,content_root) or records.size()>MAX_RECORDS:return _fail("Invalid map path or record count")
	var ids:Dictionary={}
	# Validate every basic shape before creating any files.
	for record in records:
		if not _shape(record) or ids.has(record.uuid):return _fail("Invalid record shape or duplicate UUID")
		for field in STATE_FIELDS:
			if record.has(field) and not _json_safe(record[field],[],[2000000]):return _fail("Instance state is not losslessly JSON-compatible")
		ids[record.uuid]=true
	var compact:Array=[];var resources:Dictionary={};var dependencies:Dictionary={}
	var cache_hits:=0;var cache_misses:=0;var encoded_raw_bytes:=0;var verified_bytes:=0
	var identity_hits:=0;var serialized_raw_bytes:=0;var compression_count:=0
	var encoding_start:=Time.get_ticks_usec()
	for record:Dictionary in records:
		var encoded:=_encode(_definition(record))
		if not encoded.ok:return encoded
		if encoded.cache_hit:cache_hits+=1
		else:cache_misses+=1
		identity_hits+=int(encoded.identity_hit)
		serialized_raw_bytes+=encoded.serialized_raw_bytes
		encoded_raw_bytes+=encoded.encoded_raw_bytes
		compression_count+=int(encoded.encoded_raw_bytes>0)
		var uri:String=path.get_file()+".resources/"+encoded.sha256+".rmres"
		var item:Dictionary={}
		for field in FIELDS:item[field]=record[field].duplicate(true) if record[field] is Array else record[field]
		item.rmmo_state={}
		for field in STATE_FIELDS:
			if record.has(field):item.rmmo_state[field]=_json_copy(record[field])
		item.rmmo_ref={"version":1,"uri":uri,"sha256":encoded.sha256,"length":encoded.length}
		compact.append(item);resources[uri]=encoded;dependencies[uri]=encoded.sha256
	var encoding_ms:=(Time.get_ticks_usec()-encoding_start)/1000.0
	var folder:=path+".resources"
	if not _base(path,content_root):return _fail("Resource ancestors changed before write")
	var err:=DirAccess.make_dir_recursive_absolute(folder)
	if err!=OK:return _fail("Cannot create resource directory",err)
	var paths:=_path_batch(path,content_root)
	if paths.is_empty():return _fail("Resource directory changed or escaped content root")
	var staged:Array=[];var written:=0;var reused:=0;var bytes_written:=0
	for uri:String in resources:
		var encoded:Dictionary=resources[uri];var destination:=_batch_location(paths,uri,encoded.sha256)
		if destination.is_empty():err=ERR_INVALID_DATA;break
		if FileAccess.file_exists(destination):
			if not _read(destination,encoded.sha256,encoded.length,false).ok:err=ERR_FILE_CORRUPT;break
			verified_bytes+=encoded.length
			reused+=1;continue
		var materialize_start:=Time.get_ticks_usec()
		var materialized:=_materialize(encoded)
		encoding_ms+=(Time.get_ticks_usec()-materialize_start)/1000.0
		if not materialized.ok:err=materialized.error;break
		encoded_raw_bytes+=materialized.encoded_raw_bytes
		serialized_raw_bytes+=materialized.serialized_raw_bytes
		compression_count+=int(materialized.encoded_raw_bytes>0)
		var temporary:=_temporary(destination)
		if not _batch_leaf(paths,temporary.get_file()):err=ERR_INVALID_DATA;break
		var file:=FileAccess.open(temporary,FileAccess.WRITE)
		if file==null:err=FileAccess.get_open_error();break
		staged.append({"staged":temporary,"destination":destination,"sha256":encoded.sha256,"length":encoded.length})
		file.store_buffer(materialized.bytes);file.flush();err=file.get_error();file.close()
		if err!=OK:break
		if FileAccess.get_sha256(temporary)!=encoded.sha256:err=ERR_FILE_CORRUPT;break
		verified_bytes+=encoded.length
		bytes_written+=encoded.length
	var publication:Dictionary={"written":{}}
	if err==OK and not _finish_paths(paths):err=ERR_INVALID_DATA
	if err==OK:publication=_publish(staged,folder);err=publication.error
	if err==OK and not _finish_paths(paths):err=ERR_INVALID_DATA
	if err==OK:
		for entry:Dictionary in staged:
			if not _read(entry.destination,entry.sha256,entry.length,false).ok:err=ERR_FILE_CORRUPT;break
			verified_bytes+=entry.length
			if publication.written.has(entry.sha256):written+=1
			else:reused+=1
	var paths_still_safe:=_finish_paths(paths)
	if not paths_still_safe:err=ERR_INVALID_DATA
	if paths_still_safe:
		for entry:Dictionary in staged:
			if FileAccess.file_exists(entry.staged):DirAccess.remove_absolute(entry.staged)
	if err!=OK:return _fail("Immutable resource publication or verification failed",err)
	if progress.is_valid():progress.call("resources",records.size(),records.size())
	_mutex.lock();var identity_count:=_identities.size();_mutex.unlock()
	return {"ok":true,"error":OK,"records":compact,"dependencies":dependencies,"resources_written":written,"resources_reused":reused,"bytes_written":bytes_written,"encoding_cache_hits":cache_hits,"encoding_cache_misses":cache_misses,"encoded_raw_bytes":encoded_raw_bytes,"encoding_ms":encoding_ms,"verified_bytes":verified_bytes,"identity_cache_hits":identity_hits,"serialized_raw_bytes":serialized_raw_bytes,"compression_count":compression_count,"identity_cache_entries":identity_count}

static func read_records(records:Array,path:String,content_root:String)->Dictionary:
	var paths:=_path_batch(path,content_root)
	if paths.is_empty() or records.size()>MAX_RECORDS:return _fail("Invalid map path or record count")
	var result:Array=[];var ids:Dictionary={};var decoded:Dictionary={};var dependencies:Dictionary={}
	for record in records:
		if not _shape(record,true) or ids.has(record.uuid):return _fail("Invalid compact record or duplicate UUID")
		ids[record.uuid]=true
		var ref:Dictionary=record.rmmo_ref
		if ref.size()!=4 or not _integer(ref.get("version")) or int(ref.version)!=1 or not _integer(ref.get("length")) or ref.length<=16 or ref.length>MAX_FILE_BYTES:return _fail("Invalid resource reference")
		var location:=_batch_location(paths,ref.get("uri"),ref.get("sha256"))
		if location.is_empty():return _fail("Resource reference escapes adjacent directory")
		# The per-call cache follows a fresh complete file verification. It is
		# never authoritative across opens, and definitions are copied per instance.
		if not decoded.has(ref.uri):
			var data:=_read(location,ref.sha256,int(ref.length))
			if not data.ok:return data
			decoded[ref.uri]=data
		if decoded[ref.uri].length!=int(ref.length):return _fail("Conflicting resource lengths")
		dependencies[ref.uri]=ref.sha256
		var copy_started:=Time.get_ticks_usec()
		var hydrated:Dictionary=decoded[ref.uri].definition.duplicate(true)
		for field in FIELDS:hydrated[field]=record[field].duplicate(true) if record[field] is Array else record[field]
		for field in record.rmmo_state:hydrated[str(field)]=_json_copy(record.rmmo_state[field])
		result.append(hydrated)
		if preload("res://scripts/world3d/load_trace.gd").enabled:preload("res://scripts/world3d/load_trace.gd").elapsed("resource.instance_copy",copy_started)
	if not _finish_paths(paths):return _fail("Resource paths changed during read")
	return {"ok":true,"error":OK,"reason":"","records":result,"dependencies":dependencies}

static func verify_dependencies(dependencies:Dictionary,path:String,content_root:String)->bool:
	var paths:=_path_batch(path,content_root)
	if paths.is_empty() or dependencies.size()>MAX_RECORDS:return false
	for uri in dependencies:
		var location:=_batch_location(paths,uri,dependencies[uri])
		if location.is_empty() or not _read(location,dependencies[uri],-1,false).ok:return false
	return _finish_paths(paths)
