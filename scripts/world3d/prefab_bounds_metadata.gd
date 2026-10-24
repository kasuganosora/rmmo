extends RefCounted
## A compact, model-local observation for spatial classification. Index rebuilds
## need these bounds, not every frozen mesh/face array. Geometry still prepares
## normally when demanded. Entries are keyed by authored immutable content SHA.
const House=preload("res://scripts/world3d/house_prefab.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const LIMIT:=4*1024*1024
const MAX_ENTRIES:=16384
static var disk_cache_enabled:=true
var _root:=""
var _path:=""
var _values:Dictionary={}
var _mutex:=Mutex.new()
var _dirty:=false
var hits:=0
var misses:=0
func _init(root:String="")->void:
	_root=root
	if root.is_empty() or not disk_cache_enabled:return
	var hashes:Array=[Engine.get_version_info().hash]
	for name:String in ["prefab_bounds_metadata","house_prefab","prefab_binary_cache","ground_cpu_mesh"]:hashes.append(FileAccess.get_sha256("res://scripts/world3d/"+name+".gd"))
	_path=root.path_join("cache/world3d/prefab_bounds").path_join(str(hashes).sha256_text()+".bin")
	if not Paths.allowed(_path,root):_path="";return
	var file:=FileAccess.open(_path,FileAccess.READ)
	if file==null or file.get_length()<4 or file.get_length()>LIMIT:return
	var value:Variant=bytes_to_var(file.get_buffer(file.get_length()))
	if value is Dictionary and value.size()<=MAX_ENTRIES:_values=value
func bounds(value:Dictionary)->Dictionary:
	var key:String=value.sha256;var length:int=int(value.length)
	_mutex.lock()
	var previous:Variant=_values.get(key)
	if previous is Dictionary and previous.get("length")==length and previous.get("bounds") is AABB:
		var box:AABB=previous.bounds
		if box.position.is_finite() and box.size.is_finite() and box.size.x>=0 and box.size.y>=0 and box.size.z>=0:
			hits+=1;_mutex.unlock();return {"known":true,"bounds":box}
	misses+=1;_mutex.unlock()
	var result:=House.local_bounds(value)
	if result.known:
		_mutex.lock()
		if _values.size()<MAX_ENTRIES or _values.has(key):_values[key]={"length":length,"bounds":result.bounds};_dirty=true
		_mutex.unlock()
	return result
func save()->void:
	# Called only after classification workers have joined. Concurrent map opens
	# may publish an older subset; that causes future misses, never wrong bounds.
	if not _dirty or _path.is_empty() or not Paths.allowed(_path,_root):return
	var bytes:=var_to_bytes(_values)
	if bytes.size()>LIMIT or DirAccess.make_dir_recursive_absolute(_path.get_base_dir())!=OK:return
	var temporary:=_path+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return
	file.store_buffer(bytes);file.flush();var error:=file.get_error();file.close()
	if error!=OK or DirAccess.rename_absolute(temporary,_path)!=OK:DirAccess.remove_absolute(temporary)
