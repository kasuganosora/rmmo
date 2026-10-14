extends SceneTree
## Headless regression for isolated HTTP fixtures: opening a map outside a
## registered resource pack clears the editor's current Library object in-place.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Editor=preload("res://scripts/world_editor/world_editor.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failed:=0

func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok:failed+=1

func run()->void:
	var directory:=Paths.cache_directory("guild_catalog_scope_fixture_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory+"/assets")
	var path:=directory+"/assets/library.json"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify([{"label":"fixture_a","asset_path":"a.glb"},{"label":"fixture_b","asset_path":"b.glb"}]))
	file.close()
	var catalog_sha:=FileAccess.get_sha256(path)
	var imported:=Library.new(directory+"/assets")
	var editor:=Editor.new()
	editor._path=directory+"/map.gltf"
	editor._assets=imported
	check(imported.entries.size()==2,"fixture persisted catalog loaded")
	editor._load_asset_scope()
	check(imported.entries.is_empty(),"actual outside-pack open clears shared Library object")
	check(FileAccess.get_sha256(path)==catalog_sha,"scope refresh does not mutate persisted catalog")
	for cycle in 3:
		editor._assets=Library.new(imported.directory)
		editor._shared_assets=[]
		check(editor.asset_items("fixture_").size()==2,"HTTP catalog reload survives open cycle "+str(cycle))
		editor._load_asset_scope()
	check(FileAccess.get_sha256(path)==catalog_sha,"repeated scope refresh preserves catalog bytes")
	editor.free()
	print("GUILD_CATALOG_SCOPE_FIXTURE failures=",failed)
	quit(0 if failed==0 else 1)
