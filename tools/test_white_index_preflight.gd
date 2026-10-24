extends SceneTree
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Fixtures=preload("res://tools/test_map_dependency_index.gd")
class Loader extends "res://scripts/world3d/map_loader.gd":
	var warm_calls:=0
	func _decode_prefabs(_records:Array,_workers:int=4)->void:warm_calls+=1
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var loader:=Loader.new();loader._content_root=Paths.external_root()
	var helper:=Fixtures.new();helper.content_root=Paths.external_root();helper.folder=Paths.cache_directory("white_preflight_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(helper.folder)
	var box:=helper.box("a",0)
	box.surface_paint=[{"mesh":"","geometry":"test","surface":0,"face":0,"scale":[1,1],"offset":[0,0],"rotation":0,"mapping":"uv","material":{"name":"unused white material","color":[1,1,1,1],"roughness":.8,"texture_path":helper.folder.path_join("unused_white_texture.png")}}]
	Controls.white_materials=true;Controls.discard_map_textures=true;Policy.verify_packages=false
	var result:Dictionary=loader._validate_record_batch([{"record":box,"paint_id":"shared"}])
	check(result.ok and result.get("textures",{}).is_empty(),"trusted white preflight does not inspect unused material files")
	Controls.discard_map_textures=false
	result=loader._validate_record_batch([{"record":box,"paint_id":"shared"}])
	check(not result.ok,"normal material route still observes its required files")
	box.erase("surface_paint")
	var fixture:Dictionary=helper.fixture("map",[box]);var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture.path))
	var extra:Dictionary=data.nodes[0].extras.duplicate();extra.rmmo_records=[box]
	Controls.discard_map_textures=true
	var method:Dictionary={}
	for entry:Dictionary in loader.get_method_list():
		if entry.name=="_valid_records":method=entry
	var arguments:Array=[extra,[]]
	if method.args.size()==3:arguments.append(false)
	check(loader.callv("_valid_records",arguments),"white metadata preflight succeeds")
	check(loader.warm_calls==0,"cold index owns its geometry preparation without a preceding full-prefab barrier")
	var before:=loader.warm_calls
	check(loader._valid_records(extra) and loader.warm_calls==before+1,"other callers retain explicit eager preparation")
	Controls.white_materials=false;Controls.discard_map_textures=false
	for temporary:String in helper.created:
		if Paths.allowed(temporary,helper.content_root):DirAccess.remove_absolute(temporary)
	helper.free();loader.free();print("WHITE_INDEX_PREFLIGHT failures=",failures);quit(1 if failures else 0)
