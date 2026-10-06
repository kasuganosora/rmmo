extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(150).timeout.connect(func():push_error("Expression studio timeout");quit(2))
 var studio=preload("res://tools/character_skin_studio.gd").new()
 studio.interactive=false;root.add_child(studio)
 studio.model.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":0}}, {})
 var model=studio.model;var body=model.axis_rig.body
 var identity:int=body.get_instance_id()
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/expression_studio_01")
 DirAccess.make_dir_recursive_absolute(folder)
 studio.camera.size=.6
 for lighting in ["studio","game"]:
  if lighting=="game":studio.toggle_lighting()
  for entry in [{"id":"smile","action":"idle","weights":{"eye_smile":1,"brow_smile":.6,"mouth_smile":.7,"blush":.3}},{"id":"surprise","action":"walk","weights":{"eye_surprise":1,"brow_up":.5,"o":.7}},{"id":"squeeze","action":"attack","weights":{"eye_squeeze":1,"brow_serious":.7,"a":.25}}]:
   assert(model.set_expressions(entry.weights))
   model.play(entry.action,"front",true)
   for phase in 8:model._process(1.0/30)
   assert(body.get_instance_id()==identity and not body.expression_values.is_empty())
   for angle in [0,1]:
    var head:Vector3=body.skeleton.get_bone_global_pose(body.skeleton.find_bone("head")).origin+body.root_offset
    var target:Vector3=body.to_global(head)
    studio.camera.position=target+Vector3(0 if angle==0 else 3,0,3 if angle==0 else 0)
    studio.camera.look_at(target)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(folder+"/%s_%s_%d.png"%[lighting,entry.id,angle])
    await process_frame
   assert(model.set_expressions({}))
 studio.free();await process_frame
 print("PASS original studio/game lighting, idle/walk/attack expression coexistence and instance reuse; visual screenshots require inspection")
 quit()
