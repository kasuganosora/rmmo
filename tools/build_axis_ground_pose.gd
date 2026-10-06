extends SceneTree
## Read a native VaM pose as local Unity Z-X-Y Euler transforms, NOT DAZ bend angles.
## DAZBone.GetJSON/RestoreFromJSON distinguishes root world rotation from local bones.
const Body=preload("res://scripts/char/female_axis_body.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var body=Body.new();root.add_child(body);body.initialize()
 var source:String=Art.path("characters/source_models/vam_sitting_reference/Preset_AA_sitting003.vap")
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source))
 var bones:Dictionary={}
 for item:Dictionary in data.storables:
  if item.has("rotation") or item.has("rootRotation"):bones[item.id]=item
 var animation:=Animation.new();animation.length=1;animation.loop_mode=Animation.LOOP_LINEAR
 for node:Dictionary in body.nodes:
  if not bones.has(node.name):continue
  var item:Dictionary=bones[node.name]
  var e:Dictionary=item.get("rootRotation",item.get("rotation",{}))
  var radians:=Vector3(float(e.x),float(e.y),float(e.z))*PI/180.0
  # Unity Quaternion.Euler composes Y * X * Z; the approved body retains
  # the original numeric coordinate basis, so no extra reflection is applied.
  var basis:=Basis.from_euler(radians,EULER_ORDER_YXZ)
  var track:=animation.add_track(Animation.TYPE_ROTATION_3D)
  animation.track_set_path(track,NodePath("Skeleton3D:"+node.name))
  animation.rotation_track_insert_key(track,0,basis.get_rotation_quaternion())
  var local:Basis=body.skeleton.get_bone_rest(node.skeleton_index).basis.inverse()*basis
  var angles:Vector3=Body.continuous_angles(local.orthonormalized(),node.order,Vector3.ZERO)
  var reference:=animation.add_track(Animation.TYPE_VALUE)
  animation.track_set_path(reference,NodePath("AxisAngles:"+node.name));animation.track_insert_key(reference,0,angles)
 var p:Dictionary=bones.hip.rootPosition
 var offset:Vector3=Vector3(float(p.x),float(p.y),float(p.z))-body.rests.hip.origin
 var root_track:=animation.add_track(Animation.TYPE_POSITION_3D)
 animation.track_set_path(root_track,NodePath("VisualRoot:position"));animation.position_track_insert_key(root_track,0,offset)
 var library:=AnimationLibrary.new();library.add_animation("sit_ground",animation)
 var folder:String=Art.review_path("character_3d/axis_ground_pose_01");DirAccess.make_dir_recursive_absolute(folder)
 assert(ResourceSaver.save(library,folder+"/candidate.res")==OK)
 if "--publish-source" in OS.get_cmdline_user_args():
  assert(ResourceSaver.save(library,Art.path("characters/animations/female_base_v2_ground_source.res"))==OK)
 print("Native sitting003 candidate: ",bones.size()," bone records; no runtime promotion")
 body.free();quit()
