extends SceneTree
const Real=preload("res://scripts/net/real_server.gd")
const Contract=preload("res://scripts/net/remote/combat_contract.gd")
const StatusBar=preload("res://scripts/ui/status_icon_bar.gd")
const World=preload("res://scripts/world3d/world_3d.gd")
const Player=preload("res://scripts/world3d/world_player.gd")
const Net=preload("res://scripts/net/net.gd")
const SkillSlot=preload("res://scripts/ui/skill_slot.gd")
var failures:=0

class Transport extends Real:
	var requests:Array=[]
	var commands:Array=[]
	var definition_data:Dictionary={}
	var fail_status:=0
	var last_move:Dictionary={}
	func try_move_world(_sequence:int,direction:Vector3,speed:float,_jump:bool=false)->Dictionary:
		last_move={"direction":direction,"speed":speed};return {"ok":true}
	func is_world_ready()->bool:return true
	func request_api(path:String,method:int=HTTPClient.METHOD_GET,body:Dictionary={})->Dictionary:
		requests.append({"path":path,"method":method,"body":body.duplicate(true)})
		if fail_status!=0:return {"ok":false,"status":fail_status,"error":"fixture_failure"}
		return {"ok":true,"body":{"data":definition_data.duplicate(true)}}
	func gameplay_command(kind:String,body:Dictionary)->Dictionary:
		commands.append({"kind":kind,"body":body.duplicate(true)})
		return {"ok":true,"body":{"data":{}}}
	func refresh_gameplay_snapshots()->Dictionary:return {"ok":true}

class Model extends Node3D:
	var action:="idle"
	var locomotion_rate:=0.
	func play(next:String,_direction:String)->void:action=next

class RejectedTransport extends Real:
	func rpc_call(_operation:String,_payload:Dictionary={})->Dictionary:return {"error":"skill rejected"}
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func finish(server:Node,request:Dictionary)->Dictionary:
	if not request.get("deferred",false):return request
	while true:
		var reply:Array=await server.response_ready
		if int(reply[0])==int(request.request_id):return reply[1]
	return {}
func run()->void:
	var server:=Transport.new();root.add_child(server)
	server.world_session={"boot_id":"skill-test","session_epoch":1,"map_generation":2,"map_ref":"test/map","gameplay_protocol":1}
	server._session_character_id="1"
	server.self_actor={"id":"1","generation":2,"location":{"map_ref":"test/map","position_m":{"x":0,"y":0,"z":0}}}
	server.actors={"2":{"id":"2","generation":8,"location":{"map_ref":"test/map"}}}
	var projection=server.gameplay.projection
	projection.entities={"npc":{"map":"test/map","state":{"generation":3},"details":{"name":"Guard","level":1,"hp_max":20}}}
	check(projection.target("2")=={"id":"2","map":"test/map","generation":8},"player target uses authoritative actor generation")
	check(projection.target("1").generation==2,"self is available to unit party targeting")
	check(projection.target("npc").generation==3,"creature target preserves spawn identity")
	server.actors["2"].location.map_ref="test/elsewhere"
	check(projection.target("2").is_empty(),"other-map actor is not a valid target")
	server.actors["2"].location.map_ref="test/map";server.actors["2"].generation=2.5
	check(projection.target("2").is_empty(),"fractional generation fails closed")
	server.actors["2"].generation=8
	var skill:={"uuid":"heal","name":"Heal","target":{"mode":"unit","relation":"party","range_m":10},"cost":{"mp":2},"effects":[{"type":"heal_hp","base":7}],"timing":{"cooldown_ms":200}}
	server.definition_data=skill
	var cast:Dictionary=await finish(server,server.request_cast("heal","2"))
	check(cast.ok and server.commands[-1].kind=="cast" and server.commands[-1].body.target.generation==8,"unit player skill reaches WebSocket command")
	check(server.requests.size()==1 and server.requests[0].method==HTTPClient.METHOD_GET,"casting does not use HTTP mutation")
	var queued:Dictionary=server.request_cast("heal","2")
	server.actors["2"].generation=9
	var before:=server.commands.size()
	var stale:Dictionary=await finish(server,queued)
	check(not stale.ok and server.commands.size()==before,"queued skill cannot silently retarget a new life generation")
	server.actors.erase("2")
	check(projection.target("2").is_empty(),"AOI removal clears player target")
	skill.target={"mode":"area","relation":"hostile","range_m":10};server.definition_data=skill
	projection.definitions.clear()
	var area:Dictionary=await finish(server,server.request_cast("heal","",Vector3(4,0,0)))
	check(area.ok and is_equal_approx(float(server.commands[-1].body.aim.yaw_radians),-PI/2),"ground aim faces actual selected direction")
	check(is_equal_approx(Contract.aim_yaw(Vector3.ZERO,Vector3.ZERO,1.2),1.2),"coincident ground aim retains provided facing")
	check(Contract.category(skill)=="magic","effects array classifies healing skill")
	check(Contract.category(skill,{"category":"passive"})=="passive","learned passive category overrides visual guess")
	var row:=Contract.skill_row("heal",skill)
	check(row.desc.contains("治疗 7") and is_equal_approx(row.cooldown,.2),"skill description and timing come from server effects")
	var slot:=SkillSlot.new();root.add_child(slot);slot.setup("heal","Heal","magic",-1,-1,"",row.desc)
	check(slot.tooltip_text.contains("治疗 7"),"skill widget displays effect description")
	slot.queue_free()
	var training:={"version":1,"sequence":0,"enabled":true,"skill_points":8,"respec_gold":7,"respec_allowed":true,"attribute_respec_gold":3,"attribute_respec_allowed":true,"entries":[{"skill_uuid":"heal","rank":1,"max_rank":2,"granted":true,"category":"magic","definition":skill,"learnable":true}]}
	server.business_snapshots={"combat-state":{"hp":42,"hp_max":80,"mp":15,"mp_max":20},"progression":{"level":2,"experience":100,"gold":30},"inventory":{"stats":{"effective":{"attack":17,"defense":3,"hp_max":80,"mp_max":20},"points":{"str":5,"agi":5,"vit":5,"intel":5}}},"skills":{"grants":{"heal":true},"training":training},"statuses":{"game_time_us":1000000,"statuses":{"sequence":4,"active":[]},"cancelable":[]}}
	server.combat_stats.player.magic_attack=999
	projection.apply()
	check(server.combat_stats.player.hp==42 and server.combat_stats.player.atk==17 and not server.combat_stats.player.has("magic_attack"),"authoritative attribute replacement removes old Mock values")
	check(Contract.attribute_text(server.combat_stats.player.attributes.effective,"magic_attack")=="未提供","missing server attribute is explicitly unavailable")
	check(not server.combat_stats.npcs.npc.has("atk") and not server.combat_stats.npcs.npc.has("def"),"creature projection does not invent combat stats")
	check(server.snapshot_skill_book().skill_points==8,"server training skill points reach existing skill book")
	var learned:Dictionary=await finish(server,server.try_learn_skill("heal"))
	check(learned.ok and server.requests[-1].path=="/v1/gameplay/skill-training" and server.requests[-1].body=={"sequence":1,"action":"learn","skill_uuid":"heal"},"learning uses authority sequence and low-frequency training API")
	server.business_snapshots.skills.training.sequence=1
	var reset:Dictionary=await finish(server,server.try_skill_respec())
	check(reset.ok and server.requests[-1].body=={"sequence":2,"action":"respec"},"skill reset uses current training sequence")
	var attrs_reset:Dictionary=await finish(server,server.try_attr_respec())
	check(attrs_reset.ok and server.requests[-1].body.action=="attributes_respec","attribute reset reaches server policy operation")
	server.definition_data={"name":"first"}
	var first:Dictionary=await projection.definition("items","item")
	server.definition_data={"name":"second"}
	server.business_snapshots.skills.training.version=2
	var second:Dictionary=await projection.definition("items","item")
	check(first.name=="first" and second.name=="second","definition policy version invalidates stale definition cache")
	var status_id:="a".repeat(64)
	server.business_snapshots.statuses.statuses.active=[{"status_id":status_id,"definition":{"key":"stance","kind":"modifiers","duration_ms":10000,"policy":{"class":"buff"}},"stacks":1,"expires_game_us":11000000}]
	server.business_snapshots.statuses.cancelable=[status_id]
	var actions:Array=projection.actions()
	var statuses:Array=[]
	for action:Dictionary in actions:
		if action.type=="status_update":statuses=action.statuses
	check(statuses.size()==1 and statuses[0].can_cancel and statuses[0].kind=="buff","nested authoritative status snapshot reaches UI with cancellation permission")
	var bar:=StatusBar.new();bar.allow_cancel=true;root.add_child(bar);bar.apply_statuses(statuses)
	check(bar._buff_row.get_child(0).cancelable,"allowed status exposes cancel gesture")
	var cancelled:Dictionary=await finish(server,server.try_cancel_status(status_id))
	check(cancelled.ok and server.commands[-1]=={"kind":"cancel_status","body":{"status_id":status_id,"expected_sequence":4}},"status cancellation uses WebSocket with captured status revision")
	server.business_snapshots.statuses.erase("cancelable")
	check(not server.try_cancel_status(status_id).get("deferred",false),"old server without cancellation permission cannot delete local buff")
	statuses[0].can_cancel=false
	bar.apply_statuses(statuses);await process_frame
	check(not bar._buff_row.get_child(0).cancelable,"protected status suppresses cancel gesture")
	bar.queue_free()
	server.fail_status=404
	var unsupported:Dictionary=await finish(server,server.try_skill_training_refresh())
	check(not unsupported.ok and not server.try_learn_skill("heal").get("deferred",false),"old server training endpoint becomes explicit unsupported capability")
	var rejected:=RejectedTransport.new();root.add_child(rejected)
	var rejection:Dictionary=await rejected.gameplay_command("cast",{})
	check(rejection.has("ok") and not rejection.ok and rejection.error=="skill rejected","protobuf false-default RPC rejection normalizes adapter contract")
	rejected.queue_free()
	server.business_snapshots.statuses={}
	check(is_equal_approx(server.player_move_speed_mul(),1.),"old status snapshot retains normal movement speed")
	server.business_snapshots.statuses.control={"speed_bp":40000,"can_move":true}
	check(is_equal_approx(server.player_move_speed_mul(),4.),"real haste reads fourfold authoritative multiplier")
	Net.set_server(server)
	var player:=Player.new();var model:=Model.new();model.name="CharacterModel3D";player.add_child(model);root.add_child(player)
	player.set_physics_process(false);player.click_target=Vector3(2,0,0)
	var reversed:=false
	for step in 20:
		player._step(1./60.)
		var intent:Dictionary=server.last_move
		if intent.direction.x<0.:reversed=true
		var actual_speed:=4. if float(intent.speed)>2. else 1.6
		player.global_position+=intent.direction*actual_speed*server.player_move_speed_mul()*.05
		if player.click_target==null:break
	check(player.click_target==null and not reversed and absf(player.position.x-2.)<.34,"real click controller reaches endpoint under haste without oscillation")
	server.business_snapshots.statuses.control.can_move=false
	player.click_target=Vector3(5,0,0);player._step(1./60.)
	check(is_zero_approx(server.player_move_speed_mul()) and server.last_move.direction==Vector3.ZERO and player.click_target!=null,"blocked status keeps pending route and emits no movement intent")
	Net.clear_server_override();player.queue_free()
	server.queue_free()
	print("REMOTE_SKILL_CONTRACT_TESTS failures=",failures)
	quit(0 if failures==0 else 1)
