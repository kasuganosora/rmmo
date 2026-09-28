extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(240).timeout.connect(func():push_error("Ground transition timeout");quit(2))
 var view=View.new();root.add_child(view)
 view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
 var model=view.model;model.set_process(false);var body=model.axis_rig.body
 var seated:Animation=await model.axis_rig.prepare_ground_pose();assert(seated!=null,model.axis_rig.last_error)
 var library:AnimationLibrary=model.axis_rig.animations.library.duplicate()
 var candidate:AnimationLibrary=preload("res://tools/ground_transition_candidate.gd").build(body,seated,library.get_animation("get_up"))
 for clip:StringName in candidate.get_animation_list():library.add_animation(clip,candidate.get_animation(clip))
 assert(model.axis_rig.animations.install(body.skeleton,library))
 var folder:String=Art.review_path("character_3d/ground_transition_01");DirAccess.make_dir_recursive_absolute(folder)
 var contact=null
 var bake:bool="--bake" in OS.get_cmdline_user_args()
 if "--support" in OS.get_cmdline_user_args():
  folder=Art.review_path("character_3d/ground_transition_03");DirAccess.make_dir_recursive_absolute(folder)
  contact=preload("res://tools/ground_transition_support.gd").new();contact.configure(model)
 if bake:
  assert(contact!=null,"Baking requires --support")
  folder=Art.review_path("character_3d/ground_transition_04");DirAccess.make_dir_recursive_absolute(folder)
 ResourceSaver.save(candidate,folder+"/candidate.res")
 var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(5,5);floor_mesh.mesh=plane
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color("777c80");floor_mesh.material_override=mat;view.viewport.add_child(floor_mesh)
 view.viewport.size=Vector2i(800,640);view.camera.size=2.4;view.camera.position=Vector3(3,1.6,3);view.camera.look_at(Vector3(0,.8,0))
 var samples:Array=[]
 var recordings:=AnimationLibrary.new();var expected:Dictionary={}
 for action:String in ["stand_up_ground","sit_down_ground"]:
  model.play("get_up","front",true,action);model._from_rotations.clear()
  var duration:float=model.action_duration();var count:int=ceili(duration*30);var last_hip:=Vector3.ZERO
  var recorded:=Animation.new();recorded.length=duration;var poses:Array=[]
  for frame in count+1:
   var time:float=duration*frame/count;model.pose_at(time)
   if contact!=null:contact.prepare(model,time if action=="stand_up_ground" else duration-time)
   await RenderingServer.frame_post_draw
   var end_error:=0.0
   if contact!=null:
    for bridge in [contact.legs,contact.arms]:
     assert(bridge.completed_revision==bridge.revision and bridge.error.is_empty(),"Native contact pose missing from rendered frame")
     for i in 2:
      var actual:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone(bridge.end_bones[i])).origin
      end_error=maxf(end_error,actual.distance_to(bridge.targets[i].position))
   var low:=INF
   for p:Vector3 in body.posed_points:low=minf(low,(model.rig.transform*(p+body.root_offset)).y)
   var hip:Vector3=model.rig.transform*body.get_solved_bone_pose(body.skeleton.find_bone("hip")).origin
   var step:float=hip.distance_to(last_hip) if frame>0 else 0.0;last_hip=hip
   samples.append({"action":action,"time":time,"floor_minimum_m":low,"hip_step_m":step,"raw_animation_floor_lift_m":model.axis_rig.animations.support_adjustment,"ik_end_error_m":end_error})
   if bake:
    # Apply the normal playback floor policy once, before capturing. Preserve
    # its small support gap in evidence instead of silently applying it twice.
    var offset:Vector3=model.rig.position+Vector3(0,maxf(0,-low),0)
    preload("res://scripts/char/character_axis_pose_capture.gd").append(body,recorded,time,offset)
    var points:=PackedVector3Array()
    for p:Vector3 in body.posed_points:points.append(model.rig.basis*(p+body.root_offset)+offset)
    poses.append(points)
   if frame in [0,int(count*.15),int(count*.3),int(count*.45),int(count*.6),int(count*.8),count]:view.viewport.get_texture().get_image().save_png(folder+"/%s_%03d.png"%[action,frame])
   await process_frame
  if bake:recordings.add_animation(action,recorded);expected[action]=poses
 var replay_error:=0.0
 if bake:
  contact.legs.cancel();contact.arms.cancel()
  for clip:StringName in recordings.get_animation_list():
   library.remove_animation(clip);library.add_animation(clip,recordings.get_animation(clip))
  assert(model.axis_rig.animations.install(body.skeleton,library))
  for action:String in ["stand_up_ground","sit_down_ground"]:
   model.play("get_up","front",true,action);model._from_rotations.clear()
   var count:int=expected[action].size()-1
   for frame in count+1:
    model.pose_at(model.action_duration()*frame/count)
    var previous:PackedVector3Array=expected[action][frame]
    for i in previous.size():replay_error=maxf(replay_error,previous[i].distance_to(model.rig.transform*(body.posed_points[i]+body.root_offset)))
    assert(not contact.legs.modifier.active and not contact.arms.modifier.active)
    assert(replay_error<.00005,"Baked playback diverged from final native pose")
    await RenderingServer.frame_post_draw
    if frame in [0,int(count*.3),int(count*.6),count]:view.viewport.get_texture().get_image().save_png(folder+"/%s_replay_%03d.png"%[action,frame])
    await process_frame
  assert(ResourceSaver.save(recordings,folder+"/baked.res")==OK)
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify({"samples":samples,"replay_surface_error_m":replay_error,"baked":bake,"visual_accepted":false,"scope":"Ground recovery preparation/replay diagnostic; small floor-policy support gaps remain, no gameplay promotion"},"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("Ground transition candidate captured; acceptance requires visual contact review");quit()
