extends Node3D
## Main-hand socket derived from the actual gripping hand, not character offsets.
var body:Node3D
var enabled:=false
var item_id:=""
var pieces:Array[MeshInstance3D]=[]
var club:MeshInstance3D
var grip_rotations:Dictionary={}
var grip_references:Dictionary={}
var unarmed_rotations:Dictionary={}
var unarmed_references:Dictionary={}
const HAND="lHand" # UAL hand_r maps here; letters differ between source formats.
func configure(target:Node3D,library:AnimationLibrary)->void:
 body=target
 if library.has_animation("attack_sword_a"):
  var clip:Animation=library.get_animation("attack_sword_a")
  for track in clip.get_track_count():
   var path:NodePath=clip.track_get_path(track)
   if path.get_subname_count()!=1:continue
   var bone:String=path.get_subname(0)
   if not _finger(bone):continue
   if clip.track_get_type(track)==Animation.TYPE_ROTATION_3D:grip_rotations[bone]=clip.rotation_track_interpolate(track,0)
   elif clip.track_get_type(track)==Animation.TYPE_VALUE:grip_references[bone]=clip.value_track_interpolate(track,0)
 for spec:Array in [[Vector3(.026,.12,.026),0.0,Color("4b3326")],[Vector3(.14,.022,.035),.074,Color("c3a369")],[Vector3(.048,.46,.016),.315,Color("bac8d3")]]:
  var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=spec[0];mesh.mesh=box
  var material:=StandardMaterial3D.new();material.albedo_color=spec[2];material.roughness=.5;mesh.material_override=material
  mesh.position.y=spec[1];add_child(mesh);pieces.append(mesh)
 club=MeshInstance3D.new();club.name="GreatClub"
 var shaft:=CylinderMesh.new();shaft.bottom_radius=.021;shaft.top_radius=.072;shaft.height=.9;shaft.radial_segments=12
 club.mesh=shaft;club.position.y=.3
 var timber:=StandardMaterial3D.new();timber.albedo_color=Color("91643d");timber.roughness=.9;club.material_override=timber
 club.visible=false;add_child(club)
 visible=false;body.surface_updated.connect(sync_socket)
func set_equipment(parts:Dictionary)->void:
 item_id=str(parts.get("WeaponMainItem",""))
 # Explicit item identity; a legacy boolean is only the diagnostic sword.
 var wooden:bool=item_id=="wooden_sword"
 club.visible=item_id=="great_club"
 for i in pieces.size():
  pieces[i].visible=not club.visible
  var material:StandardMaterial3D=pieces[i].material_override
  material.albedo_color=([Color("684728"),Color("94683f"),Color("ba8d59")] if wooden else [Color("4b3326"),Color("c3a369"),Color("bac8d3")])[i]
  material.roughness=.85 if wooden else .5
 set_enabled(int(parts.get("WeaponMain",0))>0 if parts.get("WeaponMain")!=null else false)
func _finger(bone:String)->bool:
 for name:String in ["Index","Mid","Ring","Pinky","Thumb"]:
  if bone.begins_with("l"+name):return true
 return false
func set_enabled(value:bool)->void:
 if value==enabled:return
 enabled=value;visible=value
 if value:apply_grip(true)
 elif not unarmed_rotations.is_empty():
  for bone:String in unarmed_rotations:body.skeleton.set_bone_pose_rotation(body.skeleton.find_bone(bone),unarmed_rotations[bone])
  body.sync_final_pose(unarmed_references)
func apply_grip(capture_unarmed:bool)->void:
 if not enabled or grip_rotations.is_empty():return
 var references:Dictionary={}
 for node:Dictionary in body.nodes:references[node.name]=node.angles
 if capture_unarmed:
  unarmed_references=references.duplicate();unarmed_rotations.clear()
 for bone:String in grip_rotations:
  var index:int=body.skeleton.find_bone(bone)
  if capture_unarmed:unarmed_rotations[bone]=body.skeleton.get_bone_pose_rotation(index)
  body.skeleton.set_bone_pose_rotation(index,grip_rotations[bone]);references[bone]=grip_references[bone]
 assert(body.sync_final_pose(references),body.pose_sync_error)
func point(bone:String)->Vector3:return body.get_solved_bone_pose(body.skeleton.find_bone(bone)).origin
func sync_socket()->void:
 if not enabled:return
 var wrist:Vector3=point(HAND)
 var index:Vector3=point("lIndex1");var pinky:Vector3=point("lPinky1")
 var along:Vector3=(point("lMid1")-wrist).normalized()
 var blade:Vector3=(index-pinky).normalized()
 var normal:Vector3=blade.cross(along).normalized();blade=along.cross(normal).normalized()
 var roots:=Vector3.ZERO;var folds:=Vector3.ZERO
 for finger:String in ["Index","Mid","Ring","Pinky"]:
  roots+=point("l"+finger+"1")*.25;folds+=point("l"+finger+"2")*.25
 transform=Transform3D(Basis(-along,blade,normal),(roots+folds)*.5+body.root_offset)
