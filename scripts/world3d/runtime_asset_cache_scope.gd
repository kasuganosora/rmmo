extends RefCounted
## Runtime templates follow map lifetime, including off-tree load/rollback roots.
## Weak registrations add no resource owner and survive temporary tree handoff.
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const META:="runtime_asset_cache_scope"
static var _scopes:Dictionary={}
var _templates:Dictionary={}
var _identity:int
static func claim(map_root:Node,path:String)->void:
	if not is_instance_valid(map_root) or not Assets.has_cached_scene(path):return
	var scope:RefCounted=map_root.get_meta(META) if map_root.has_meta(META) else null
	if scope==null:
		scope=load("res://scripts/world3d/runtime_asset_cache_scope.gd").new()
		scope._identity=scope.get_instance_id();_scopes[scope._identity]=weakref(scope)
		map_root.set_meta(META,scope)
	var previous:WeakRef=scope._templates.get(path)
	if previous!=null and previous.get_ref()==Assets._scenes[path]:return
	scope._templates[path]=weakref(Assets._scenes[path])
func release(path:String)->bool:return _release_template(_templates,_identity,path)
static func _release_template(templates:Dictionary,identity:int,path:String)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.runtime_asset_cache_scope._release_template") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var reference:WeakRef=templates.get(path)
	if reference==null:return false
	templates.erase(path)
	var expected:PackedScene=reference.get_ref()
	if expected==null or Assets._scenes.get(path)!=expected:return false
	for id:int in _scopes.keys():
		if id==identity:continue
		var other:RefCounted=_scopes[id].get_ref()
		if other==null:_scopes.erase(id);continue
		var retained:WeakRef=other._templates.get(path)
		if retained!=null and retained.get_ref()==expected:return false
	if Assets._scenes.get(path)!=expected:return false
	return Assets.evict_cached_scene(path)
func _notification(what:int)->void:
	if what!=NOTIFICATION_PREDELETE:return
	_scopes.erase(_identity)
	for path:String in _templates.keys():_release_template(_templates,_identity,path)
