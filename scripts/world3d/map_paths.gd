extends RefCounted
## External map directories. These paths are storage, not a map_ref.

const ArtPaths = preload("res://scripts/asset/art_paths.gd")
const WorldLocation = preload("res://scripts/world3d/world_location.gd")
static var reuse_path_access_enabled:=true
static var pooled_path_access_enabled:=true
const PATH_ACCESS_POOL_LIMIT:=8
static var _path_access_mutex:=Mutex.new()
static var _path_access_pool:Array[DirAccess]=[]


static func _take_path_access(profile:Variant=null)->DirAccess:
	if not reuse_path_access_enabled:return null
	var access:DirAccess
	if pooled_path_access_enabled:
		_path_access_mutex.lock()
		if not _path_access_pool.is_empty():access=_path_access_pool.pop_back()
		_path_access_mutex.unlock()
	if access==null:
		access=DirAccess.open(".")
		if profile!=null:profile.access_opens+=1
	elif profile!=null:profile.access_reuses+=1
	return access


static func _return_path_access(access:DirAccess)->void:
	if access==null or not pooled_path_access_enabled:return
	# Only absolute is_link/dir_exists queries use these objects. Never change their
	# directory or share one concurrently. Keep no checked-path decisions:
	# every invocation still observes every required ancestor on disk.
	_path_access_mutex.lock()
	if _path_access_pool.size()<PATH_ACCESS_POOL_LIMIT:_path_access_pool.append(access)
	_path_access_mutex.unlock()


static func external_root() -> String:
	return ArtPaths.external_root()


static func allowed(value: String, content_root: String = "") -> bool:
	var base := (external_root() if content_root.is_empty() else content_root).replace("\\", "/").simplify_path().trim_suffix("/")
	var path:=_authority_path(value,base)
	if path.is_empty():return false
	var access:=_take_path_access()
	var result:=_check_ancestors(path,access,{})
	_return_path_access(access)
	return result


static func _authority_path(value:String,base:String)->String:
	if value.is_empty() or not value.is_absolute_path() or value.contains("://"): return ""
	for index in value.length():
		if value.unicode_at(index) == 0: return ""
	if base.is_empty(): return ""
	var path := value.replace("\\", "/").simplify_path().trim_suffix("/")
	if path.to_lower() != base.to_lower() and not path.to_lower().begins_with(base.to_lower() + "/"): return ""
	return path


static func allowed_many(values:Array,content_root:String="",profile:Variant=null)->bool:
	# Map and its adjacent resource directory share all parent checks. Reuse
	# only within this synchronous call; post-IO callers get a fresh observation.
	if values.is_empty():return true
	var base:=(external_root() if content_root.is_empty() else content_root).replace("\\","/").simplify_path().trim_suffix("/")
	var paths:Array[String]=[]
	for value:Variant in values:
		if not value is String:return false
		var path:=_authority_path(value,base)
		if path.is_empty():return false
		paths.append(path)
	if profile!=null:profile.assign({"access_opens":0,"access_reuses":0,"link_checks":0,"reused_ancestors":0})
	var access:=_take_path_access(profile)
	var checked:Dictionary={}
	var result:=true
	for path:String in paths:
		if not _check_ancestors(path,access,checked,profile):
			result=false;break
	_return_path_access(access)
	return result


static func _check_ancestors(path:String,access:DirAccess,checked:Dictionary,profile:Variant=null)->bool:
	for i in 128:
		var parent := path.get_base_dir()
		if parent == path or path.is_empty(): break
		if checked.has(path):
			if profile!=null:profile.reused_ancestors+=1
			return true
		if profile!=null:profile.link_checks+=1
		if access!=null:
			if access.is_link(path):return false
		else:
			var directory := DirAccess.open(parent)
			if profile!=null:profile.access_opens+=1
			if directory != null and directory.is_link(path.get_file()): return false
		checked[path]=true
		path = parent
	return true


static func map_directory(pack_id: String, map_id: String) -> String:
	if not WorldLocation.id_ok(pack_id) or not WorldLocation.id_ok(map_id):
		push_error("World map id must be letters, digits, or underscore")
		return ""
	var root := external_root()
	if root.is_empty():
		return ""
	return _confine(root, root.path_join("packs").path_join(pack_id).path_join("maps").path_join(map_id))


static func cache_directory(name: String) -> String:
	if not WorldLocation.id_ok(name):
		push_error("World cache name must be letters, digits, or underscore")
		return ""
	var root := external_root()
	if root.is_empty():
		return ""
	return _confine(root, root.path_join("cache").path_join("world3d").path_join(name))


static func _confine(root: String, candidate: String) -> String:
	var base := root.replace("\\", "/").simplify_path().trim_suffix("/")
	var path := candidate.replace("\\", "/").simplify_path().trim_suffix("/")
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")
	if path == project or path.to_lower().begins_with(project.to_lower() + "/"):
		push_error("World files must stay outside the Godot project")
		return ""
	if path != base and not path.to_lower().begins_with(base.to_lower() + "/"):
		push_error("World path escaped the content root")
		return ""
	return path
