extends RefCounted
## Diagnostic splice: first uncross/draw the legs, then transfer upper-body
## support into the source recovery. Never play the lying start of LayToIdle.
const Body=preload("res://scripts/char/female_axis_body.gd")
const JOIN_TIME:=1.0
const SOURCE_START:=.5
static func track_for(clip:Animation,path:NodePath)->int:
 for i in clip.get_track_count():
  if clip.track_get_path(i)==path:return i
 return -1
static func rotation(clip:Animation,name:String,time:float,fallback:Quaternion)->Quaternion:
 var track:int=track_for(clip,NodePath("Skeleton3D:"+name))
 return clip.rotation_track_interpolate(track,time) if track>=0 else fallback
static func offset(clip:Animation,time:float)->Vector3:
 return clip.position_track_interpolate(track_for(clip,NodePath("VisualRoot:position")),time)
static func build(body:Node3D,seated:Animation,source:Animation,standing:Animation=null)->AnimationLibrary:
 var rising:=Animation.new();rising.length=JOIN_TIME+source.length-SOURCE_START
 var count:int=ceili(rising.length*30)
 for node:Dictionary in body.nodes:
  var rest:Basis=body.skeleton.get_bone_rest(node.skeleton_index).basis
  var initial:Quaternion=rotation(seated,node.name,0,rest.get_rotation_quaternion())
  var target:Quaternion=rotation(source,node.name,SOURCE_START,rest.get_rotation_quaternion())
  var r:=rising.add_track(Animation.TYPE_ROTATION_3D);rising.track_set_path(r,NodePath("Skeleton3D:"+node.name))
  var a:=rising.add_track(Animation.TYPE_VALUE);rising.track_set_path(a,NodePath("AxisAngles:"+node.name))
  var previous:Vector3=seated.track_get_key_value(track_for(seated,NodePath("AxisAngles:"+node.name)),0)
  var leg:bool=node.name=="pelvis" or node.name.contains("Thigh") or node.name.contains("Shin") or node.name.contains("Foot") or node.name.contains("Toe")
  for frame in count+1:
   var time:float=rising.length*frame/count
   var q:Quaternion
   if time<=JOIN_TIME:
    var weight:float=smoothstep(.05,.7,time) if leg else smoothstep(.25,JOIN_TIME,time)
    q=initial.slerp(target,weight)
   else:q=rotation(source,node.name,SOURCE_START+time-JOIN_TIME,rest.get_rotation_quaternion())
   if standing!=null:
    q=q.slerp(rotation(standing,node.name,0,rest.get_rotation_quaternion()),smoothstep(rising.length-.25,rising.length,time))
   previous=Body.continuous_angles((rest.inverse()*Basis(q)).orthonormalized(),node.order,previous)
   rising.rotation_track_insert_key(r,time,q);rising.track_insert_key(a,time,previous)
 var root_track:=rising.add_track(Animation.TYPE_POSITION_3D);rising.track_set_path(root_track,NodePath("VisualRoot:position"))
 for frame in count+1:
  var time:float=rising.length*frame/count
  var point:Vector3=offset(seated,0).lerp(offset(source,SOURCE_START),smoothstep(.4,JOIN_TIME,time)) if time<=JOIN_TIME else offset(source,SOURCE_START+time-JOIN_TIME)
  if standing!=null:point=point.lerp(offset(standing,0),smoothstep(rising.length-.25,rising.length,time))
  rising.position_track_insert_key(root_track,time,point)
 var lowering:Animation=rising.duplicate()
 for track in rising.get_track_count():
  var keys:Array=[]
  for key in rising.track_get_key_count(track):keys.append([rising.track_get_key_time(track,key),rising.track_get_key_value(track,key)])
  for key in range(lowering.track_get_key_count(track)-1,-1,-1):lowering.track_remove_key(track,key)
  for key in keys:lowering.track_insert_key(track,rising.length-float(key[0]),key[1])
 var library:=AnimationLibrary.new();library.add_animation("stand_up_ground",rising);library.add_animation("sit_down_ground",lowering)
 return library
