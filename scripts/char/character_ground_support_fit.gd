extends RefCounted
## Preparation only: retain the source seated legs, solve supporting arms against
## the floor. A bounded trunk adjustment provides reach without scaling bones.
var bridge=preload("res://scripts/char/character_axis_ik.gd").new()
var hand_vertices:Array=[]
var lean_degrees:=0.0
var leg_degrees:=0.0
var hip_vertices:=PackedInt32Array()
var foot_vertices:=PackedInt32Array()
var error:=""
func prepare(model:Node3D)->bool:
 var body=model.axis_rig.body;var sk:Skeleton3D=body.skeleton
 bridge.configure(body)
 var refs:Dictionary={}
 for node:Dictionary in body.nodes:refs[node.name]=node.angles
 var hips:Dictionary={};var feet:Dictionary={}
 for node:Dictionary in body.nodes:
  if node.name not in ["hip","pelvis","lFoot","rFoot","lToe","rToe"]:continue
  var ids:Dictionary=hips if node.name in ["hip","pelvis"] else feet
  for weight:Dictionary in node.weights:
   if weight.axis_weights.length_squared()>.75:ids[int(weight.vertex)]=true
  for id in node.full:ids[int(id)]=true
 hip_vertices=PackedInt32Array(hips.keys());foot_vertices=PackedInt32Array(feet.keys())
 # Rotate the leg assembly around the pelvis, retaining the source crossing.
 # Solve foot-vs-hip support separation instead of lowering both feet apart.
 var pelvis:int=sk.find_bone("pelvis")
 var leg_original:Basis=body.get_solved_bone_pose(pelvis).basis
 var leg_parent:Basis=body.get_solved_bone_pose(sk.get_bone_parent(pelvis)).basis
 var lower:=0.0;var upper:=16.0
 for iteration in 12:
  leg_degrees=(lower+upper)*.5
  sk.set_bone_pose_rotation(pelvis,(leg_parent.inverse()*Basis(Vector3.RIGHT,deg_to_rad(leg_degrees))*leg_original).get_rotation_quaternion())
  if not body.sync_final_pose(refs):error=body.pose_sync_error;return false
  var hip_low:=INF;var foot_low:=INF
  for id in hip_vertices:hip_low=minf(hip_low,body.posed_points[id].y)
  for id in foot_vertices:foot_low=minf(foot_low,body.posed_points[id].y)
  if foot_low>hip_low:lower=leg_degrees
  else:upper=leg_degrees
 refs.clear()
 for node:Dictionary in body.nodes:refs[node.name]=node.angles
 for side:String in ["l","r"]:
  var ids:Dictionary={}
  for node:Dictionary in body.nodes:
   if not node.name.begins_with(side):continue
   var hand:bool=node.name==side+"Hand"
   for finger:String in ["Thumb","Index","Mid","Ring","Pinky"]:hand=hand or node.name.begins_with(side+finger)
   if not hand:continue
   for weight:Dictionary in node.weights:
    if weight.axis_weights.length_squared()>.75:ids[int(weight.vertex)]=true
   for id in node.full:ids[int(id)]=true
  hand_vertices.append(PackedInt32Array(ids.keys()))
 var spine:int=sk.find_bone("abdomen")
 var original:Basis=body.get_solved_bone_pose(spine).basis
 var parent:Basis=body.get_solved_bone_pose(sk.get_bone_parent(spine)).basis
 for attempt in 11:
  lean_degrees=-float(attempt)*2.0
  sk.set_bone_pose_rotation(spine,(parent.inverse()*Basis(Vector3.RIGHT,deg_to_rad(lean_degrees))*original).get_rotation_quaternion())
  if not body.sync_final_pose(refs):error=body.pose_sync_error;return false
  var lowest:=INF
  for p:Vector3 in body.posed_points:lowest=minf(lowest,p.y+body.root_offset.y)
  model.rig.position.y=-lowest
  var targets:Array[Transform3D]=[];var poles:Array[Vector3]=[];var reachable:=true
  for i in 2:
   var side:String="l" if i==0 else "r"
   var wrist:Transform3D=body.get_solved_bone_pose(sk.find_bone(side+"Hand"))
   var shoulder:Vector3=body.get_solved_bone_pose(sk.find_bone(side+"Shldr")).origin
   var elbow:Vector3=body.get_solved_bone_pose(sk.find_bone(side+"ForeArm")).origin
   var low:=INF
   for id in hand_vertices[i]:low=minf(low,(model.rig.transform*(body.posed_points[id]+body.root_offset)).y)
   wrist.origin.y-=low
   var reach:float=(shoulder.distance_to(elbow)+elbow.distance_to(body.get_solved_bone_pose(sk.find_bone(side+"Hand")).origin))*.99
   var dy:float=wrist.origin.y-shoulder.y
   if absf(dy)>reach:reachable=false;break
   var horizontal:=Vector2(wrist.origin.x-shoulder.x,wrist.origin.z-shoulder.z)
   horizontal=horizontal.limit_length(sqrt(maxf(0,reach*reach-dy*dy)))
   wrist.origin.x=shoulder.x+horizontal.x;wrist.origin.z=shoulder.z+horizontal.y
   targets.append(wrist);poles.append(elbow)
  if reachable:
   refs.clear()
   for node:Dictionary in body.nodes:refs[node.name]=node.angles
   return bridge.submit(targets,poles,refs)
 error="Hands cannot reach floor within bounded trunk adjustment"
 return false
