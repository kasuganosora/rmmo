extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(240).timeout.connect(func():push_error("Seat transition timeout");quit(2))
 var view=View.new();root.add_child(view)
 var height:=0.0
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--height="):height=float(arg.trim_prefix("--height="))
 view.configure("female",{"body_model":"female_base_v2","body_shapes":{"height":height},"part_ids":{"FrontHair1":202}},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
 var model=view.model;model.set_process(false)
 var body=model.axis_rig.body;var support=model.axis_rig.seat
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_seat_transition_02/height_%s"%str(height))
 DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(800,640);view.camera.size=2.5;view.camera.position=Vector3(3,1.8,3);view.camera.look_at(Vector3(0,.9,0))
 model.play("sit_chair_hold","front",true);model._from_rotations.clear();model.pose_at(0)
 var pelvis:Vector3=model.rig.transform*body.get_solved_bone_pose(body.skeleton.find_bone("hip")).origin
 var seat:=Vector3(pelvis.x,.46,pelvis.z)
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color("aeb4b8")
 for spec:Array in [[Vector3(.5,.04,.5),seat-Vector3(0,.02,0)],[Vector3(.5,.45,.04),seat+Vector3(0,.225,-.25)],[Vector3(4,.04,4),Vector3(0,-.02,0)]]:
  var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=spec[0];mesh.mesh=box;mesh.position=spec[1];mesh.material_override=mat;view.viewport.add_child(mesh)
 support.set_seat(seat,Vector2(.5,.5))
 model.play("idle","front",true);model._from_rotations.clear();model.pose_at(0)
 var samples:Array=[];var previous_hip:=Vector3.ZERO;var previous_action:=""
 var max_step:=0.0;var min_sole:=INF;var max_boundary_step:=0.0
 for requested:String in ["sit_chair","sit_chair_hold","stand_up_chair","idle"]:
  if model.action!=requested:model.play(requested,"front",true)
  var frames:int=ceili(model.action_duration()*30)+1 if requested in ["sit_chair","stand_up_chair"] else 8
  for frame in frames:
   model._process(1.0/30.0)
   await RenderingServer.frame_post_draw
   var hip:Vector3=model.rig.transform*(body.get_solved_bone_pose(body.skeleton.find_bone("hip")).origin+body.root_offset)
   var step:float=hip.distance_to(previous_hip) if not samples.is_empty() else 0.0
   max_step=maxf(max_step,step)
   if previous_action!=model.action:max_boundary_step=maxf(max_boundary_step,step)
   var soles:Array=[]
   for ids in support.sole_vertices:
    var low:=INF
    for id in ids:low=minf(low,(model.rig.transform*(body.posed_points[id]+body.root_offset)).y)
    min_sole=minf(min_sole,low);soles.append(low)
   samples.append({"action":model.action,"time":model.elapsed,"hip":[hip.x,hip.y,hip.z],"step_m":step,"adjustment_m":support.root_adjustment,"soles_y_m":soles})
   if frame in [0,frames/2,frames-1] or previous_action!=model.action:
    view.viewport.get_texture().get_image().save_png(folder+"/%s_%03d.png"%[requested,frame])
   assert(body.pose_sync_error.is_empty())
   previous_hip=hip;previous_action=model.action
   await process_frame
 assert(model.action=="idle" and not support.bridge.modifier.active)
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"height":height,"maximum_hip_frame_step_m":max_step,"maximum_action_boundary_step_m":max_boundary_step,"minimum_sole_y_m":min_sole,"samples":samples,"scope":"Fixed seat continuous entry/hold/exit diagnostic, no cloth or footwear"},"  "));file.close()
 print("Seat transition: max hip step ",max_step," minimum sole ",min_sole)
 assert(min_sole>-.003,"Transition foot penetrated floor by over 3 mm")
 assert(max_boundary_step<.02,"Action boundary introduced a hip jump over 2 cm")
 view.free()
 for frame in 3:await process_frame
 quit()
