extends RefCounted
## Horizontal seats share the normal character rig and authored chair actions.
var world
var seat:StaticBody3D
var original:Transform3D
var fixed:Transform3D
var seat_id:=""
var actor_id:=""
var map_id:=""
var exiting:=false
func _init(owner):world=owner
func active()->bool:return not seat_id.is_empty()
func interact(target:StaticBody3D)->bool:
 if active():stand();return true
 var player=world._player;var model=player._model
 if player.input_locked or world._transfer_pending or not world.Net.server().combat_stats.player_alive():return false
 if model.axis_rig==null or model.action in player.REST_ACTIONS:return false
 for clip in ["sit_chair","sit_chair_hold","stand_up_chair"]:
  if not model.axis_rig.supports(clip):return false
 if not is_instance_valid(target) or not target.has_meta("seat"):return false
 var data:Dictionary=target.get_meta("seat")
 var surface:Variant=data.get("surface",[]);var size:Variant=data.get("size",[])
 if not surface is Array or surface.size()!=3 or not size is Array or size.size()!=2:return false
 for number in surface+size:
  if typeof(number) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(number)):return false
 if float(size[0])<=0 or float(size[1])<=0:return false
 var basis:Basis=target.global_basis
 if basis.y.normalized().dot(Vector3.UP)<.999:return false
 var point:Vector3=target.to_global(Vector3(surface[0],surface[1],surface[2]))
 if player.global_position.distance_to(point)>2.0:return false
 var ray:=PhysicsRayQueryParameters3D.create(player.global_position,point+Vector3.UP*.05)
 ray.exclude=[player.get_rid(),target.get_rid()]
 if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return false
 var floor_query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.1,point-Vector3.UP*1.2)
 floor_query.exclude=ray.exclude
 var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(floor_query)
 if hit.is_empty() or (hit.normal as Vector3).y<.99:return false
 var yaw:float=atan2(basis.z.x,basis.z.z)
 var reference:Vector3=model.axis_rig.animations.reference_position(model.skeleton,"sit_chair_hold","hip")
 var ground:Vector3=point-Basis(Vector3.UP,yaw)*Vector3(reference.x,0,reference.z)
 ground.y=hit.position.y
 var next:Transform3D=Transform3D(Basis(Vector3.UP,yaw),ground+Vector3(0,.9,0))
 var shape_query:=PhysicsShapeQueryParameters3D.new()
 shape_query.shape=player.get_node("CollisionShape3D").shape
 shape_query.transform=next;shape_query.exclude=ray.exclude
 shape_query.margin=.001
 # Lift the probe off the supporting floor; test blockers at the interaction anchor.
 shape_query.transform.origin.y+=.02
 if not world.get_world_3d().direct_space_state.intersect_shape(shape_query,1).is_empty():return false
 var id:String=str(target.get_meta("uuid",""))
 var actor:String=world.Net.server()._party_self_id()
 if not world.Net.server().furniture.reserve(world._map_path,id,actor):return false
 world.cancel_sit_preparation()
 original=player.global_transform;fixed=target.global_transform
 seat=target;seat_id=id;actor_id=actor;map_id=world._map_path;exiting=false
 player.add_collision_exception_with(seat)
 player.global_transform=next;player.velocity=Vector3.ZERO
 var local:Vector3=model.to_local(point)
 model.axis_rig.seat.set_seat(local,Vector2(size[0]*basis.x.length(),size[1]*basis.z.length()),model.to_local(ground).y)
 world.Net.server().sitting=true
 player.request_rest("sit_chair")
 world.Net.server().world3d_authority._publish(player)
 return true
func stand()->void:
 if not active() or exiting:return
 exiting=true;world.Net.server().sitting=false
 world._player._model.play("stand_up_chair","front",true)
func tick()->void:
 if not active():return
 if not is_instance_valid(seat) or seat.global_transform!=fixed:
  cancel();return
 var model=world._player._model
 if model.axis_rig==null or not model.axis_rig.seat.enabled:
  cancel();return
 if model.action not in ["sit_chair","sit_chair_hold","stand_up_chair"]:
  cancel(true);return
 if model.action=="stand_up_chair":exiting=true;world.Net.server().sitting=false
func cancel(preserve_action:bool=false)->void:
 if not active():return
 var player=world._player
 if is_instance_valid(player) and player.is_inside_tree():
  if is_instance_valid(seat):player.remove_collision_exception_with(seat)
  player.global_transform=original;player.velocity=Vector3.ZERO
  var model=player._model
  if model.axis_rig!=null:model.axis_rig.seat.clear()
  if not preserve_action:model.play("idle","front",true)
  world.Net.server().world3d_authority._publish(player)
 world.Net.server().furniture.release(map_id,seat_id,actor_id)
 world.Net.server().sitting=false
 seat=null;seat_id="";exiting=false
