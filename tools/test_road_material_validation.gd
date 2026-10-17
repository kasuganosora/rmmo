extends SceneTree
const Native=preload("res://scripts/world_editor/road_tools.gd")
const Old=preload("res://review_artifacts/road_record_prepare_20261017/road_tools_baseline.gd")
const CountOld=preload("res://review_artifacts/road_record_prepare_20261017/road_tools_baseline_count.gd")
const CountNew=preload("res://review_artifacts/road_record_prepare_20261017/road_tools_current_count.gd")
const Counter=preload("res://review_artifacts/road_record_prepare_20261017/surface_materials_count.gd")
const Fixture=preload("res://tools/road_prepare_fixture.gd")
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Evidence="D:/code/rmmo_runtime/review_artifacts/road_record_prepare_completed_20261017/"
var checks:Array=[]
var counts:Array=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:checks.append({"ok":ok,"label":label_});print("PASS " if ok else "FAIL ",label_)
func run()->void:
	var fixture:=Fixture.local_terrain();var context:=Fixture.context(fixture);context._material_tool.library=Library.new()
	var old:=Old.new();old.editor=context;var current:=Native.new();current.editor=context
	var ids:=["pack:default:paving/historic_cobble/material","pack:default:paving/automatic_limestone_kerb/material"]
	var args:Dictionary=fixture.args.merged({"kerb_enabled":true,"material_id":ids[0],"kerb_material_id":ids[1]},true)
	var reference:Dictionary=old.prepare(args);check(reference.ok,"actual dual PBR preparation succeeds")
	for variant in [{"name":"baseline","script":CountOld},{"name":"current","script":CountNew}]:
		var tool:RefCounted=variant.script.new();tool.editor=context
		for call in 2:
			Counter.material_visits=0;Counter.material_cache_hits=0;Counter.material_path_checks=0
			var actual:Dictionary=tool.prepare(args)
			check(var_to_bytes(actual)==var_to_bytes(reference),"instrumented "+variant.name+" complete bytes equal, call "+str(call))
			counts.append({"version":variant.name,"call":call,"visits":Counter.material_visits,"cache_hits":Counter.material_cache_hits,"path_checks":Counter.material_path_checks,"road_records":actual.get("records",[]).size()})
		tool.editor=null
	check(counts[2].path_checks<counts[0].path_checks and counts[2].cache_hits>0,"actual path-validation work decreases")
	check(counts[2].path_checks==counts[3].path_checks and counts[3].path_checks>0,"next prepare repeats fresh required validation")
	var material:Dictionary=context._material_tool.library.find(ids[0]);var cache:Dictionary={}
	var built:=Plan.build(Fixture.graph([[[-6.,0.,0.],[6.,0.,0.]]]),Plan.defaults())
	var record:Dictionary=built.records[0]
	for changes:Dictionary in [{},{"roughness":-1.},{"color":[1,1,1,2]},{"normal_strength":5.},{"texture_path":ProjectSettings.globalize_path("res://project.godot")},{"normal_format":"invalid"},{"tile_size":[.001,1.]}]:
		var definition:=material.merged(changes,true);var a:=record.duplicate(true);var b:=record.duplicate(true)
		var expected:Dictionary=old.paint_default(a,definition);var actual:Dictionary=current.paint_default(b,definition,cache)
		check(var_to_bytes(actual)==var_to_bytes(expected) and var_to_bytes(a)==var_to_bytes(b),"shared cache keeps exact validation and author result: "+str(changes.keys()))
		check(actual.ok==changes.is_empty(),"invalid definition cannot reuse an earlier material proof: "+str(changes.keys()))
	var invalid:=record.duplicate(true);invalid.terrain_saturation=.5
	check(not current.paint_default(invalid,material,cache).ok,"cached material cannot bypass independent record constraints")
	var directory:=preload("res://scripts/world3d/map_paths.gd").cache_directory("road_validation_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("temporary.png");var image:=Image.create(2,2,false,Image.FORMAT_RGB8);image.fill(Color.WHITE);image.save_png(path)
	var external:Dictionary={"name":"temporary","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":path}
	var transient:Dictionary={};check(current.paint_default(record.duplicate(true),external,transient).ok,"existing temporary dependency validates")
	DirAccess.remove_absolute(path)
	check(not current.paint_default(record.duplicate(true),external,transient).ok,"even reused material proof cannot hide a missing texture on another record")
	image.save_png(path);check(current.paint_default(record.duplicate(true),external).ok,"standalone next operation sees restored dependency")
	var failures:=checks.filter(func(c):return not c.ok).size()
	FileAccess.open(Evidence+"validation.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"counts":counts,"scope":"counter copies outside timing; exact complete output; material proofs local to one prepare; per-record structural and dependency checks retained"},"\t"))
	old.editor=null;current.editor=null;context._waterways.editor=null;context.free();quit(1 if failures else 0)
