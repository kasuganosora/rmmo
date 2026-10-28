extends SceneTree
## Verify the actual autoload root is overridden before _ready creates paths.
## Launch with private APPDATA/LOCALAPPDATA already set by the parent process.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Writer=preload("res://scripts/world3d/compiled_asset_cache.gd")
const REVIEW="D:/code/rmmo_runtime/review_artifacts"
var folder:=""
var checks:=0
var failed:=0
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").replace("\\","/").simplify_path()
	if folder.is_empty() or not Paths.allowed(folder,REVIEW) or DirAccess.dir_exists_absolute(folder):printerr("new external --output root required");quit(2);return
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:printerr("cannot create root");quit(2);return
	var manager:=root.get_node_or_null("AssetManager")
	check(manager!=null and not manager.is_node_ready(),"actual AssetManager exists before _ready")
	if manager==null:quit(1);return
	manager.content_root_override=folder
	run.call_deferred()
func run()->void:
	var manager:=root.get_node("AssetManager")
	check(manager.is_node_ready() and manager.content_root()==folder,"AssetManager uses fixture root at _ready")
	check(DirAccess.dir_exists_absolute(folder.path_join("cache/downloads")) and DirAccess.dir_exists_absolute(folder.path_join("packs/default").get_base_dir()),"autoload created directories inside fixture")
	check(Paths.external_root()==folder,"map paths resolve the same fixture root")
	var map:=folder.path_join("packs/default/maps/fixture/map.gltf")
	var model:=folder.path_join("packs/default/assets/fixture.glb")
	var index:=Index.cache_path(map,folder);var bundle:=Store.bundle_path(map,folder);var native:=Writer.index_path(model,folder)
	check(not index.is_empty() and Paths.allowed(index,folder),"dependency index path confined")
	check(not bundle.is_empty() and Paths.allowed(bundle,folder),"resource bundle path confined")
	check(not native.is_empty() and Paths.allowed(native,folder),"native index path confined")
	var user:=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path()
	var appdata:=OS.get_data_dir().replace("\\","/").simplify_path()
	var local:=OS.get_cache_dir().replace("\\","/").simplify_path()
	check(Paths.allowed(user,REVIEW) and Paths.allowed(appdata,REVIEW) and Paths.allowed(local,REVIEW),"user/data/cache directories confined by parent environment")
	print("ROOT_ISOLATION checks=",checks," failures=",failed," root=",folder," user=",user," appdata=",appdata," localappdata=",local)
	quit(0 if failed==0 else 1)
