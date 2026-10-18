extends "res://scripts/world3d/world_events.gd"
## Authored event programs are never executed by a real client.
func mount(_map_ref:String,_specs:Array,_records:Array=[])->void:
	targets.clear();runtime.clear_session();runtime.events_by_id.clear();runtime.events_by_cell.clear()
func interact(_id:String,_body:CharacterBody3D,_target:CollisionObject3D=null)->Array:return []
func run(_id:String)->Array:return []
func choice(_id:String="",_index:int=-1)->Array:return []
func touch_segment(_from:Vector3,_to:Vector3)->Array:return []
