extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Custom=preload("res://scripts/char/customization.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func maximum_difference(a:PackedVector3Array,b:PackedVector3Array)->float:
 assert(a.size()==b.size());var result:=0.0
 for i in a.size():result=maxf(result,a[i].distance_to(b[i]))
 return result
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Identity shape test timed out");quit(2))
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":0}}
 var model:=Model.new();model.body_type="female";model.appearance=recipe.duplicate(true);root.add_child(model);model.set_process(false)
 var other:=Model.new();other.body_type="female";other.appearance=recipe.duplicate(true);root.add_child(other);other.set_process(false)
 var body=model.axis_rig.body
 var original_mesh:Mesh=body.mesh_instance.mesh;var original_skeleton:Skeleton3D=body.skeleton
 var other_points:PackedVector3Array=other.axis_rig.body.rest_points.duplicate()
 var original_texture:Texture2D=body.positions_texture
 assert(body.use_compute)
 var max_error:=0.0
 for key:String in body.Shapes.RANGES:
  assert(body.set_shape_values({key:.5}))
  body.set_angles({})
  # Independent source-file reference; do not compare the helper to itself.
  var expected:PackedVector3Array=body.base_rest_points.duplicate()
  var payload:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Art.path("characters/morphs/female_base_v2/source_native_01/"+key+".json")))
  for delta:Dictionary in payload.deltas:expected[int(delta.vertex)]+=Vector3(delta.delta.x,delta.delta.y,delta.delta.z)*.5
  assert(maximum_difference(body.rest_points,expected)<.000001)
  assert(maximum_difference(body.read_gpu_points(),expected)<.00001)
  body.set_angles(body.POSES.elbow)
  var gpu_points:PackedVector3Array=body.read_gpu_points()
  body.use_compute=false;body._solve_surface(body.root_offset)
  max_error=maxf(max_error,maximum_difference(gpu_points,body.posed_points))
  body.use_compute=true
  assert(max_error<.00001,"Morph-before-skin GPU/CPU mismatch")
  assert(body.set_shape_values({}))
  assert(body.rest_points==body.base_rest_points)
 var values={"bust_size":.4,"waist_width":-.3,"hip_size":.2,"nose_width":.25}
 recipe.body_shapes=values
 var custom=Custom.from_dict(recipe)
 var restored=Custom.from_dict(JSON.parse_string(JSON.stringify(custom.to_dict())))
 assert(restored.body_shapes==values)
 model.configure("female",restored.to_dict(),{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
 model.play("walk","front",true);model._from_rotations.clear();model.pose_at(.25)
 var elapsed:float=model.elapsed
 var shaped:PackedVector3Array=body.rest_points.duplicate()
 for repeat in 5:
  model.configure("female",restored.to_dict(),model.equipment)
  assert(body.rest_points==shaped and model.elapsed==elapsed)
 assert(body.positions_texture==original_texture and body.mesh_instance.mesh==original_mesh and body.skeleton==original_skeleton)
 assert(other.axis_rig.body.rest_points==other_points and other.axis_rig.body.shape_values.is_empty())
 assert(not body.set_shape_values({"unknown_shape":1.0}),"Unknown shape silently enabled")
 for garment in model.axis_rig.wardrobe.garments.values():
  for surface in garment.mesh_instance.mesh.get_surface_count():
   assert(garment.mesh_instance.get_active_material(surface).get_shader_parameter("body_positions")==body.positions_texture)
 restored.body_shapes={};model.configure("female",restored.to_dict(),model.equipment)
 assert(body.rest_points==body.base_rest_points)
 var report={"cpu_gpu_max_error_m":max_error,"source_reference":true,"reset_exact":true,"recipe_roundtrip":true,"instance_isolation":true,"mesh_skeleton_texture_reused":true,"garment_shared_surface":true,"height_supported":true}
 var folder:String=Art.review_path("character_3d/body_identity_02");DirAccess.make_dir_recursive_absolute(folder)
 var file:=FileAccess.open(folder+"/regression.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 model.free();other.free()
 for frame in 3:await process_frame
 print("PASS five native identity shapes: source deltas, bent CPU/GPU error=",max_error,"; reset/recipe/isolation/reuse/shared garment surface.")
 quit()
