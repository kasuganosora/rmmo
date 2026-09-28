extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(240).timeout.connect(func():push_error("Ground action preparation timeout");quit(2))
 var view=View.new();root.add_child(view)
 var height:=0.0
 var dressed:bool=OS.get_cmdline_user_args().has("--outfit")
 var scene_contact:bool=OS.get_cmdline_user_args().has("--scene-contact")
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--height="):height=float(arg.trim_prefix("--height="))
 var parts:Dictionary={"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE.duplicate(true)}
 if dressed:
  parts.SurfaceEquipment.merge({"Clothing1":"maid_separate/item_02","Clothing2":"maid_separate/item_01"})
  parts["SurfaceClothSlots"]=["Clothing2"]
 view.configure("female",{"body_model":"female_base_v2","body_shapes":{"height":height},"part_ids":{"FrontHair1":202}},parts)
 var model=view.model;model.set_process(false);var body=model.axis_rig.body
 model.pose_at(.2);var before:PackedVector3Array=body.posed_points.duplicate();var updates:Array=[]
 body.surface_updated.connect(func():updates.append(1))
 var bundle:AnimationLibrary=await model.axis_rig.prepare_ground_actions()
 assert(bundle!=null,model.axis_rig.last_error)
 assert(updates.is_empty() and before==body.posed_points,"Action preparation changed visible pose")
 var again:AnimationLibrary=await model.axis_rig.prepare_ground_actions()
 assert(again==bundle and model.axis_rig.ground_actions.build_count==1)
 # Exercise release while native modifiers are pending, not just static fitting.
 var dying_owner:=Node3D.new();root.add_child(dying_owner);dying_owner.queue_free()
 var cancelled=preload("res://scripts/char/character_ground_action_preparer.gd").new()
 var abandoned:AnimationLibrary=await cancelled.prepare(dying_owner,body.shape_values,bundle.get_animation("sit_ground"),model.axis_rig.animations.library)
 assert(abandoned==null and cancelled.error=="Ground action owner released" and not cancelled.busy,"Released action owner retained pending work")
 assert(cancelled.cached_library==null and cancelled.build_count==0,"Cancelled actions entered cache")
 for child in root.get_children():assert(child.name!="GroundActionPreparation","Cancelled action workspace leaked")
 var library:AnimationLibrary=model.axis_rig.animations.library.duplicate()
 for clip:StringName in bundle.get_animation_list():library.add_animation(clip,bundle.get_animation(clip))
 assert(model.axis_rig.animations.install(body.skeleton,library))
 var folder:String=Art.review_path("character_3d/%s/height_%s"%[("ground_dressed_02" if scene_contact else "ground_dressed_01") if dressed else "ground_action_preparation_01",str(height)]);DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(800,640);view.camera.size=2.4;view.camera.position=Vector3(3,1.6,3);view.camera.look_at(Vector3(0,.8,0))
 var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(5,5);floor_mesh.mesh=plane;view.viewport.add_child(floor_mesh)
 if scene_contact:
  model.axis_rig.cloth.set_scene_colliders([floor_mesh])
  for entry in model.axis_rig.cloth.entries.values():assert(entry.adapter.scene_triangles.size()==6,"Floor triangles did not reach cloth solver")
 var interpolation_lift:=0.0;var minimum:=INF;var maximum_lift_frame:Dictionary={};var unblended_lift:=0.0
 for action:String in ["sit_down_ground","stand_up_ground"]:
  model.play(action,"front",true)
  var frames:int=ceili(model.action_duration()*60)+12
  for frame in frames:
   model._process(1.0/60)
   var lift:float=model.axis_rig.animations.support_adjustment
   if lift>interpolation_lift:
    interpolation_lift=lift
    maximum_lift_frame={"action":model.action,"time":model.elapsed,"blending":not model._from_rotations.is_empty()}
   if model._from_rotations.is_empty():unblended_lift=maxf(unblended_lift,lift)
   for p:Vector3 in body.posed_points:minimum=minf(minimum,(model.rig.transform*(p+body.root_offset)).y)
   await RenderingServer.frame_post_draw
   if frame in [0,frames/2,frames-1]:view.viewport.get_texture().get_image().save_png(folder+"/%s_%03d.png"%[action,frame])
   await process_frame
  assert(model.action==("sit_ground" if action=="sit_down_ground" else "idle"),"Ground action completion missing")
  if dressed and action=="sit_down_ground":
   for frame in 60:
    model._process(1.0/60)
    await RenderingServer.frame_post_draw
    await process_frame
   for side in ["front","side","back"]:
    view.camera.position={"front":Vector3(0,1.3,3),"side":Vector3(3,1.3,0),"back":Vector3(0,1.3,-3)}[side]
    view.camera.look_at(Vector3(0,.6,0))
    await RenderingServer.frame_post_draw
    view.viewport.get_texture().get_image().save_png(folder+"/hold_"+side+".png")
    await process_frame
   view.camera.position=Vector3(3,1.6,3);view.camera.look_at(Vector3(0,.8,0))
 assert(minimum>-.001)
 for child in root.get_children():assert(child.name not in ["GroundPosePreparation","GroundActionPreparation"])
 var report={"height":height,"minimum_y_m":minimum,"interpolation_floor_lift_m":interpolation_lift,"maximum_lift_frame":maximum_lift_frame,"unblended_floor_lift_m":unblended_lift,"preparation_floor_correction_m":model.axis_rig.ground_actions.maximum_floor_correction,"preparation_ik_error_m":model.axis_rig.ground_actions.maximum_ik_error,"scope":"Shared per-shape action preparation, cache and 60Hz Model playback; gameplay request/cancel and cloth pending"}
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 if dressed:
  report["scope"]="Original maid outfit with runtime GPU cloth; numerical assertions cover BODY only. Garment visuals require image review."
  report["scene_contact"]=scene_contact
  report["garment_visual_accepted"]=false
  file=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 print("Ground prepared actions ",report)
 view.free()
 for frame in 3:await process_frame
 quit()
