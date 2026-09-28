extends RefCounted
## Shape-specific action preparation, isolated from the displayed actor.
const Static=preload("res://scripts/char/character_ground_pose_preparer.gd")
const Capture=preload("res://scripts/char/character_axis_pose_capture.gd")
var cached_shapes:Dictionary={}
var cached_library:AnimationLibrary
var busy:=false
var error:=""
var build_count:=0
var maximum_floor_correction:=0.0
var maximum_ik_error:=0.0
func prepare(owner:Node3D,shapes:Dictionary,seated:Animation,sources:AnimationLibrary)->AnimationLibrary:
 var normalized:Dictionary=Static.Body.Shapes.normalize(shapes)
 if cached_library!=null and cached_shapes==normalized:return cached_library
 if busy:error="Ground action preparation already in progress";return null
 if seated==null or sources==null or not sources.has_animation("get_up") or not sources.has_animation("idle"):error="Missing ground action inputs";return null
 busy=true;error="";maximum_floor_correction=0;maximum_ik_error=0
 var owner_ref:WeakRef=weakref(owner)
 var work=Static.Workspace.new();work.name="GroundActionPreparation";work.visible=false;owner.get_tree().root.add_child(work)
 work.rig=Node3D.new();work.add_child(work.rig)
 var body=Static.Body.new();work.rig.add_child(body);body.initialize();body.enable_compute()
 if not body.set_shape_values(normalized):return _fail(work,"Ground action shape unavailable")
 var motion=Static.Motion.new()
 if not motion.install(body.skeleton,sources) or not motion.apply(body,"idle",0):return _fail(work,"Standing endpoint unavailable")
 var standing:=Animation.new();standing.length=1
 Capture.append(body,standing,0,motion.visual_offset)
 var source:AnimationLibrary=preload("res://scripts/char/character_ground_motion_source.gd").build(body,seated,sources.get_animation("get_up"),standing)
 if not motion.install(body.skeleton,source):return _fail(work,"Ground action source incompatible")
 work.axis_rig={"body":body,"animations":motion}
 var contact=preload("res://scripts/char/character_ground_motion_contact.gd").new();contact.configure(work)
 work.play("stand_up_ground","front",true)
 var rising:=Animation.new();rising.length=source.get_animation("stand_up_ground").length
 var count:int=ceili(rising.length*30)
 for frame in count+1:
  var time:float=rising.length*frame/count
  work.pose_at(time);contact.prepare(work,time)
  await RenderingServer.frame_post_draw
  if owner_ref.get_ref()==null:return _fail(work,"Ground action owner released")
  for bridge in [contact.legs,contact.arms]:
   if bridge.completed_revision!=bridge.revision or not bridge.error.is_empty():return _fail(work,"Ground action IK result unavailable")
   for i in 2:
    var actual:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone(bridge.end_bones[i])).origin
    maximum_ik_error=maxf(maximum_ik_error,actual.distance_to(bridge.targets[i].position))
  var low:=INF
  for p:Vector3 in body.posed_points:low=minf(low,(work.rig.transform*(p+body.root_offset)).y)
  var correction:float=maxf(0,-low);maximum_floor_correction=maxf(maximum_floor_correction,correction)
  Capture.append(body,rising,time,work.rig.position+Vector3(0,correction,0))
  await work.get_tree().process_frame
  if owner_ref.get_ref()==null:return _fail(work,"Ground action owner released")
 var lowering:Animation=rising.duplicate()
 for track in rising.get_track_count():
  var keys:Array=[]
  for key in rising.track_get_key_count(track):keys.append([rising.track_get_key_time(track,key),rising.track_get_key_value(track,key)])
  for key in range(lowering.track_get_key_count(track)-1,-1,-1):lowering.track_remove_key(track,key)
  for key in keys:lowering.track_insert_key(track,rising.length-float(key[0]),key[1])
 var result:=AnimationLibrary.new();result.add_animation("sit_ground",seated);result.add_animation("stand_up_ground",rising);result.add_animation("sit_down_ground",lowering)
 work.free();busy=false;build_count+=1;cached_shapes=normalized.duplicate(true);cached_library=result
 return result
func _fail(work:Node3D,reason:String)->AnimationLibrary:
 error=reason;work.free();busy=false;return null
