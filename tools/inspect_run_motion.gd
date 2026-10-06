extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var model:=Model.new();root.add_child(model);model.set_process(false);model.configure("female",{}, {})
	model.play("dash","front",true)
	var values:Array=[]
	for i in range(61):
		model.pose_at(model.action_duration()*i/60.0)
		var entry:Dictionary={"phase":i/60.0}
		for key in ["hips","head","armL","forearmL","handL","armR","forearmR","handR","footL","footR","thighL","shinL","thighR","shinR"]:
			var point:Vector3=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones[key]).origin
			entry[key]=[point.x,point.y,point.z]
		for name in ["mixamorig_LeftToeBase","mixamorig_RightToeBase"]:
			var point:Vector3=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.skeleton.find_bone(name)).origin
			entry[name]=[point.x,point.y,point.z]
		values.append(entry)
	var path:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/run_metrics_after.json")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(values));file.close()
	print("METRICS_OK");quit()
