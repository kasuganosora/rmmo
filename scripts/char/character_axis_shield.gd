extends Node3D
## Strapped off-hand shield. No arm pose changes or world-space offsets.
var body:Node3D
var item_id:=""
var straps:Array[MeshInstance3D]=[]
var board:MeshInstance3D
func configure(target:Node3D)->void:
 body=target
 board=MeshInstance3D.new()
 var disk:=CylinderMesh.new();disk.top_radius=.22;disk.bottom_radius=.22;disk.height=.035;disk.radial_segments=32
 board.mesh=disk;board.rotation.x=PI*.5
 var wood:=StandardMaterial3D.new();wood.albedo_color=Color("94683f");wood.roughness=.85;board.material_override=wood
 add_child(board)
 for i in 2:
  var strap:=MeshInstance3D.new();strap.mesh=TorusMesh.new()
  var leather:=StandardMaterial3D.new();leather.albedo_color=Color("493323");leather.roughness=.9
  strap.material_override=leather;add_child(strap);straps.append(strap)
 visible=false;body.surface_updated.connect(sync_socket)
func set_equipment(parts:Dictionary)->void:
 item_id=str(parts.get("WeaponOffItem",""))
 visible=item_id=="wood_shield"
 if visible:sync_socket()
func point(bone:String)->Vector3:return body.get_solved_bone_pose(body.skeleton.find_bone(bone)).origin
func sync_socket()->void:
 if not visible:return
 var elbow:Vector3=point("rForeArm");var wrist:Vector3=point("rHand")
 var along:Vector3=(wrist-elbow).normalized()
 var across:Vector3=point("rIndex1")-point("rPinky1")
 var outward:Vector3=across.cross(along).normalized()
 var right:Vector3=along.cross(outward).normalized()
 var length:float=elbow.distance_to(wrist)
 # Proxy radius follows the forearm; fixed constants describe the gear itself.
 var radius:float=length*.16
 var center:Vector3=elbow.lerp(wrist,.6)
 transform=Transform3D(Basis(right,along,outward),center+body.root_offset)
 board.position.z=radius+.0175
 for i in straps.size():
  var ring:TorusMesh=straps[i].mesh
  ring.inner_radius=radius-.004;ring.outer_radius=radius+.004
  straps[i].position.y=length*(-.16 if i==0 else .16)
