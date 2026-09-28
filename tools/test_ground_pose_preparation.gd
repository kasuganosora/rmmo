extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Prepare=preload("res://scripts/char/character_ground_pose_preparer.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Ground preparation timeout");quit(2))
 var view=View.new();root.add_child(view)
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 var gear={"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}
 view.configure("female",recipe,gear);view.model.set_process(false)
 var body=view.model.axis_rig.body;var identity:int=body.get_instance_id()
 var prepare=view.model.axis_rig.ground_pose;var notifications:Array=[]
 body.surface_updated.connect(func():notifications.append(1))
 var folder:String=Art.review_path("character_3d/ground_pose_preparation_01");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(800,640);view.camera.size=1.8;view.camera.position=Vector3(3,1,.5);view.camera.look_at(Vector3(0,.5,0))
 var results:Array=[]
 for height:float in [0.0,-1.0,1.0]:
  recipe.body_shapes={"height":height};view.model.configure("female",recipe,gear)
  view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
  var before:PackedVector3Array=body.posed_points.duplicate();notifications.clear()
  var animation:Animation=await view.model.axis_rig.prepare_ground_pose()
  assert(animation!=null,prepare.error)
  assert(notifications.is_empty(),"Trial pose reached the visible body")
  var trial_updates:int=notifications.size()
  assert(before==body.posed_points and identity==body.get_instance_id(),"Preparation modified visible body")
  var count:int=prepare.build_count
  var cached:Animation=await view.model.axis_rig.prepare_ground_pose()
  assert(cached==animation and prepare.build_count==count,"Same shape rebuilt ground pose")
  var library:AnimationLibrary=view.model.axis_rig.animations.library.duplicate()
  library.add_animation("sit_ground",animation)
  assert(view.model.axis_rig.animations.install(body.skeleton,library))
  view.model.play("sit_ground","front",true);view.model._from_rotations.clear();view.model.pose_at(0)
  var minimum:=INF
  for p:Vector3 in body.posed_points:minimum=minf(minimum,(view.model.rig.transform*(p+body.root_offset)).y)
  assert(absf(minimum)<.001 and body.pose_sync_error.is_empty())
  await RenderingServer.frame_post_draw
  view.viewport.get_texture().get_image().save_png(folder+"/height_%s.png"%str(height))
  results.append({"height":height,"minimum_y_m":minimum,"build_count":count,"visible_trial_updates":trial_updates})
  await process_frame
  # Keep this test's static clip out of subsequent shape configuration.
  library.remove_animation("sit_ground");assert(view.model.axis_rig.animations.install(body.skeleton,library))
  view.model.play("idle","front",true)
 assert(prepare.build_count==3)
 var dying_owner:=Node3D.new();root.add_child(dying_owner);dying_owner.queue_free()
 var cancelled=Prepare.new()
 var abandoned:Animation=await cancelled.prepare(dying_owner,{})
 assert(abandoned==null and cancelled.error=="Ground pose owner released" and not cancelled.busy,"Released owner retained pending work")
 for child in root.get_children():assert(child.name!="GroundPosePreparation","Temporary preparation body leaked")
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify({"results":results,"scope":"Shared Model static playback, shape cache and hidden preparation only; no normal UI or transition acceptance"},"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("PASS hidden ground pose preparation, cache, shared Model playback and cleanup");quit()
