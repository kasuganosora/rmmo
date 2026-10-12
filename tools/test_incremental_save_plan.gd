extends SceneTree
const Delta=preload("res://scripts/world3d/incremental_save.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
var failed:=0
func check(value:bool,label:String)->void:
	print(("PASS " if value else "FAIL ")+label)
	if not value:failed+=1
func baseline(record:Dictionary)->Dictionary:
	var node:Dictionary={"name":record.uuid,"mesh":0,"extras":{"uuid":record.uuid}}
	Pose._set_pose(node,Pose.pose(record))
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"extensionsUsed":["GODOT_single_root"],
		"nodes":[{"name":"rmmo_world","children":[1],"extras":Pose.extras([record],{})},node],"meshes":[{"primitives":[{"attributes":{}}]}]}
	return JSON.parse_string(JSON.stringify(data,"",true,true))
func _init()->void:
	var original:Dictionary={"uuid":"obj_a","kind":"box","surface_id":"block","size":[1,2,3],"position":[0,0,0],"rotation":[0,0,0]}
	var copy:Dictionary=original.duplicate(true);copy.uuid="obj_b";copy.position=[10,0,0]
	var planned:Dictionary=Delta.plan(baseline(original),[original,copy],{},Pose)
	check(planned.get("ok",false),"native numeric JSON can plan an added instance")
	if planned.get("ok",false):check(planned.cloned_instances==1 and planned.export_records.is_empty(),"integer author fields and JSON floats share the same unchanged resources")
	copy.editor_group="new_group";copy.editor_group_name="Copied independent group"
	planned=Delta.plan(baseline(original),[original,copy],{},Pose)
	check(planned.get("ok",false) and planned.cloned_instances==1,"independent editor group changes do not duplicate unchanged resources")
	var moved:Dictionary=original.duplicate(true);moved.position=[3,0,0]
	planned=Delta.plan(baseline(original),[moved,copy],{},Pose)
	check(planned.get("ok",false) and planned.get("updated_nodes",0)==1,"combined existing pose and membership edit")
	var malformed:Dictionary=copy.duplicate(true);malformed.position=[NAN,0,0]
	check(not Delta.plan(baseline(original),[original,malformed],{},Pose).ok,"invalid added transform rejects reuse")
	planned=Delta.plan(baseline(original),[],{},Pose)
	check(planned.get("ok",false) and planned.removed_instances==1 and not planned.data.nodes[int(planned.root)].has("children"),"deleting the last instance omits empty children while retaining valid resource indices")
	print("INCREMENTAL_SAVE_PLAN_FINISHED failures=",failed)
	quit(0 if failed==0 else 1)
