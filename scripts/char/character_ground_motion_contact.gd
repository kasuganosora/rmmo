extends RefCounted
const Bridge=preload("res://scripts/char/character_axis_ik.gd")
var legs=Bridge.new()
var arms=Bridge.new()
var start_feet:Array[Transform3D]=[]
var end_feet:Array[Transform3D]=[]
var start_knees:Array[Vector3]=[]
var end_knees:Array[Vector3]=[]
var start_hands:Array[Transform3D]=[]
var hips:=PackedInt32Array()
var soles:Array=[]
var palms:Array=[]
var start_low:Array[float]=[]
var end_low:Array[float]=[]
func minimum(body:Node3D,model:Node3D,ids:PackedInt32Array)->float:
 var low:=INF
 for id in ids:low=minf(low,(model.rig.transform*(body.posed_points[id]+body.root_offset)).y)
 return low
func frame(body:Node3D,model:Node3D,name:String)->Transform3D:
 return model.rig.transform*body.get_solved_bone_pose(body.skeleton.find_bone(name))
func configure(model:Node3D)->void:
 var body=model.axis_rig.body
 var ids:Dictionary={}
 for node:Dictionary in body.nodes:
  if node.name not in ["hip","pelvis"]:continue
  for w:Dictionary in node.weights:
   if w.axis_weights.length_squared()>.75:ids[int(w.vertex)]=true
  for id in node.full:ids[int(id)]=true
 hips=PackedInt32Array(ids.keys())
 for side:String in ["l","r"]:
  for target:Array in [[side+"Foot",side+"Toe"],[side+"Hand",side+"Thumb",side+"Index",side+"Mid",side+"Ring",side+"Pinky"]]:
   ids={}
   for node:Dictionary in body.nodes:
    var selected:=false
    for prefix:String in target:selected=selected or node.name.begins_with(prefix)
    if not selected:continue
    for w:Dictionary in node.weights:
     if w.axis_weights.length_squared()>.75:ids[int(w.vertex)]=true
    for id in node.full:ids[int(id)]=true
   if target.size()==2:soles.append(PackedInt32Array(ids.keys()))
   else:palms.append(PackedInt32Array(ids.keys()))
 model.play("get_up","front",true,"stand_up_ground");model._from_rotations.clear()
 for time:float in [0.0,1.0]:
  model.pose_at(time)
  for i in 2:
   var side:String="l" if i==0 else "r"
   if time==0:
    start_feet.append(frame(body,model,side+"Foot"));start_knees.append(frame(body,model,side+"Shin").origin)
    start_hands.append(frame(body,model,side+"Hand"));start_low.append(minimum(body,model,soles[i]))
   else:
    end_feet.append(frame(body,model,side+"Foot"));end_knees.append(frame(body,model,side+"Shin").origin)
    end_low.append(minimum(body,model,soles[i]));end_feet[i].origin.y-=end_low[i]
 legs.configure(body,[["lThigh","lShin","lFoot"],["rThigh","rShin","rFoot"]]);arms.configure(body)
func prepare(model:Node3D,time:float)->void:
 var body=model.axis_rig.body
 var transfer:float=smoothstep(.8,1.3,time)
 # Seated support first, then transfer to the original rising pelvis path.
 model.rig.position.y-=minimum(body,model,hips)*(1.0-transfer)
 var inverse:Transform3D=model.rig.transform.affine_inverse()
 var targets:Array[Transform3D]=[];var poles:Array[Vector3]=[];var refs:Dictionary={}
 for node:Dictionary in body.nodes:refs[node.name]=node.angles
 var amount:float=smoothstep(0,1,time)
 for i in 2:
  var side:String="l" if i==0 else "r"
  var desired:Transform3D
  var knee:Vector3
  if time<=1:
   desired=start_feet[i].interpolate_with(end_feet[i],amount)
   desired.origin.y+=.08*sin(PI*amount)
   knee=start_knees[i].lerp(end_knees[i],amount)
  else:
   desired=frame(body,model,side+"Foot");desired.origin.y-=minimum(body,model,soles[i])
   knee=frame(body,model,side+"Shin").origin
  targets.append(inverse*desired);poles.append(inverse*knee)
 legs.submit(targets,poles,refs)
 targets.clear();poles.clear()
 for i in 2:
  var side:String="l" if i==0 else "r"
  var current:Transform3D=frame(body,model,side+"Hand")
  current.origin.y-=minf(0,minimum(body,model,palms[i]))
  var desired:Transform3D=start_hands[i].interpolate_with(current,smoothstep(.4,1,time))
  targets.append(inverse*desired);poles.append(body.get_solved_bone_pose(body.skeleton.find_bone(side+"ForeArm")).origin)
 arms.submit(targets,poles,refs)
