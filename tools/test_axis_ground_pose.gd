extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(120).timeout.connect(func():push_error("Ground pose timeout");quit(2))
 var view=View.new();root.add_child(view)
 var height:=0.0
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--height="):height=float(arg.trim_prefix("--height="))
 view.configure("female",{"body_model":"female_base_v2","body_shapes":{"height":height},"part_ids":{"FrontHair1":202}},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
 view.model.set_process(false)
 var body=view.model.axis_rig.body
 var folder:String=Art.review_path("character_3d/axis_ground_pose_01")
 var motion=preload("res://scripts/char/character_axis_animation.gd").new()
 assert(motion.install(body.skeleton,load(folder+"/candidate.res")))
 assert(motion.apply(body,"sit_ground",0));view.model.rig.position=motion.visual_offset
 var candidate=null
 if "--support" in OS.get_cmdline_user_args():
  folder=Art.review_path("character_3d/axis_ground_pose_04/height_%s"%str(height));DirAccess.make_dir_recursive_absolute(folder)
  candidate=preload("res://tools/ground_support_candidate.gd").new()
  assert(candidate.prepare(view.model),candidate.error)
  await RenderingServer.frame_post_draw
  assert(candidate.bridge.completed_revision==candidate.bridge.revision)
 var lowest:=INF;var highest:=-INF
 for p:Vector3 in body.posed_points:
  var y:float=p.y+body.root_offset.y+view.model.rig.position.y
  lowest=minf(lowest,y);highest=maxf(highest,y)
 var report:=FileAccess.open(folder+"/report.json",FileAccess.WRITE)
 var hands:Array=[]
 if candidate!=null:
  for ids in candidate.hand_vertices:
   var low:=INF
   for id in ids:low=minf(low,(view.model.rig.transform*(body.posed_points[id]+body.root_offset)).y)
   hands.append(low)
 var hip_low:=INF;var foot_low:=INF
 if candidate!=null:
  for id in candidate.hip_vertices:hip_low=minf(hip_low,(view.model.rig.transform*(body.posed_points[id]+body.root_offset)).y)
  for id in candidate.foot_vertices:foot_low=minf(foot_low,(view.model.rig.transform*(body.posed_points[id]+body.root_offset)).y)
 report.store_string(JSON.stringify({"minimum_body_y_m":lowest,"maximum_body_y_m":highest,"source_support_lift_m":motion.support_adjustment,"hands_minimum_y_m":hands,"hip_minimum_y_m":hip_low,"foot_minimum_y_m":foot_low,"leg_adjustment_degrees":candidate.leg_degrees if candidate!=null else 0,"trunk_adjustment_degrees":candidate.lean_degrees if candidate!=null else 0,"visual_accepted":false,"scope":"Native sitting003 pose candidate; full palm contact and transitions pending"},"  "));report.close()
 print("Ground candidate minimum y ",lowest," support lift ",motion.support_adjustment)
 if candidate!=null:
  assert(absf(hip_low)<.003 and absf(foot_low)<.003,"Ground hip/foot support exceeds 3 mm")
  for low in hands:assert(absf(low)<.003,"Hand support exceeds 3 mm")
  assert(lowest>-.001,"Supported body penetrates ground")
 var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(4,4);floor_mesh.mesh=plane
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color("aeb4b8");floor_mesh.material_override=mat;view.viewport.add_child(floor_mesh)
 view.viewport.size=Vector2i(800,640);view.camera.size=1.8
 for side:int in 3:
  view.camera.position=[Vector3(0,1,3),Vector3(3,1,.5),Vector3(1,1,-3)][side];view.camera.look_at(Vector3(0,.5,0))
  await RenderingServer.frame_post_draw
  assert(view.viewport.get_texture().get_image().save_png(folder+"/view_%d.png"%side)==OK)
  await process_frame
 print("Native ground pose candidate captured; visual review required")
 view.free()
 for frame in 3:await process_frame
 quit()
