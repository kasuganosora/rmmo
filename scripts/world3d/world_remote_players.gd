extends RefCounted
## Mocker peer snapshots use metre coordinates, never legacy tile coordinates.
const Expressions=preload("res://scripts/char/character_expressions.gd")
var world
var models:Dictionary={}
var states:Dictionary={}
func _init(owner):world=owner

func pick(screen:Vector2,terrain_hit:Dictionary)->String:
 if not world.Net.is_real_server():return ""
 var camera:Camera3D=world._camera.get_node("Camera3D")
 var origin:=camera.project_ray_origin(screen)
 var direction:=camera.project_ray_normal(screen)
 var limit:=origin.distance_to(terrain_hit.position) if terrain_hit.has("position") else 80.
 var chosen:=""
 for id:String in models:
  if not world.Net.server().actors.has(id) or world.Net.server().gameplay.projection.target(id).is_empty():continue
  var actor:Dictionary=world.Net.server().actors[id]
  var feet:Vector3=models[id].global_position
  var radius:=clampf(float(actor.get("body_radius",.3)),.1,2.)
  var height:=clampf(float(actor.get("body_height",1.8)),.2,5.)
  var bounds:=AABB(feet-Vector3(radius,0,radius),Vector3(radius*2,height,radius*2))
  var point:Variant=bounds.intersects_ray(origin,direction)
  if point is Vector3:
   var distance:=origin.distance_to(point)
   if distance<limit or is_equal_approx(distance,limit) and (chosen.is_empty() or id<chosen):limit=distance;chosen=id
 return chosen
func receive(action:Dictionary)->void:
 var id:=str(action.get("actor_id",""))
 var weights:Variant=action.get("weights",{})
 if id.is_empty() or not weights is Dictionary:return
 var normalized:=Expressions.normalize(weights)
 if normalized.has("invalid"):return
 var revision:=int(action.get("revision",0))
 if revision<=int(states.get(id,{}).get("revision",-1)):return
 states[id]={"weights":normalized,"revision":revision}
 if id==world.Net.server()._party_self_id():world._player._model.transition_expressions(normalized)
 elif models.has(id):models[id].transition_expressions(normalized)
func spawn(row:Dictionary)->void:
 var id:=str(row.get("id",""))
 var point:Variant=row.get("position_m",[])
 if id.is_empty() or not point is Array or point.size()!=3:return
 if str(row.get("map_path",""))!=world._map_path:return
 for coordinate in point:
  if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)):return
 if not models.has(id):
  var recipe:Dictionary=row.duplicate(true)
  if recipe.get("equipment",{}) is Array:
   recipe["equipment"]=preload("res://scripts/char/character_view_3d.gd").equipment_parts(str(recipe.get("gender","male")),recipe.equipment,world.Net.server().item_catalog)
  var model=preload("res://scripts/char/character_model_3d.gd").create_npc(recipe)
  world.add_child(model);models[id]=model
 models[id].position=Vector3(point[0],point[1],point[2])
 var face:Dictionary=row.get("facial_expression",{})
 if not face.is_empty():receive({"actor_id":id,"weights":face.get("weights",{}),"revision":face.get("revision",0)})
 if states.has(id):models[id].set_expressions(states[id].weights)
func despawn(id:String)->void:
 if models.has(id):
  models[id].free();models.erase(id)
 # Keep revision tombstone so a late packet cannot resurrect an old expression.
func refresh()->void:
 for id in models.keys():despawn(id)
 states.clear()
 var server=world.Net.server()
 var local:Dictionary=server.facial_expressions.snapshot(server._party_self_id())
 receive({"actor_id":server._party_self_id(),"weights":local.weights,"revision":local.revision})
 for row:Dictionary in server.snapshot_remote_players():spawn(row)
