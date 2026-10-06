extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Recovery timeout");quit(2))
 var view=View.new();root.add_child(view)
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 var gear={"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}
 view.configure("female",recipe,gear);view.model.set_process(false)
 var body=view.model.axis_rig.body;var id:int=body.get_instance_id()
 var floor_mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(5,.04,5);floor_mesh.mesh=box;floor_mesh.position.y=-.02
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color("777c80");floor_mesh.material_override=mat;view.viewport.add_child(floor_mesh)
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_recovery_02");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(800,640)
 var rising:Array=[];var reverse_error:=0.0;var low:=INF
 for action:String in ["get_up","lie_down","lie"]:
  assert(view.model.axis_rig.supports(action))
  view.model.play(action,"front",true);view.model._from_rotations.clear()
  for fraction:float in [0.0,.25,.5,.75,1.0]:
   view.model.pose_at(view.model.action_duration()*fraction)
   assert(body.get_instance_id()==id and body.pose_sync_error.is_empty())
   var points:=PackedVector3Array()
   for p:Vector3 in body.posed_points:points.append(view.model.rig.transform*(p+body.root_offset))
   if action=="get_up":rising.append(points)
   if action=="lie_down":
    var previous:PackedVector3Array=rising[4-int(round(fraction*4))]
    for i in points.size():reverse_error=maxf(reverse_error,points[i].distance_to(previous[i]))
   var bounds:=AABB(points[0],Vector3.ZERO)
   for p:Vector3 in points:bounds=bounds.expand(p);low=minf(low,p.y)
   view.camera.size=maxf(2.3,bounds.size.length()*1.15)
   var center:Vector3=bounds.get_center();view.camera.position=center+Vector3(3,1.5,3);view.camera.look_at(center)
   for frame in 3:await process_frame
   await RenderingServer.frame_post_draw
   assert(view.viewport.get_texture().get_image().save_png(folder+"/%s_%02d.png"%[action,int(fraction*100)])==OK)
   if action=="lie":break
 assert(reverse_error<.00001 and low>=-.00001)
 var supports:Array=[]
 for height:float in [-1.0,0.0,1.0]:
  recipe.body_shapes={"height":height};view.model.configure("female",recipe,gear)
  view.model.play("lie","front",true);view.model._from_rotations.clear();view.model.pose_at(0)
  var support:Dictionary={"height":height}
  for region:String in ["head","lHand","rHand"]:
   var minimum:=INF
   for node:Dictionary in body.nodes:
    var selected:bool=node.name==region
    if region.ends_with("Hand"):
     selected=node.name.begins_with(region.left(1)) and (node.name.contains("Hand") or node.name.contains("Index") or node.name.contains("Mid") or node.name.contains("Ring") or node.name.contains("Pinky") or node.name.contains("Thumb"))
    if selected:
     for weight:Dictionary in node.weights:
      if weight.axis_weights.length_squared()>=.75:minimum=minf(minimum,(view.model.rig.transform*(body.posed_points[weight.vertex]+body.root_offset)).y)
   support[region]=minimum
  supports.append(support)
  assert(float(support.head)<.012 and maxf(float(support.lHand),float(support.rHand))<.03,"Resting head/hands hover: "+str(support))
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"reverse_surface_error_m":reverse_error,"minimum_floor_y_m":low,"rest_support_m":supports,"source":"UAL2 LayToIdle plus shared relaxed resting endpoint; reverse used for lowering candidate","scope":"Five motion samples and three height rest supports; not continuous garment/armed/seat contact acceptance"},"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("PASS source recovery samples and reversed surface ",reverse_error);quit()
