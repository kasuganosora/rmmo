extends SceneTree
const Body=preload("res://scripts/char/female_axis_body.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func vec(d:Dictionary)->Vector3:return Vector3(float(d.x),float(d.y),float(d.z))
func xyz(p:Vector3)->Array:return [p.x,p.y,p.z]
func run()->void:
 var body=Body.new();root.add_child(body);body.initialize();body.enable_compute()
 var folder:String=Art.review_path("character_3d/axis_ground_pose_01")
 var motion=preload("res://scripts/char/character_axis_animation.gd").new()
 assert(motion.install(body.skeleton,load(folder+"/candidate.res")))
 assert(motion.apply(body,"sit_ground",0))
 var input:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Art.path("characters/source_models/vam_sitting_reference/Preset_AA_sitting003.vap")))
 var source:Dictionary={}
 for item:Dictionary in input.storables:
  if item.has("rotation") or item.has("rootRotation"):source[item.id]=item
 var joints:Array=[];var frames:Array[Transform3D]=[]
 for i in body.skeleton.get_bone_count():
  var name:String=body.skeleton.get_bone_name(i);var parent:int=body.skeleton.get_bone_parent(i)
  var local:Transform3D=body.skeleton.get_bone_rest(i)
  if source.has(name):
   var item:Dictionary=source[name]
   local.basis=Basis.from_euler(vec(item.get("rootRotation",item.get("rotation",{})))*PI/180.0,EULER_ORDER_YXZ)
   local.origin=vec(item.get("rootPosition",item.get("position",{})))
  frames.append(frames[parent]*local if parent>=0 else local)
  if source.has(name):
   var current:Vector3=body.get_solved_bone_pose(i).origin+motion.authored_offset
   joints.append({"name":name,"source_position":xyz(frames[i].origin),"current_position":xyz(current),"difference_m":current.distance_to(frames[i].origin)})
 var regions:Array=[];var lowest:=INF;var lowest_id:=-1
 for i in body.posed_points.size():
  var y:float=body.posed_points[i].y+motion.authored_offset.y
  if y<lowest:lowest=y;lowest_id=i
 for node:Dictionary in body.nodes:
  var ids:Dictionary={}
  for w:Dictionary in node.weights:
   if w.axis_weights.length_squared()>.75:ids[int(w.vertex)]=true
  for id in node.full:ids[int(id)]=true
  if ids.is_empty():continue
  var low:=INF
  for id in ids:low=minf(low,body.posed_points[id].y+motion.authored_offset.y)
  regions.append({"name":node.name,"minimum_y_m":low,"contains_global_minimum":ids.has(lowest_id)})
 var file:=FileAccess.open(folder+"/contact_diagnostic.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"lowest_vertex":lowest_id,"minimum_unlifted_y_m":lowest,"support_lift_m":motion.support_adjustment,"regions":regions,"joints":joints},"  "));file.close()
 print("Ground diagnostic minimum ",lowest," vertex ",lowest_id)
 body.free();quit()
