extends SceneTree
## External fixture: no GPU, no user content. Exercise the same library used
## by editor UI and 3D MCP, including targeted lookup and catalog listing.
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1;print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func write(path:String,name_:String)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"material":{"name":name_,"color":[1,1,1,1],"roughness":.9},"category":"fixture"}));file.close()
func run()->void:
	var test_root:=OS.get_environment("RMMO_MATERIAL_LIBRARY_TEST_ROOT")
	if test_root.is_empty() or not test_root.is_absolute_path() or not DirAccess.dir_exists_absolute(test_root) or test_root.replace("\\","/").begins_with(ProjectSettings.globalize_path("res://").replace("\\","/")):
		check(false,"existing external test root required");quit(1);return
	if DirAccess.dir_exists_absolute(test_root.path_join("bulk")) or DirAccess.dir_exists_absolute(test_root.path_join("deep")):
		check(false,"fresh isolated fixture directories required");quit(1);return
	var manager:=root.get_node("AssetManager");manager.content_root_override=test_root
	var bulk:=test_root.path_join("bulk");DirAccess.make_dir_recursive_absolute(bulk)
	for i:int in 2050:write(bulk.path_join("item_%04d.json"%i),"bulk_%04d"%i)
	write(bulk.path_join("later/visible.json"),"later_visible")
	var library:=Library.new(bulk)
	var listing:=library.entries(test_root)
	check(listing.size()==2053,"all 2051 authored materials plus two builtins are listed")
	check(library.search("later_visible").size()==1 and not library.find("later/visible").is_empty(),"search and single lookup find material beyond 2048")
	check(library.find_many(["item_0000","later/visible"]).size()==2,"batch lookup finds all requested materials across the old limit")
	var deep:=test_root.path_join("deep");var branch:=deep
	var names:Array[String]=[]
	for i:int in 12:
		var name_:String="d%d"%i;names.append(name_);branch=branch.path_join(name_)
	write(branch.path_join("leaf.json"),"deep_material")
	library.directory=deep
	var id:=String("/").join(names)+"/leaf"
	check(library.entries(test_root).any(func(entry):return entry.material_id==id),"deep material is included in catalog")
	check(library.find(id).get("name","")=="deep_material" and library.find_many([id]).has(id),"single and batch lookup agree on deep paths")
	check(library.find_many(["../bulk/item_0000","C:/outside","res://escape"]).is_empty(),"targeted lookup does not cross its catalog root")
	print("SURFACE_MATERIAL_LIBRARY_UNBOUNDED checks=",checks," failures=",failures)
	quit(1 if failures else 0)
