extends "res://tools/test_road_projection_reuse.gd"
## Compare against the frozen previous batch with its original library.
const ReferenceRoads=preload("res://review_artifacts/material_targeted_20261017/road_tools_baseline.gd")
const ReferenceLibrary=preload("res://review_artifacts/material_targeted_20261017/surface_material_library_baseline.gd")
func initialize()->bool:
	report_path="D:/code/rmmo_runtime/review_artifacts/material_targeted_20261017/roads.json"
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var archive:="res://review_artifacts/material_targeted_20261017/"
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(archive+"baseline.json"))
	for filename:String in manifest.files:check(FileAccess.get_sha256(archive+filename)==manifest.files[filename],"frozen previous batch "+filename)
	var projection:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE+"reference.json"))
	for filename:String in projection.files:check(FileAccess.get_sha256(ARCHIVE+filename)==projection.files[filename],"unchanged projection baseline "+filename)
	var hashes:Dictionary={};source_hashes("res://scripts/world3d",hashes);source_hashes("res://scripts/world_editor",hashes)
	for path:String in ["res://tools/test_material_targeted_roads.gd","res://tools/test_road_projection_reuse.gd","res://tools/road_prepare_fixture.gd","res://tools/test_road_prepare_differential.gd","res://project.godot"]:hashes[path]=FileAccess.get_sha256(path)
	report={"reference":manifest,"projection_reference":projection,"script_sha256":hashes,"engine":Engine.get_version_info(),"engine_executable_sha256":FileAccess.get_sha256(OS.get_executable_path()),"fixtures":[]}
	return failures==0
func compare_context(name_:String,context:Node3D,args:Dictionary,current:RefCounted,_original:RefCounted,expected_ok:Variant=null,conflict:="")->Dictionary:
	var reference:=ReferenceRoads.new();reference.editor=context
	var native_library:RefCounted=context._material_tool.library
	var old_library:=ReferenceLibrary.new(native_library.directory);old_library.include_shared=native_library.include_shared
	var before:=var_to_bytes([Fixture.state(context),args]);current.profile_enabled=true
	var actual:Dictionary=current.prepare(args)
	context._material_tool.library=old_library
	var expected:Dictionary=reference.prepare(args)
	context._material_tool.library=native_library
	record_comparison(name_,actual,expected,[Fixture.state(context),args],expected_ok,conflict)
	current.profile_enabled=false
	check(var_to_bytes(current.prepare(args))==var_to_bytes(actual) and current.last_profile.is_empty(),name_+" ON/OFF exact and disabled profile empty")
	check(before==var_to_bytes([Fixture.state(context),args]),name_+" state history authoring and arguments unchanged")
	reference.editor=null;return actual
