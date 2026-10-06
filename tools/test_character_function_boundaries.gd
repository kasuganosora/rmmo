extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
class DelayedPose extends RefCounted:
 var error:=""
 var waiting:=false
 func prepare(owner:Node3D,_shape:Dictionary)->Animation:
  waiting=true
  await owner.get_tree().process_frame
  return Animation.new()
func _initialize()->void:call_deferred("run")
var finished:=false
var result:Animation
func prepare(adapter)->void:
 result=await adapter.prepare_ground_pose()
 finished=true
func run()->void:
 create_timer(120).timeout.connect(func():push_error("Boundary test timed out");quit(2))
 var recipe:Dictionary={"body_model":"female_base_v2","part_ids":{"FrontHair1":0}}
 var gear:Dictionary={"SurfaceEquipment":{"UnderwearBottom":"underlayer_briefs/item_00"}}
 var model=Model.create("female",recipe,gear);root.add_child(model);model.set_process(false)
 var body=model.axis_rig.body;var id:int=body.get_instance_id()
 model.play("walk","front",true);model.pose_at(.3)
 assert(model.set_expressions({"a":.4}))
 var values:Dictionary=body.expression_values.duplicate()
 var adapter=model.axis_rig
 adapter.ground_pose=DelayedPose.new()
 prepare(adapter)
 assert(adapter.ground_pose.waiting)
 var changed:Dictionary=recipe.duplicate(true);changed["body_shapes"]={"height":.2}
 model.configure("female",changed,gear)
 model.configure("female",recipe,gear)
 while not finished:await process_frame
 assert(result==null,"Changed-and-restored identity accepted stale pose")
 assert(body.get_instance_id()==id and body.expression_values==values)
 assert(model.action=="walk")
 var slots:Dictionary=adapter.wardrobe.slots.duplicate()
 var garment_id:int=adapter.wardrobe.garments.UnderwearBottom.get_instance_id()
 assert(not adapter.set_equipment({"SurfaceEquipment":{"UnderwearBottom":"missing/item"}}))
 assert(adapter.wardrobe.slots==slots and adapter.wardrobe.garments.UnderwearBottom.get_instance_id()==garment_id)
 model.set_equipment({})
 assert(adapter.wardrobe.slots.is_empty() and model.action=="walk" and body.expression_values==values)
 model.set_equipment(gear)
 assert(body.get_instance_id()==id and adapter.wardrobe.slots==slots)
 finished=false;result=null
 prepare(adapter)
 # A color-only update should not cancel shape-specific work.
 changed=recipe.duplicate(true);changed["eye_color"]="#77aabb"
 model.configure("female",changed,gear)
 while not finished:await process_frame
 assert(result!=null,"Color-only edit incorrectly canceled shape preparation")
 var library:AnimationLibrary=adapter.animations.library.duplicate()
 for clip:StringName in [&"sit_ground",&"sit_down_ground",&"stand_up_ground"]:
  if library.has_animation(clip):library.remove_animation(clip)
  library.add_animation(clip,library.get_animation("idle").duplicate())
 assert(adapter.animations.install(body.skeleton,library))
 model.play("sit_ground","front",true)
 changed["body_shapes"]={"height":-.2}
 model.configure("female",changed,gear)
 assert(model.action=="idle")
 for clip:StringName in [&"sit_ground",&"sit_down_ground",&"stand_up_ground"]:
  assert(not adapter.supports(clip) and not adapter.animations.tracks.has(clip),"Stale shape-specific clip remains callable")
 assert(adapter.supports("walk") and adapter.supports("sit_chair"))
 assert(body.get_instance_id()==id and body.expression_values==values)
 model.play("attack","front",true);model.elapsed=.2
 model.configure("young_female",{},{})
 assert(model.action=="idle" and model.elapsed==0 and model.animation_clip.is_empty(),"Replacement inherited previous action")
 model.configure("female",recipe,gear)
 assert(model.action=="idle" and model.axis_rig!=null)
 model.free();await process_frame
 print("PASS shape ABA cancellation, color-only continuity, equipment failure atomicity, swap identity/expression/action preservation")
 quit()
