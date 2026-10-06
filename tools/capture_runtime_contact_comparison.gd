extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(240).timeout.connect(func():push_error("Runtime contact comparison timeout");quit(2))
 var view=View.new();root.add_child(view)
 var parts={"SurfaceEquipment":{"Clothing1":"maid_separate/item_02","Clothing2":"maid_separate/item_01","UnderwearTop":"underlayer_lace/item_00","UnderwearBottom":"underlayer_briefs/item_00"}}
 view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},parts)
 view.model.set_process(false);view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
 view.viewport.size=Vector2i(640,800);view.camera.size=2.2
 var body=view.model.axis_rig.body;var wardrobe=view.model.axis_rig.wardrobe
 var before:PackedVector3Array=body.posed_points.duplicate();var original_position:Vector3=body.position
 var use_candidate:bool=OS.get_cmdline_user_args().has("--candidate")
 var folder:String=Art.review_path("character_3d/runtime_contact_comparison_02" if use_candidate else "character_3d/runtime_contact_comparison_01");DirAccess.make_dir_recursive_absolute(folder)
 var maximum_error:=0.0
 for enabled in [false,true]:
  if enabled:
   if use_candidate:
    var original_angles:Dictionary={}
    for node:Dictionary in body.nodes:original_angles[node.name]=node.angles*180.0/PI
    var original_offset:Vector3=body.root_offset
    body.set_angles({},original_offset)
    var adapter=preload("res://scripts/char/garment_candidate_cloth.gd").new();body.add_child(adapter)
    assert(adapter.initialize(wardrobe.garments.Clothing2),adapter.frame_error)
    for frame in 5:await process_frame
    for frame in 65:
     var angles:Dictionary={}
     for bone:String in original_angles:angles[bone]=original_angles[bone]*minf(float(frame+1)/45.0,1.0)
     body.set_angles(angles,original_offset)
     assert(adapter.advance(1.0/60.0),adapter.frame_error)
     await process_frame
     await RenderingServer.frame_post_draw
     if frame%20==0:print("Candidate warm frame ",frame)
   else:
    assert(wardrobe.warm_start_cloth())
   for i in before.size():maximum_error=maxf(maximum_error,before[i].distance_to(body.posed_points[i]))
   assert(maximum_error<.00001 and body.position.is_equal_approx(original_position),"Contact changed wearer pose")
   if not use_candidate:
    for frame in 12:wardrobe.step_cloth()
  for side in 2:
   view.camera.position=Vector3(0 if side==0 else 4,1,4 if side==0 else 0);view.camera.look_at(Vector3(0,1,0))
   for frame in 5:await process_frame
   await RenderingServer.frame_post_draw
   assert(view.viewport.get_texture().get_image().save_png(folder+"/%s_%d.png"%["on" if enabled else "off",side])==OK)
  print("Captured contact enabled=",enabled)
 var report={"wearer_maximum_error_m":maximum_error,"solver":"existing candidate plugin, skirt only, 65-frame warm transition" if use_candidate else "existing garment_cloth_gpu, 80 warm-start steps then 12 settle frames","visual_accepted":false}
 var file:=FileAccess.open(folder+"/comparison.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("CONTACT COMPARISON COMPLETE: inspect visual before runtime promotion; ",report)
 quit()
