extends SceneTree
const Native=preload("res://scripts/world_editor/road_tools.gd")
const Profile=preload("res://review_artifacts/road_record_prepare_20261017/road_tools_profile.gd")
const Fixture=preload("res://tools/road_prepare_fixture.gd")
const Evidence="D:/code/rmmo_runtime/review_artifacts/road_record_prepare_completed_20261017/"
func _init()->void:run.call_deferred()
func run()->void:
	var native:=Native.new();var profile:=Profile.new();var results:Array=[];var failures:=0
	for far in [false,true]:
		var fixture:=Fixture.local_terrain(far);var context:=Fixture.context(fixture)
		context._material_tool.library=preload("res://scripts/world_editor/surface_material_library.gd").new()
		native.editor=context;profile.editor=context;profile.profile_enabled=true
		var args:Dictionary=fixture.args.merged({"kerb_enabled":true,"material_id":"pack:default:paving/historic_cobble/material","kerb_material_id":"pack:default:paving/automatic_limestone_kerb/material"},true)
		var expected:=var_to_bytes(native.prepare(args));var before:=var_to_bytes(Fixture.state(context))
		for i in 3:
			var result:Dictionary=profile.prepare(args)
			var same:bool=result.ok and var_to_bytes(result)==expected and var_to_bytes(Fixture.state(context))==before
			if not same:failures+=1
			results.append({"far":far,"index":i,"same":same,"profile":profile.last_profile.duplicate(true)})
		native.editor=null;profile.editor=null;context._waterways.editor=null;context.free()
	FileAccess.open(Evidence+"attribution.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"samples":results,"scope":"current-version preliminary attribution; archived instrumented copy verified against full native bytes; not OFF performance results"},"\t"))
	print(JSON.stringify(results));quit(1 if failures else 0)
