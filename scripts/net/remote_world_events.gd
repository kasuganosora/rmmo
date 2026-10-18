extends "res://scripts/world3d/world_events.gd"
## Authored event programs are never executed by a real client.
func mount(_map_ref:String,_specs:Array,_records:Array=[])->void:
	targets.clear();runtime.clear_session();runtime.events_by_id.clear();runtime.events_by_cell.clear()
func interact(id:String,_body:CharacterBody3D,_target:CollisionObject3D=null)->Array:
	server.try_interact(id,-9999,-9999)
	return []
func run(_id:String)->Array:return []
func choice(id:String="",index:int=-1)->Array:
	server.try_dialogue_choice(id,index)
	return []
func touch_segment(_from:Vector3,_to:Vector3)->Array:return []
