extends RefCounted
## Fixed seat plane plus planted feet; uses the shared native paired-limb bridge.
var body:Node3D
var bridge=preload("res://scripts/char/character_axis_ik.gd").new()
var top:=Vector3.ZERO
var size:=Vector2(.5,.5)
var enabled:=false
var sole_vertices:Array=[]
var seat_vertices:=PackedInt32Array()
var root_adjustment:=0.0
var floor_height:=0.0
func configure(target:Node3D)->void:
 body=target;bridge.configure(body,[["lThigh","lShin","lFoot"],["rThigh","rShin","rFoot"]])
 bridge.modifier.name="SeatLegIK"
 for side:String in ["l","r"]:
  var ids:Dictionary={}
  for node:Dictionary in body.nodes:
   if node.name not in [side+"Foot",side+"Toe"]:continue
   for weight:Dictionary in node.weights:
    if weight.axis_weights.length_squared()>=.75:ids[int(weight.vertex)]=true
   for id in node.full:ids[int(id)]=true
  sole_vertices.append(PackedInt32Array(ids.keys()))
## Coordinates are model-local, with a horizontal seat and floor.
## Caller binds a fixed furniture surface; it must not follow the animated pelvis.
func set_seat(surface_top:Vector3,dimensions:Vector2,ground_height:float=0.0)->void:
 assert(surface_top.is_finite() and dimensions.is_finite() and dimensions.x>0 and dimensions.y>0 and is_finite(ground_height))
 top=surface_top;size=dimensions;floor_height=ground_height;enabled=true
func clear()->void:
 enabled=false
 root_adjustment=0.0;seat_vertices.clear()
 if bridge.modifier.active:bridge.cancel()
func prepare(model:Node3D)->bool:
 if not enabled or model.action not in ["sit_chair","sit_chair_hold","stand_up_chair"]:
  root_adjustment=0.0
  if bridge.modifier.active:bridge.cancel()
  return false
 var sk:Skeleton3D=body.skeleton
 var phase:float=clampf(model.elapsed/maxf(model.action_duration(),.001),0,1)
 var lowering_weight:=1.0
 var foot_weight:=1.0
 if model.action=="sit_chair":lowering_weight=smoothstep(.2,.7,phase)
 if model.action=="stand_up_chair":
  lowering_weight=0.0
  foot_weight=1.0-smoothstep(.65,1.0,phase)
 var hip:Vector3=model.rig.transform*(body.get_solved_bone_pose(sk.find_bone("hip")).origin+body.root_offset)
 var thigh_length:float=body.rests.lThigh.origin.distance_to(body.rests.lShin.origin)
 seat_vertices.clear();var bottom:=INF
 for index in body.posed_points.size():
  var p:Vector3=model.rig.transform*(body.posed_points[index]+body.root_offset)
  if absf(p.x-top.x)<=size.x*.5 and absf(p.z-top.z)<=size.y*.5 and p.y<hip.y and p.y>hip.y-thigh_length*.55:
   seat_vertices.append(index);bottom=minf(bottom,p.y)
 if seat_vertices.is_empty():
  if bridge.modifier.active:bridge.cancel()
  root_adjustment=0.0
  return false
 var feet:Array[Transform3D]=[];var knees:Array[Vector3]=[];var refs:Dictionary={}
 for node:Dictionary in body.nodes:refs[node.name]=node.angles
 for i in 2:
  var side:String="l" if i==0 else "r"
  var ankle:Transform3D=model.rig.transform*body.get_solved_bone_pose(sk.find_bone(side+"Foot"))
  var lowest:=INF
  for index in sole_vertices[i]:lowest=minf(lowest,(model.rig.transform*(body.posed_points[index]+body.root_offset)).y)
  ankle.origin.y+=(floor_height-lowest)*foot_weight
  feet.append(ankle)
  knees.append(body.get_solved_bone_pose(sk.find_bone(side+"Shin")).origin+Vector3(0,0,thigh_length))
 # Never pull an entering/standing character down to the seat. Only lower
 # toward it during the seated end of entry; prevent existing penetration
 # while rising until the body has naturally cleared the fixed surface.
 var separation:float=top.y-bottom
 root_adjustment=maxf(0,separation)+minf(0,separation)*lowering_weight
 model.rig.position.y+=root_adjustment
 for i in 2:feet[i]=model.rig.transform.affine_inverse()*feet[i]
 return bridge.submit(feet,knees,refs)
