extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(120).timeout.connect(func():push_error("Expression test timeout");quit(2))
 var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
 view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":0}},{})
 var model=view.model;model.set_process(false);model.pose_at(.2)
 var body=model.axis_rig.body;var before:PackedVector3Array=body.rest_points.duplicate()
 var identity:int=body.get_instance_id()
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/native_expressions_03")
 DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(640,640);view.camera.size=.55;view.camera.position=Vector3(0,1.62,3);view.camera.look_at(Vector3(0,1.62,0))
 for entry in [{"name":"neutral","weights":{}},{"name":"blink","weights":{"blink":1.0}},{"name":"wink_left","weights":{"wink_left":1.0}},{"name":"smile","weights":{"smile":.7,"brow_worried":.3}}]:
  assert(model.set_expressions(entry.weights))
  if not entry.weights.is_empty():assert(before!=body.rest_points,"Expression has no visible geometry effect")
  assert(identity==body.get_instance_id())
  await RenderingServer.frame_post_draw
  view.viewport.get_texture().get_image().save_png(folder+"/"+entry.name+".png")
  await process_frame
 assert(not model.set_expressions({"unsupported":1.0}))
 assert(model.set_expressions({}) and before==body.rest_points,"Expression reset drifted from identity")
 assert(model.transition_expressions({"blink":1.0},.2))
 model._process(.1)
 assert(absf(float(body.expression_values.blink)-.5)<.001,"Expression did not blend halfway")
 var halfway:PackedVector3Array=body.rest_points.duplicate()
 assert(model.transition_expressions({},.2) and halfway==body.rest_points,"Interrupting expression snapped geometry")
 model._process(.2)
 assert(body.expression_values.is_empty() and before==body.rest_points,"Interrupted expression did not reset")
 assert(body.set_shape_values({"height":-.25,"nose_width":.2}))
 var shaped:PackedVector3Array=body.rest_points.duplicate()
 assert(model.set_expressions({"blink":.5}))
 assert(model.set_expressions({}) and shaped==body.rest_points,"Reset erased body identity")
 var jaw:int=body.skeleton.find_bone("lowerJaw")
 var neutral_jaw:Quaternion=body.skeleton.get_bone_pose_rotation(jaw)
 for vowel:String in ["a","i","u","e","o"]:
  assert(model.set_expressions({vowel:1.0}))
  assert(not body.skeleton.get_bone_pose_rotation(jaw).is_equal_approx(neutral_jaw),"Mouth ignored jaw formula")
  var expected:Quaternion=body.skeleton.get_bone_pose_rotation(jaw)
  for frame in 3:model._process(1.0/60)
  assert(body.skeleton.get_bone_pose_rotation(jaw).is_equal_approx(expected),"Jaw formula accumulated or animation erased expression")
  await RenderingServer.frame_post_draw
  view.viewport.get_texture().get_image().save_png(folder+"/vowel_"+vowel+".png")
  await process_frame
  assert(model.set_expressions({}) and shaped==body.rest_points)
  assert(body.skeleton.get_bone_pose_rotation(jaw).is_equal_approx(neutral_jaw),"Jaw did not restore after clearing mouth")
 for effect:String in ["heart_eyes","star_eyes","circle_eyes","blush"]:
  assert(model.set_expressions({effect:1.0}))
  assert(shaped==body.rest_points,"Material expression changed the base geometry")
  await RenderingServer.frame_post_draw
  view.viewport.get_texture().get_image().save_png(folder+"/"+effect+".png")
  await process_frame
 assert(model.set_expressions({"a":1.0,"i":1.0,"blink":.4,"blush":.6}))
 assert(body.expression_values.a==.5 and body.expression_values.i==.5)
 view.camera.position=Vector3(3,1.62,0);view.camera.look_at(Vector3(0,1.62,0))
 await RenderingServer.frame_post_draw
 view.viewport.get_texture().get_image().save_png(folder+"/combined_side.png")
 await process_frame
 assert(model.set_expressions({}) and shaped==body.rest_points)
 for surface in body.topology.materials.size():
  var material:ShaderMaterial=body.mesh_instance.get_active_material(surface)
  if body.topology.materials[surface] in ["Irises","Pupils"]:assert(float(material.get_shader_parameter("expression_heart"))==0 and float(material.get_shader_parameter("expression_circle"))==0)
 for shape in [-.6,0.0,.6]:
  assert(body.set_shape_values({"height":shape,"nose_width":shape}))
  var head:Vector3=body.rests.head.origin
  for label:String in ["eye_smile","eye_surprise","eye_squeeze"]:
   var weights:Dictionary={label:1,"blush":.35}
   weights["brow_smile" if label=="eye_smile" else "brow_serious"]=.5
   if label=="eye_surprise":weights["o"]=.7
   assert(model.set_expressions(weights))
   for facing in [0,1]:
    view.camera.position=Vector3(0,head.y,3) if facing==0 else Vector3(3,head.y,0)
    view.camera.look_at(Vector3(0,head.y,0))
    await RenderingServer.frame_post_draw
    view.viewport.get_texture().get_image().save_png(folder+"/%s_%s_%d.png"%[label,str(shape),facing])
    await process_frame
   assert(model.set_expressions({}))
 # Reuse keeps expression; structural replacement must cancel pending state.
 assert(model.transition_expressions({"a":1,"blush":1},.5))
 var recipe:Dictionary=model.appearance.duplicate(true)
 recipe["body_shapes"]={"height":.2}
 model.configure("female",recipe,{})
 assert(model.axis_rig.body.get_instance_id()==identity)
 model._process(.5)
 assert(model.expression_target().has_all(["a","blush"]))
 model.configure("young_female",{},{})
 assert(model.expression_target().is_empty() and model._expression_duration==0)
 model.configure("female",recipe,{})
 model._process(.5)
 assert(model.axis_rig.body.expression_values.is_empty(),"New body inherited old facial transition")
 print("PASS native mouth formulas, materials, blending/reset, identity reuse and structural replacement cancellation")
 view.free();await process_frame;quit()
