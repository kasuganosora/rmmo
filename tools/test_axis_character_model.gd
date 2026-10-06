extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const View=preload("res://scripts/char/character_view_3d.gd")
const Custom=preload("res://scripts/char/customization.gd")
class AppearanceController extends RefCounted:
	var anim:AnimatedSprite2D
	var character_3d:Node2D
	var _weapon_spr:Node2D
	var gender:="female"
class PreviewCloth extends RefCounted:
	func step(_body:Node3D,_reset:bool,_iterations:int,_inner:Array)->void:pass
class PreviewGarment extends Node3D:
	var cloth_enabled:=true
	var cloth:RefCounted
	func enable_cloth()->bool:cloth=PreviewCloth.new();return true
	func disable_cloth()->void:cloth=null
func _initialize()->void:call_deferred("run")
func error(a:PackedVector3Array,b:PackedVector3Array)->float:
	var maximum:=0.0
	for i:int in a.size():maximum=maxf(maximum,a[i].distance_to(b[i]))
	return maximum
func run()->void:
	var recipe:Dictionary=Custom.from_dict({"body_model":"female_base_v2","eye_color":"#62aabb"}).to_dict()
	assert(Custom.from_dict(JSON.parse_string(JSON.stringify(recipe))).body_model=="female_base_v2")
	var parts:Dictionary={"SurfaceEquipment":{"UnderwearTop":"underlayer_lace/item_00","UnderwearBottom":"underlayer_briefs/item_00"}}
	var model:Node3D=Model.create("female",recipe,parts);root.add_child(model);model.set_process(false)
	assert(model.axis_rig!=null and model.imported_rig==null)
	var body:Node3D=model.axis_rig.body
	var identity:Array=[model.get_instance_id(),model.rig.get_instance_id(),body.get_instance_id(),model.skeleton.get_instance_id(),body.mesh_instance.mesh.get_instance_id()]
	for side:String in ["L","R"]:
		assert(signf(model.skeleton.get_bone_global_rest(model.bones["hand"+side]).origin.x)==(-1 if side=="L" else 1))
	model.play("walk","front",true);model._from_rotations.clear();model.elapsed=.4;model.pose_at(model.elapsed)
	var original:PackedVector3Array=body.posed_points.duplicate()
	var original_root:Transform3D=model.rig.transform
	var changed:Dictionary=recipe.duplicate(true);changed.skin_on=false;changed.eye_color="#7c9632"
	model.configure("female",changed,parts)
	assert(model.elapsed==.4 and model.action=="walk" and body.posed_points==original)
	assert(identity==[model.get_instance_id(),model.rig.get_instance_id(),body.get_instance_id(),model.skeleton.get_instance_id(),body.mesh_instance.mesh.get_instance_id()])
	model.set_equipment({"SurfaceEquipment":{"UnderwearBottom":"underlayer_briefs/item_00"}})
	assert(not model.axis_rig.wardrobe.slots.has("UnderwearTop") and model.elapsed==.4 and body.posed_points==original)
	model.set_equipment(parts);assert(body.posed_points==original)
	# Regression for enabling review cloth while an animation owns the pose.
	var wardrobe:Node3D=model.axis_rig.wardrobe
	var fake:=PreviewGarment.new();wardrobe.add_child(fake);wardrobe.garments["__pose_test"]=fake
	var requested:Dictionary=body.angles_by_name.duplicate(true)
	assert(wardrobe.warm_start_cloth())
	assert(error(original,body.posed_points)<.00001 and body.angles_by_name==requested and model.rig.transform==original_root)
	wardrobe.garments.erase("__pose_test");fake.free()
	# The shared controller's interrupted-action blend must deform the skin too.
	model.play("cast","left")
	assert(error(original,body.posed_points)<.00001,"Blend start changed the visible surface")
	var mismatch:=0.0
	for frame:int in 12:
		model._process(.016)
		for bone:int in model.skeleton.get_bone_count():
			mismatch=maxf(mismatch,body.get_solved_bone_pose(bone).origin.distance_to(model.skeleton.get_bone_global_pose(bone).origin))
		for point:Vector3 in body.posed_points:assert((model.rig.transform*point).y>=-.000001,"Blend penetrates support")
	assert(mismatch<.000001 and model._from_rotations.is_empty())
	assert(error(original,body.posed_points)>.03,"Blend never reached the actual cast")
	for clip:String in ["attack","sit_chair","death"]:
		model.play(clip,"front",true);model._from_rotations.clear();model.pose_at(model.action_duration())
		assert(model.action==clip and model.action_duration()>0 and body.pose_sync_error.is_empty())
	var npc:Node3D=Model.create_npc({"gender":"female","customization":recipe,"equipment":parts});root.add_child(npc);npc.set_process(false)
	assert(npc.axis_rig!=null and npc.axis_rig.body!=body)
	npc.play("idle","front",true);npc._from_rotations.clear();npc.pose_at(.3)
	var npc_surface:PackedVector3Array=npc.axis_rig.body.posed_points.duplicate()
	model.play("walk","back",true);model.pose_at(.6)
	assert(npc.axis_rig.body.posed_points==npc_surface)
	# Existing composited preview/view also uses the same adapter and recipe.
	var view:=View.new();view.portrait_mode=true;root.add_child(view);view.model.set_process(false);view.set_process(false)
	view.configure("female",recipe,parts)
	assert(view.model.axis_rig!=null and is_equal_approx(view.camera.size,.58))
	view.play("walk","right",true);view.model.pose_at(.4)
	assert(view.model.axis_rig.body.pose_sync_error.is_empty())
	var controller:=AppearanceController.new();controller.anim=AnimatedSprite2D.new();controller.character_3d=view
	var server=load("res://scripts/net/net.gd").server()
	var snapshot:Array=[{"slot":"underwear_bottom","item_id":"underwear_lace_briefs_white"}]
	preload("res://scripts/game/application/player_appearance.gd").apply_gear_look(controller,{"gender":"female","customization":recipe},snapshot,server.item_catalog)
	assert(view.model.axis_rig.wardrobe.slots=={"UnderwearBottom":"underlayer_briefs/item_00"})
	assert(view.model.action=="walk","Real player appearance update reset animation")
	controller.anim.free()
	var label=preload("res://scripts/char/character_overhead_label.gd").new();label.model=model;root.add_child(label);label.update_anchor()
	assert(label.global_position.y>=model.axis_rig.head_top(Vector3.UP)+label.clearance-.00001,"Name entered the new body's head")
	label.free()
	print("PASS shared Model / NPC / portrait View; recipe roundtrip, equipment/color identity, cloth pose restoration, post-blend surface and support; mismatch_m=",mismatch)
	view.free();npc.free();model.free()
	for frame in 3:await process_frame
	quit()
