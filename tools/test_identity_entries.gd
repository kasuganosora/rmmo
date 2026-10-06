extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Portrait identity timed out");quit(2))
 var ui=load("res://scenes/character_select.tscn").instantiate();root.add_child(ui)
 await create_timer(.8).timeout
 var chars:Array=[]
 for amount:float in [-1.0,1.0]:
  chars.append({"id":chars.size()+1,"name":"Height portrait","gender":"female","customization":{"body_model":"female_base_v2","body_shapes":{"height":amount,"nose_width":.3},"part_ids":{"FrontHair1":202}}})
 ui._on_chars(chars)
 var folder:String=Art.review_path("character_3d/identity_entries_01");DirAccess.make_dir_recursive_absolute(folder)
 var results:Array=[]
 for i in chars.size():
  ui.list.select(i);ui._show_character(i)
  var view=ui._view;view.model.set_process(false)
  assert(view.model.appearance==chars[i].customization)
  var body=view.model.axis_rig.body
  var cutoff:float=lerpf(body.base_rests.neck.origin.y,body.base_rests.head.origin.y,.5)
  var min_y:=INF;var max_y:=-INF
  for j in body.base_rest_points.size():
   if body.base_rest_points[j].y<cutoff:continue
   var pixel:Vector2=view.camera.unproject_position(body.global_transform*(body.posed_points[j]+body.root_offset))
   min_y=minf(min_y,pixel.y);max_y=maxf(max_y,pixel.y)
  assert(min_y>0 and max_y<view.viewport.size.y,"Anatomical head cropped in selection portrait")
  var npc=Model.create_npc({"gender":"female","customization":chars[i].customization,"equipment":{}});root.add_child(npc);npc.set_process(false)
  assert(npc.appearance==view.model.appearance)
  assert(npc.axis_rig.body.rest_points==body.rest_points)
  assert(npc.axis_rig.hair.fit.is_equal_approx(view.model.axis_rig.hair.fit))
  var snapshot:PackedVector3Array=body.rest_points.duplicate()
  var changed:Dictionary=chars[i].customization.duplicate(true);changed.body_shapes.height=0.0
  npc.configure("female",changed,{})
  assert(body.rest_points==snapshot,"NPC edit mutated selection avatar")
  npc.free()
  for frame in 5:await process_frame
  await RenderingServer.frame_post_draw
  assert(view.viewport.get_texture().get_image().save_png(folder+"/portrait_%d.png"%i)==OK)
  var fitted_transform:Transform3D=view.camera.transform;var fitted_size:float=view.camera.size
  view.camera.size=.58;view.camera.position=Vector3(0,1.75,4);view.camera.look_at(Vector3(0,1.69,0))
  for frame in 3:await process_frame
  await RenderingServer.frame_post_draw
  assert(view.viewport.get_texture().get_image().save_png(folder+"/legacy_fixed_portrait_%d.png"%i)==OK)
  view.camera.transform=fitted_transform;view.camera.size=fitted_size
  results.append({"height_weight":chars[i].customization.body_shapes.height,"head_pixel_min_y":min_y,"head_pixel_max_y":max_y,"camera_size":view.camera.size,"camera_y":view.camera.position.y})
 assert(absf(results[0].camera_y-results[1].camera_y)>.1,"Portrait camera did not follow height")
 var file:=FileAccess.open(folder+"/entry_regression.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 ui.free()
 for frame in 3:await process_frame
 print("PASS actual selection portraits and NPC identity/isolation: ",results)
 quit()
