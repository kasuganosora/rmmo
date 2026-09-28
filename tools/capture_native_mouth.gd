extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(90).timeout.connect(func():push_error("Mouth diagnostic timed out");quit(2))
 var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
 view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":0}}, {})
 view.model.set_process(false);view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.3)
 var body=view.model.axis_rig.body
 var mesh:MeshInstance3D=body.mesh_instance
 var originals:Array[Material]=[]
 for i in mesh.mesh.get_surface_count():originals.append(mesh.get_active_material(i))
 var hidden:=ShaderMaterial.new();hidden.shader=Shader.new()
 hidden.shader.code="shader_type spatial;\n"+body.VERTEX_CODE+"void fragment(){ALPHA=0.0;}"
 for uniform:Dictionary in originals[0].shader.get_shader_uniform_list():
  if uniform.name in ["body_positions","body_normals","subdivision_weights"]:hidden.set_shader_parameter(uniform.name,originals[0].get_shader_parameter(uniform.name))
 var angles:Dictionary={}
 for node:Dictionary in body.nodes:angles[node.name]=node.angles*180.0/PI
 view.viewport.size=Vector2i(640,640);view.viewport.msaa_3d=Viewport.MSAA_4X
 view.camera.size=.18;view.camera.position=Vector3(0,1.595,4);view.camera.look_at(Vector3(0,1.595,0))
 var folder:String=Art.review_path("character_3d/native_mouth_02")
 DirAccess.make_dir_recursive_absolute(folder)
 var jaw_points:Dictionary={}
 for isolated in [false,true]:
  for i in originals.size():
   var oral:bool=originals[i].get_meta("native_face_surface","") in ["Teeth","Tongue","Gums","InnerMouth"]
   mesh.set_surface_override_material(i,originals[i] if oral or not isolated else hidden)
  for jaw in [0,18]:
   angles.lowerJaw=Vector3(jaw,0,0);body.set_angles(angles,body.root_offset)
   jaw_points[jaw]=(body.read_gpu_points() if body.use_compute else body.posed_points).duplicate()
   for mapped in [false,true]:
    var normals:=0
    for mat:Material in originals:
     if mat.get_meta("native_face_surface","") in ["Teeth","Tongue"]:
      assert(mat.get_shader_parameter("packed_normal_map")!=null)
      assert(is_equal_approx(mat.get_shader_parameter("normal_depth"),1.0 if mat.get_meta("native_face_surface")=="Teeth" else .2))
      mat.set_shader_parameter("use_normal_map",mapped);normals+=1
    assert(normals==2)
    for frame in 6:await process_frame
    await RenderingServer.frame_post_draw
    assert(view.viewport.get_texture().get_image().save_png(folder+"/isolated%s_jaw%s_normal%s.png"%[int(isolated),jaw,int(mapped)])==OK)
 var upper_max:=0.0;var lower_length_error:=0.0
 for node:Dictionary in body.nodes:
  if node.name=="upperJaw":
   for vertex in node.full:upper_max=maxf(upper_max,jaw_points[0][int(vertex)].distance_to(jaw_points[18][int(vertex)]))
  if node.name=="lowerJaw":
   var anchor:int=node.full[0]
   for vertex in node.full:
    lower_length_error=maxf(lower_length_error,absf(jaw_points[0][anchor].distance_to(jaw_points[0][int(vertex)])-jaw_points[18][anchor].distance_to(jaw_points[18][int(vertex)])))
 assert(upper_max<.00001 and lower_length_error<.00001,"Lower jaw moved upper dental arch or deformed fully weighted points")
 var report={"upper_jaw_max_displacement_m":upper_max,"lower_jaw_full_weight_distance_error_m":lower_length_error,"scope":"Original bone diagnostic, not lip expression validation"}
 var file:=FileAccess.open(folder+"/binding_check.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("WROTE original mouth surfaces: rest/jaw, complete/isolated, packed normals on/off; diagnostic only")
 quit()
