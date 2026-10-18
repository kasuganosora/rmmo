extends "res://scripts/world3d/world_authority.gd"
## Only render server snapshots. No local collision, gravity or step simulation.
var transport:Node
var _last_position:=Vector3.ZERO
func _init(owner:Node)->void:transport=owner
func mount(body:CharacterBody3D,navigation:Node,map_ref:String)->void:
	super.mount(body,navigation,map_ref)
	apply_actor(transport.self_actor)
func move_intent(_seq:int,direction:Vector3,speed:float,jump:bool=false)->Dictionary:
	if movement_allowed.is_valid() and not movement_allowed.call():direction=Vector3.ZERO;jump=false
	return transport.queue_movement(direction,speed>2.,jump,false)
func apply_actor(actor:Dictionary)->void:
	var body:CharacterBody3D=_body.get_ref() if _body!=null else null
	if body==null or actor.is_empty():return
	var location:Dictionary=actor.get("location",{})
	if location.get("map_ref","")!=_map_ref:return
	if preload("res://scripts/world3d/player_clearance.gd").apply_server(body,float(actor.get("body_radius",0)),float(actor.get("body_height",0)))<0:
		transport.disconnect_server("服务器角色碰撞尺寸无效，请更新双端协议")
		return
	var value:Dictionary=location.get("position_m",{})
	var feet:=Vector3(value.get("x",0.),value.get("y",0.),value.get("z",0.))
	var next:=feet+Vector3.UP*.9
	body.velocity=(next-body.global_position)*float(ProjectSettings.get_setting("rmmo/network/movement_hz",20.))
	body.global_position=next;body.surface_id=str(location.get("surface_id","ground"))
	snapshot={"map_ref":_map_ref,"position_m":[feet.x,feet.y,feet.z],"surface_id":body.surface_id,"sequence":actor.get("sequence",0),"mode":actor.get("mode","ground")}
