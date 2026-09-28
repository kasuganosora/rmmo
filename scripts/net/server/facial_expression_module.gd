extends RefCounted
const Expressions=preload("res://scripts/char/character_expressions.gd")
var ctrl
var states:Dictionary={}
var serial:=0
var pending:Dictionary={}
func _init(owner):ctrl=owner
func reset()->void:
 states.clear();pending.clear()
 # Revisions stay monotonic across character sessions.
func snapshot(actor_id:String)->Dictionary:
 return states.get(actor_id,{"weights":{},"revision":0}).duplicate(true)
func request(weights:Dictionary)->Dictionary:
 if ctrl.awaiting_respawn or not ctrl.combat_stats.player_alive():return {"ok":false,"actions":[]}
 return _accept(ctrl._party_self_id(),weights)
func debug_remote(actor_id:String,weights:Dictionary)->Dictionary:
 if not ctrl._remote_players.has(actor_id):return {"ok":false,"actions":[]}
 var result:=_accept(actor_id,weights)
 if result.ok:ctrl._remote_players[actor_id]["facial_expression"]=snapshot(actor_id)
 return result
func _accept(actor_id:String,weights:Dictionary)->Dictionary:
 var normalized:=Expressions.normalize(weights)
 if normalized.has("invalid"):return {"ok":false,"reason":"invalid_expression","actions":[]}
 serial+=1
 states[actor_id]={"weights":normalized.duplicate(true),"revision":serial}
 var action:Dictionary={"type":"facial_expression","actor_id":actor_id,"weights":normalized,"revision":serial}
 pending[actor_id]=action.duplicate(true)
 return {"ok":true,"actions":[action]}

func drain()->Array:
 var actions:Array=pending.values().duplicate(true)
 pending.clear()
 return actions

func spawn_peer(display_name:String,map_path:String,feet:Vector3)->Dictionary:
 if map_path.is_empty() or not feet.is_finite():return {"ok":false,"actions":[]}
 var result:Dictionary=ctrl.try_remote_debug_spawn(display_name)
 if not result.get("ok",false):return result
 var id:String=result.remote_id
 ctrl._remote_players[id]["position_m"]=[feet.x,feet.y,feet.z]
 ctrl._remote_players[id]["map_path"]=map_path
 return {"ok":true,"remote_id":id,"actions":[ctrl._remote_spawn_action(id)]}
