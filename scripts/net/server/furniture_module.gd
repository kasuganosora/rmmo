extends RefCounted
## In-process seat reservations, keyed by map and stable furniture UUID.
var occupants:Dictionary={}
func reserve(map_id:String,seat_id:String,actor_id:String)->bool:
 if map_id.is_empty() or seat_id.is_empty() or actor_id.is_empty():return false
 var key:String=map_id+"::"+seat_id
 if occupants.has(key) and occupants[key]!=actor_id:return false
 if not occupants.has(key) and actor_id in occupants.values():return false
 occupants[key]=actor_id;return true
func release(map_id:String,seat_id:String,actor_id:String)->void:
 var key:String=map_id+"::"+seat_id
 if occupants.get(key)==actor_id:occupants.erase(key)
func release_actor(actor_id:String)->void:
 for key in occupants.keys():
  if occupants[key]==actor_id:occupants.erase(key)
