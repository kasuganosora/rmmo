extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(180).timeout.connect(func():push_error("Height test timed out");quit(2))
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 var model:=Model.new();model.body_type="female";model.appearance=recipe.duplicate(true);root.add_child(model);model.set_process(false)
 var body=model.axis_rig.body;var hair=model.axis_rig.hair
 var body_id:int=body.get_instance_id();var hair_id:int=hair.source.get_instance_id()
 var baseline_fit:Transform3D=hair.fit
 var baseline_angles:Dictionary={}
 for node:Dictionary in body.nodes:baseline_angles[node.name]=node.angles
 var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Art.path("characters/morphs/female_base_v2/source_native_01/height.json")))
 assert(raw.formulas.size()==240)
 var heights:Dictionary={};var max_center_error:=0.0;var minimum_support:=INF
 for amount:float in [-1.0,1.0,0.0,-1.0,1.0,0.0]:
  recipe.body_shapes={"height":amount};model.configure("female",recipe,{})
  assert(body.get_instance_id()==body_id and hair.source.get_instance_id()==hair_id)
  var expected:Dictionary=body.base_rests.duplicate()
  for formula:Dictionary in raw.formulas:
   var transform:Transform3D=expected[formula.target]
   transform.origin[int(formula.targetType)-1]+=float(formula.multiplier)*amount
   expected[formula.target]=transform
  for node:Dictionary in body.nodes:
   max_center_error=maxf(max_center_error,body.rests[node.name].origin.distance_to(expected[node.name].origin))
   max_center_error=maxf(max_center_error,body.skeleton.get_bone_global_rest(node.skeleton_index).origin.distance_to(expected[node.name].origin))
  assert(max_center_error<.00001)
  var low:=INF;var high:=-INF
  for p:Vector3 in body.rest_points:low=minf(low,p.y);high=maxf(high,p.y)
  heights[str(amount)]=high-low
  for action:String in ["idle","walk","sit_chair"]:
   model.play(action,"front",true);model._from_rotations.clear()
   for time:float in [0.0,.25,.5]:
    model.pose_at(time)
    assert(body.pose_sync_error.is_empty())
    var bottom:=INF
    for p:Vector3 in body.posed_points:bottom=minf(bottom,(model.rig.transform*(p+body.root_offset)).y)
    minimum_support=minf(minimum_support,bottom)
    assert(bottom>=-.0001,"Height adjustment penetrates flat floor")
  if amount==0.0:
   assert(body.rest_points==body.base_rest_points)
   assert(hair.fit.is_equal_approx(baseline_fit),"Hair fit accumulates height edits")
 assert(float(heights["-1.0"])>float(heights["0.0"]) and float(heights["0.0"])>float(heights["1.0"]))
 var report={"rest_height_m":heights,"center_error_m":max_center_error,"minimum_support_m":minimum_support,"body_hair_reused":true,"reset_hair_fit":true,"scope":"Static hair; flat floor, three actions at three samples. Not terrain/seat contact or dynamic spring acceptance."}
 var folder:String=Art.review_path("character_3d/body_identity_02");DirAccess.make_dir_recursive_absolute(folder)
 var file:=FileAccess.open(folder+"/height_regression.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 model.free()
 for frame in 3:await process_frame
 print("PASS height original joint centers, repeated body/hair resets and sampled flat support: ",report)
 quit()
