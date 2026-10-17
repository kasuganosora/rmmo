extends SceneTree
const Library=preload("res://review_artifacts/material_lookup_20261017/library_profile.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Evidence="D:/code/rmmo_runtime/review_artifacts/material_lookup_20261017/"
func _initialize()->void:run.call_deferred()
func run()->void:
	DirAccess.make_dir_recursive_absolute(Evidence)
	var library:=Library.new()
	var samples:Array=[]
	for i in 4:
		for id:String in ["pack:default:paving/historic_cobble/material","pack:default:paving/automatic_limestone_kerb/material"]:
			var start:=Time.get_ticks_usec();var value:=library.find(id);var lookup:=Time.get_ticks_usec()-start
			start=Time.get_ticks_usec();var valid:=Paint.material_valid(value);var validation:=Time.get_ticks_usec()-start
			start=Time.get_ticks_usec();var missing:=Paint.missing([{"road_kerb_material":value}]);var dependency:=Time.get_ticks_usec()-start
			var row:={"round":i,"id":id,"lookup_us":lookup,"catalog":library.measurements.duplicate(true),"selected_validation_us":validation,"selected_dependency_us":dependency,"valid":valid,"missing":missing,"material":value}
			samples.append(row);print(JSON.stringify(row))
	var file:=FileAccess.open(Evidence+"profile_before.json",FileAccess.WRITE);file.store_string(JSON.stringify({"samples":samples},"\t"));file.close()
	quit(0 if samples.all(func(s):return s.valid and s.missing.is_empty()) else 1)
