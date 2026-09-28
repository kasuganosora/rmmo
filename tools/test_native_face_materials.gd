extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(90).timeout.connect(func():push_error("Native facial material validation timed out");quit(2))
 var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
 view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":0}}, {})
 view.model.set_process(false);view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.3)
 var mesh:MeshInstance3D=view.model.axis_rig.body.mesh_instance
 var found:Array[String]=[]
 for i in mesh.mesh.get_surface_count():
  var mat:Material=mesh.get_active_material(i)
  var name:String=mat.get_meta("native_face_surface","")
  if name.is_empty():continue
  assert(mat is ShaderMaterial and mat.shader.code.contains("body_positions"),"Native face lost dynamic deformation")
  found.append(name)
  if name not in ["EyeReflection","Tear"]:
   var tex:Texture2D=mat.get_shader_parameter("alpha_map" if name in ["Eyelashes","Cornea"] else "albedo_map")
   assert(tex!=null and tex.get_width()==2048,"Missing native atlas")
  if name=="Eyelashes":assert(is_equal_approx(mat.get_shader_parameter("cutoff"),.3))
  if name=="EyeReflection":assert(mat.render_priority==1)
  if name=="Tear":assert(mat.get_shader_parameter("tint").a==0.0 and mat.render_priority==2)
 found.sort();assert(found==["Cornea","EyeReflection","Eyelashes","Gums","InnerMouth","Tear","Teeth","Tongue"])
 view.viewport.size=Vector2i(640,640);view.viewport.msaa_3d=Viewport.MSAA_4X
 view.camera.size=.38
 var folder:String=Art.review_path("character_3d/native_face_03")
 DirAccess.make_dir_recursive_absolute(folder)
 var light:DirectionalLight3D=view.viewport.find_children("*","DirectionalLight3D",true,false)[0]
 for lighting in 2:
  light.rotation_degrees=Vector3(-35,-30,0) if lighting==0 else Vector3(-15,30,0)
  for side in [0,1]:
   view.camera.position=Vector3(0 if side==0 else 2.0,1.63,4)
   view.camera.look_at(Vector3(0,1.63,0))
   for enabled in [false,true]:
    for i in mesh.mesh.get_surface_count():
     var mat:Material=mesh.get_active_material(i)
     if mat.get_meta("native_face_surface","") in ["Cornea","EyeReflection","Tear"]:mat.set_shader_parameter("overlay_enabled",float(enabled))
    for frame in 8:await process_frame
    await RenderingServer.frame_post_draw
    assert(view.viewport.get_texture().get_image().save_png(folder+"/face_light%s_side%s_on%s.png"%[lighting,side,int(enabled)])==OK)
 # Exercise original lower-jaw weights, not a fabricated expression morph.
 var body=view.model.axis_rig.body
 var angles:Dictionary={}
 for node:Dictionary in body.nodes:angles[node.name]=node.angles*180.0/PI
 assert(angles.has("lowerJaw"))
 angles["lowerJaw"]=Vector3(18,0,0)
 body.set_angles(angles,body.root_offset)
 view.camera.position=Vector3(0,1.57,4);view.camera.look_at(Vector3(0,1.57,0))
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
 assert(view.viewport.get_texture().get_image().save_png(folder+"/jaw_open.png")==OK)
 view.free()
 for frame in 3:await process_frame
 print("PASS eight original facial materials, dynamic deformation and overlay order; WROTE two light/two view/on-off and jaw diagnostic views")
 quit()
