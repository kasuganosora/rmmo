extends RefCounted
## Prepare off-screen once per shape, then replay a regular shared animation.
## No trial poses are published to the visible body's hair or cloth.
const Body=preload("res://scripts/char/female_axis_body.gd")
const Motion=preload("res://scripts/char/character_axis_animation.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
class Workspace extends Node3D:
 var axis_rig:Dictionary={}
 var rig:Node3D
 var _from_rotations:Array=[]
 var clip:=""
 func play(action:String,_direction:String,_restart:bool=false,variant:String="")->void:
  clip=variant if not variant.is_empty() else action
 func pose_at(time:float)->void:
  assert(axis_rig.animations.apply(axis_rig.body,clip,time))
  rig.position=axis_rig.animations.visual_offset
var cached_shapes:Dictionary={}
var cached_animation:Animation
var busy:=false
var error:=""
var build_count:=0
func prepare(owner:Node3D,shapes:Dictionary)->Animation:
 var normalized:Dictionary=Body.Shapes.normalize(shapes)
 if cached_animation!=null and normalized==cached_shapes:return cached_animation
 if busy:error="Ground pose preparation already in progress";return null
 var source_path:String=Art.path("characters/animations/female_base_v2_ground_source.res")
 if not FileAccess.file_exists(source_path):error="Missing native ground pose source";return null
 busy=true;error=""
 var owner_ref:WeakRef=weakref(owner)
 var work:=Workspace.new();work.name="GroundPosePreparation";work.visible=false
 owner.get_tree().root.add_child(work)
 work.rig=Node3D.new();work.add_child(work.rig)
 var body:=Body.new();work.rig.add_child(body);body.initialize();body.enable_compute()
 work.axis_rig={"body":body}
 var motion:=Motion.new()
 if not body.set_shape_values(normalized) or not motion.install(body.skeleton,load(source_path)) or not motion.apply(body,"sit_ground",0):
  error="Ground pose source/shape preparation failed";work.free();busy=false;return null
 work.rig.position=motion.visual_offset
 var fit=preload("res://scripts/char/character_ground_support_fit.gd").new()
 if not fit.prepare(work):error=fit.error;work.free();busy=false;return null
 await RenderingServer.frame_post_draw
 if owner_ref.get_ref()==null:
  error="Ground pose owner released";work.free();busy=false;return null
 if fit.bridge.completed_revision!=fit.bridge.revision or not fit.bridge.error.is_empty():
  error="Ground pose final IK unavailable";work.free();busy=false;return null
 var animation:=Animation.new();animation.length=1;animation.loop_mode=Animation.LOOP_LINEAR
 # Read the retained final-pose snapshot, not the skeleton's restored input.
 for node:Dictionary in body.nodes:
  var i:int=node.skeleton_index;var parent:int=body.skeleton.get_bone_parent(i)
  var basis:Basis=body.get_solved_bone_pose(i).basis
  if parent>=0:basis=body.get_solved_bone_pose(parent).basis.inverse()*basis
  var track:=animation.add_track(Animation.TYPE_ROTATION_3D)
  animation.track_set_path(track,NodePath("Skeleton3D:"+node.name));animation.rotation_track_insert_key(track,0,basis.get_rotation_quaternion())
  var angles:=animation.add_track(Animation.TYPE_VALUE)
  animation.track_set_path(angles,NodePath("AxisAngles:"+node.name));animation.track_insert_key(angles,0,node.angles)
 var root_track:=animation.add_track(Animation.TYPE_POSITION_3D)
 animation.track_set_path(root_track,NodePath("VisualRoot:position"));animation.position_track_insert_key(root_track,0,work.rig.position)
 for ids in [fit.hip_vertices,fit.foot_vertices,fit.hand_vertices[0],fit.hand_vertices[1]]:
  var low:=INF
  for id in ids:low=minf(low,body.posed_points[id].y+body.root_offset.y+work.rig.position.y)
  if absf(low)>.003:
   error="Ground pose support outside 3 mm tolerance";work.free();busy=false;return null
 work.free();busy=false;build_count+=1
 cached_shapes=normalized.duplicate(true);cached_animation=animation
 return animation
