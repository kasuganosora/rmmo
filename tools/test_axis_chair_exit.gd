extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(150).timeout.connect(func():push_error("Chair exit timeout");quit(2))
 var view=View.new();root.add_child(view)
 view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE});view.model.set_process(false)
 var body=view.model.axis_rig.body
 var chair:=Node3D.new();view.viewport.add_child(chair)
 # Fixed 46 cm seat. Do not move the chair along with the actor to hide gaps.
 for spec:Array in [[Vector3(.5,.04,.5),Vector3(0,.44,-.08)],[Vector3(.5,.45,.04),Vector3(0,.7,-.31)],[Vector3(.05,.42,.05),Vector3(-.22,.21,-.3)],[Vector3(.05,.42,.05),Vector3(.22,.21,-.3)],[Vector3(.05,.42,.05),Vector3(-.22,.21,.14)],[Vector3(.05,.42,.05),Vector3(.22,.21,.14)],[Vector3(5,.04,5),Vector3(0,-.02,0)]]:
  var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=spec[0];mesh.mesh=box;mesh.position=spec[1]
  var mat:=StandardMaterial3D.new();mat.albedo_color=Color("aeb4b8");mat.roughness=.9;mesh.material_override=mat
  if box.size.x>1:view.viewport.add_child(mesh)
  else:chair.add_child(mesh)
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_chair_exit_02");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(800,640);view.camera.size=2.6;view.camera.position=Vector3(3,1.8,3);view.camera.look_at(Vector3(0,.9,0))
 view.model.play("sit_chair","front",true)
 view.model.elapsed=view.model.action_duration();view.model._process(.01)
 assert(view.model.action=="sit_chair_hold")
 view.model._from_rotations.clear();view.model.pose_at(0)
 var pelvis:Vector3=view.model.rig.transform*(body.get_solved_bone_pose(body.skeleton.find_bone("hip")).origin+body.root_offset)
 chair.position=Vector3(pelvis.x,0,pelvis.z+.08)
 print("Fixed chair horizontal anchor ",chair.position," seated hip ",pelvis)
 var butt_bottom:=INF
 for p:Vector3 in body.posed_points:
  var world_point:Vector3=view.model.rig.transform*(p+body.root_offset)
  if absf(world_point.x-pelvis.x)<.18 and world_point.z>pelvis.z-.2 and world_point.z<pelvis.z+.08 and world_point.y<pelvis.y and world_point.y>pelvis.y-.25:butt_bottom=minf(butt_bottom,world_point.y)
 var report:=FileAccess.open(folder+"/seat_probe.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"seat_top_m":.46,"seated_pelvis_y_m":pelvis.y,"butt_region_bottom_m":butt_bottom,"seat_gap_m":butt_bottom-.46,"scope":"Geometric butt-region probe at initial seated pose; not full chair/body contact acceptance"},"  "));report.close()
 for action:String in ["sit_chair_hold","stand_up_chair"]:
  view.model.play(action,"front",true);view.model._from_rotations.clear()
  for amount:float in [0.0,.5,1.0]:
   view.model.pose_at(view.model.action_duration()*amount)
   assert(body.pose_sync_error.is_empty())
   for frame in 3:await process_frame
   await RenderingServer.frame_post_draw
   assert(view.viewport.get_texture().get_image().save_png(folder+"/%s_%d.png"%[action,int(amount*100)])==OK)
 view.model.elapsed=view.model.action_duration();view.model._process(.01)
 assert(view.model.action=="idle")
 view.free()
 for frame in 3:await process_frame
 print("PASS chair hold/exit action completion; fixed chair captures require visual contact review");quit()
