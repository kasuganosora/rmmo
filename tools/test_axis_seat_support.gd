extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Seat support timeout");quit(2))
 var view=View.new();root.add_child(view)
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 var gear={"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}
 view.configure("female",recipe,gear);view.model.set_process(false)
 var body=view.model.axis_rig.body
 var support=view.model.axis_rig.seat
 var chair:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.5,.04,.5);chair.mesh=box
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color("aeb4b8");chair.material_override=mat;view.viewport.add_child(chair)
 var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(4,4);floor_mesh.mesh=plane
 floor_mesh.material_override=mat;view.viewport.add_child(floor_mesh)
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_seat_support_02");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(800,640);view.camera.size=2.5;view.camera.position=Vector3(3,1.8,3);view.camera.look_at(Vector3(0,.9,0))
 var results:Array=[]
 for height:float in [-1.0,0.0,1.0]:
  support.clear();recipe.body_shapes={"height":height};view.model.configure("female",recipe,gear)
  view.model.play("sit_chair_hold","front",true);view.model._from_rotations.clear();view.model.pose_at(0)
  var pelvis:Vector3=view.model.rig.transform*body.get_solved_bone_pose(body.skeleton.find_bone("hip")).origin
  var seat:=Vector3(pelvis.x,.46,pelvis.z);chair.position=seat-Vector3(0,.02,0)
  support.set_seat(seat,Vector2(.5,.5))
  view.model.axis_rig.finish_frame(view.model,1.0/60.0)
  await RenderingServer.frame_post_draw
  assert(support.bridge.completed_revision==support.bridge.revision and support.bridge.error.is_empty())
  var bottom:=INF
  for index in support.seat_vertices:bottom=minf(bottom,(view.model.rig.transform*(body.posed_points[index]+body.root_offset)).y)
  var soles:Array=[]
  for ids in support.sole_vertices:
   var low:=INF
   for index in ids:low=minf(low,(view.model.rig.transform*(body.posed_points[index]+body.root_offset)).y)
   soles.append(low)
  results.append({"height":height,"seat_gap_m":bottom-seat.y,"soles_y_m":soles,"root_adjustment_m":support.root_adjustment})
  assert(absf(bottom-seat.y)<.003,"Seat penetration exceeds 3 mm")
  for low in soles:assert(absf(low)<.001,"Planted sole exceeds 1 mm")
  assert(view.viewport.get_texture().get_image().save_png(folder+"/height_%s.png"%str(height))==OK)
  print("Seat probe ",results.back())
  await process_frame
  # Same fixed chair, several real Model frames: root correction must not accumulate.
  for frame in 5:
   view.model._process(1.0/60.0)
   await RenderingServer.frame_post_draw
   assert(support.bridge.completed_revision==support.bridge.revision)
   assert(absf(support.root_adjustment)<.15,"Seat root correction accumulated")
   for ids in support.sole_vertices:
    var low:=INF
    for index in ids:low=minf(low,(view.model.rig.transform*(body.posed_points[index]+body.root_offset)).y)
    assert(absf(low)<.001,"Continuous hold lost floor contact")
   await process_frame
  view.model.play("stand_up_chair","front",true);view.model._process(1.0/60.0)
  await RenderingServer.frame_post_draw
  assert(support.bridge.modifier.active,"Initial rise lost planted-foot support")
  view.model.play("idle","front",true);view.model._process(1.0/60.0)
  await RenderingServer.frame_post_draw
  assert(not support.bridge.modifier.active,"Seat constraint survived completed exit")
  support.clear();assert(not support.enabled)
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify({"results":results,"scope":"Shared AxisRig hold support and release only; continuous entry/exit checked separately, footwear and cloth contact not accepted"},"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 quit()
