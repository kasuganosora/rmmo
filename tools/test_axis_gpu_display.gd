extends SceneTree
const Body=preload("res://scripts/char/female_axis_body.gd")
const GPU=preload("res://scripts/char/female_axis_gpu.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
var images:Array[PackedByteArray]=[]
func capture(display:RefCounted)->void:
 images=[display.rd.texture_get_data(display.positions.texture_rd_rid,0),display.rd.texture_get_data(display.normals.texture_rd_rid,0)]
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Display timeout");quit(2))
 Body.default_gpu_display=true
 var body=Body.new();root.add_child(body);body.initialize();assert(body.enable_compute());assert(body.gpu_display!=null)
 var reference=GPU.new();assert(reference.initialize(Art.path("characters/base/female_base_v2")))
 var max_error:=0.0
 var destination:=Node3D.new();root.add_child(destination)
 var original_positions=body.positions_texture
 var original_normals=body.normals_texture
 for i in 12:
  if i%3==0:
   body.get_parent().remove_child(body)
   assert(body.gpu!=null and body.gpu_display!=null,"Detaching a live body released its GPU state")
   body.set_angles({"rThigh":Vector3(i+1,0,0)})
   (destination if i%2==0 else root).add_child(body)
   assert(body.positions_texture==original_positions and body.normals_texture==original_normals)
  assert(body.set_shape_values({"height":float(i%3-1)*.3,"bust_size":.2}))
  assert(body.set_expressions({"blink":float(i%3)*.5,"smile":float(i%2)*.7}))
  var pose:Dictionary={"lShldr":Vector3(i*2,0,0),"rThigh":Vector3(i,0,0)} if i<9 else Body.POSES[["sit","lie_relaxed","elbow"][i-9]]
  body.set_angles(pose,Vector3(.13,-.04,.02))
  assert(reference.set_rest_points(body.rest_points));reference.evaluate(body.nodes,body.solved_bones,body.bulge_scale,body.root_offset)
  RenderingServer.call_on_render_thread(capture.bind(body.gpu_display));RenderingServer.force_sync()
  assert(body.gpu.last_readback_bytes==260020 and body.gpu.last_positions.is_empty() and body.gpu.last_normals.is_empty())
  assert(body.gpu.last_points==reference.last_points and body.gpu.last_min_y==reference.last_min_y)
  assert(images[0]==reference.last_positions,"Position display changed")
  var a:=images[1].to_float32_array();var b:PackedFloat32Array=reference.last_normals.to_float32_array()
  for j in a.size():
   assert(is_finite(a[j]));max_error=maxf(max_error,absf(a[j]-b[j]))
  if max_error>=.000001:push_error("Normal display changed: "+str(max_error));quit(1);return
 var texture=body.positions_texture
 reference.close()
 for i in 2:await process_frame
 body.queue_free()
 for i in 4:await process_frame
 assert(texture.get_width()==0 and texture.get_height()==0)
 for i in 4:await process_frame
 var automatic=preload("res://scripts/char/female_axis_display.gd").new()
 assert(automatic.initialize(Art.path("characters/base/female_base_v2")))
 automatic=null
 for i in 4:await process_frame
 print("PASS GPU display 12 shape/expression/pose/offset cases, four live reparentings, exact positions/contact/bounds, normal max error=",max_error," final texture disposal");quit()

