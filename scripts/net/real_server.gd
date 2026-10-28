extends "res://scripts/net/real_gameplay_api.gd"
## Real Go transport. Inherited objects are UI projections; scaffold requests,
## snapshot methods and simulation are fenced by remote_boundary.gd.
const Wire=preload("res://scripts/net/protocol/protobuf.gd")
const ConnectionConfig=preload("res://scripts/net/connection_config.gd")
signal response_ready(request_id:int,result:Dictionary)
signal connection_lost(message:String)
signal characters_failed(message:String)
signal world_changed(session:Dictionary)
signal api_response(request_id:int,result:Dictionary)

class Ticket extends RefCounted:
	signal finished(result:Dictionary)
	var done:=false
	var result:Dictionary={}
	func resolve(value:Dictionary)->void:
		if done:return
		done=true;result=value;finished.emit(value)

var endpoint_address:="http://127.0.0.1:7777"
var configuration_error:=""
var self_actor:Dictionary={}
var world_session:Dictionary={}
var actors:Dictionary={}
var _retired_actors:Dictionary={}
var _peer_visibility=preload("res://scripts/net/remote/peer_visibility.gd").new()
var _visibility_recovering:=false
var business_snapshots:Dictionary={}
var _peer:WebSocketPeer
var _token:=""
var _endpoint:Dictionary={}
var _pending:Dictionary={}
var _request_serial:=0
var _network_actions:Array=[]
var _movement:Dictionary={}
var _movement_at:=0
var _movement_sequence:=0
var _move_inflight:=false
var _snapshot_at:=0
var _connection_revision:=0
var _selected_id:=0
var _map_path:=""
var _local_loaded_context:Dictionary={}
var _http_requests:Dictionary={}
var _snapshot_inflight:=false
var _snapshot_revision:=0

func is_remote_transport()->bool:return true

func _ready()->void:
	# Catalogs and snapshot models are shared with the existing HUD; no starter
	# rewards, bots, combat ticks, weather simulation or local world are run.
	_init_combat_layers()
	inventory.clear();equipment.clear();quest_journal.clear();mailbox.clear();auction.clear()
	inventory=preload("res://scripts/net/remote/inventory.gd").new();inventory.set_catalog(item_catalog)
	item_catalog._by_id.clear();skill_catalog._by_id.clear()
	skill_catalog.register_skill({"id":"basic_attack","name":"普通攻击","requires_target":true,"starter":true})
	combat_stats.player.hp=0
	_accounts.clear();_remote_players.clear()
	world3d_authority=preload("res://scripts/net/remote_world_authority.gd").new(self)
	world3d_events=preload("res://scripts/net/remote_world_events.gd").new(self)

func _timeout()->float:return clampf(float(ProjectSettings.get_setting("rmmo/network/request_timeout_sec",10.)),1.,60.)
func _hz()->float:return clampf(float(ProjectSettings.get_setting("rmmo/network/movement_hz",20.)),5.,30.)
func is_logged_in()->bool:return not _token.is_empty() and _peer!=null and _peer.get_ready_state()==WebSocketPeer.STATE_OPEN
func current_server()->String:return endpoint_address

func _process(_delta:float)->void:
	if _peer==null:return
	_peer.poll()
	if _peer.get_ready_state()==WebSocketPeer.STATE_CLOSED:
		disconnect_server("与真实服务器的连接已断开，请重新登录或重连");return
	if _peer.get_ready_state()!=WebSocketPeer.STATE_OPEN:return
	var received:=0
	while _peer.get_available_packet_count()>0 and received<64:
		var bytes:=_peer.get_packet();received+=1
		if _peer.was_string_packet():disconnect_server("服务器发送了非二进制协议帧");return
		var decoded:=Wire.decode("ServerMessage",bytes)
		if not decoded.ok:disconnect_server("服务器协议解码失败："+decoded.error);return
		_receive(decoded.data)
		if _peer==null:return
	var now:=Time.get_ticks_msec()
	for id:int in _pending.keys():
		if now>int(_pending[id].deadline):
			var entry:Dictionary=_pending[id];_pending.erase(id)
			entry.ticket.resolve({"ok":false,"error":"request_timeout","request_id":id})
			# A missing world reply may conceal an accepted movement or transfer.
			if not entry.scope.is_empty():disconnect_server("世界请求超时，已停止发送输入，请重连恢复快照");return
	if is_world_ready() and not _move_inflight and now>=_movement_at and not _movement.is_empty():
		_movement_at=now+int(1000./_hz());_send_movement()
	if is_world_ready() and not _snapshot_inflight and now>=_snapshot_at:
		if not gameplay.busy():_snapshot_at=now+int(clampf(float(ProjectSettings.get_setting("rmmo/network/snapshot_interval_sec",.25)),.1,5.)*1000);_refresh_runtime_snapshots()
		gameplay.poll_events()

func disconnect_server(message:String="")->void:
	_connection_revision+=1
	gameplay.cancel()
	if _peer!=null:_peer.close();_peer=null
	var requests:=_http_requests;_http_requests={}
	for request:HTTPRequest in requests:
		requests[request].resolve({"ok":false,"error":"connection_closed"})
		if is_instance_valid(request):request.cancel_request();request.queue_free()
	world_session.clear();self_actor.clear();actors.clear();_retired_actors.clear();_peer_visibility.clear();_visibility_recovering=false;business_snapshots.clear();_local_loaded_context.clear()
	_movement.clear();_move_inflight=false;_login_inflight=false
	_snapshot_inflight=false;_fetch_inflight=false;_create_inflight=false;_enter_inflight=false
	world3d_authority.release()
	var pending:=_pending;_pending={}
	for entry:Dictionary in pending.values():entry.ticket.resolve({"ok":false,"error":"connection_closed"})
	if not message.is_empty():
		_network_actions.append({"type":"system_message","text":message})
		connection_lost.emit(message)

func logout()->void:
	disconnect_server();_token="";_selected_id=0;_session_user="";_session_character_id=""

func login(username:String,password:String,address:String)->void:
	_authenticate("login",username,password,address)

func register_account(username:String,password:String,address:String)->void:
	_authenticate("register",username,password,address)

func _authenticate(operation:String,username:String,password:String,address:String)->void:
	if _login_inflight:return
	if not configuration_error.is_empty():login_finished.emit(false,configuration_error);return
	disconnect_server();_token="";_login_inflight=true
	_selected_id=0;_session_character_id=""
	endpoint_address=address;_endpoint=ConnectionConfig.endpoint(address)
	if not _endpoint.ok:
		_login_inflight=false;login_finished.emit(false,_endpoint.error);return
	if username.strip_edges().is_empty() or password.is_empty():
		_login_inflight=false;login_finished.emit(false,"请输入账号和密码");return
	var connected:bool=await _connect_socket()
	if not connected:
		_login_inflight=false;login_finished.emit(false,"无法连接真实服务器："+address);return
	var result:Dictionary=await rpc_call(operation,{"username":username.strip_edges(),"password":password})
	_login_inflight=false
	if result.get("ok",false) and not str(result.get("token","")).is_empty():
		_token=result.token;_session_user=username.strip_edges();_session_server=address
		login_finished.emit(true,str(result.get("message","登录成功")))
	else:login_finished.emit(false,_message(result))

func _connect_socket(use_token:bool=false)->bool:
	_peer=WebSocketPeer.new();_peer.inbound_buffer_size=Wire.MAX_BYTES;_peer.outbound_buffer_size=Wire.MAX_BYTES
	_peer.max_queued_packets=256
	if use_token:_peer.handshake_headers=PackedStringArray(["Authorization: Bearer "+_token])
	if _peer.connect_to_url(_endpoint.websocket)!=OK:_peer=null;return false
	var revision:=_connection_revision;var until:=Time.get_ticks_msec()+int(_timeout()*1000)
	while revision==_connection_revision and _peer!=null and _peer.get_ready_state()==WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	return revision==_connection_revision and _peer!=null and _peer.get_ready_state()==WebSocketPeer.STATE_OPEN

func reconnect()->Dictionary:
	if _token.is_empty() or _selected_id==0:return {"ok":false,"error":"login_required"}
	disconnect_server()
	if not await _connect_socket(true):return {"ok":false,"error":"connection_failed"}
	var result:Dictionary=await rpc_call("enter_world",{"character_id":_selected_id,"visibility_protocol":1})
	if result.get("ok",false):result=prepare_authoritative_map()
	if result.get("ok",false):result=await refresh_world_snapshots()
	if result.get("ok",false):_project_snapshots();world_changed.emit(world_session.duplicate(true))
	return result

func _send(operation:String,body:Dictionary)->Ticket:
	var ticket:=Ticket.new()
	if _peer==null or _peer.get_ready_state()!=WebSocketPeer.STATE_OPEN:
		ticket.resolve({"ok":false,"error":"connection_closed"});return ticket
	if _pending.size()>=256:ticket.resolve({"ok":false,"error":"request_limit"});return ticket
	_request_serial=(_request_serial%4294967295)+1
	while _pending.has(_request_serial):_request_serial=(_request_serial%4294967295)+1
	var request:={"request_id":_request_serial,operation:body};var scope:Dictionary={}
	if operation in ["try_move","find_path","snapshot_actors","world_ready","leave_world"]:
		scope=context()
		if scope.is_empty():ticket.resolve({"ok":false,"error":"world_not_entered"});return ticket
		request.world_context=scope
	var encoded:=Wire.encode("ClientMessage",request)
	if not encoded.ok:ticket.resolve(encoded);return ticket
	_pending[_request_serial]={"ticket":ticket,"scope":scope,"operation":operation,"deadline":Time.get_ticks_msec()+int(_timeout()*1000)}
	if _peer.send(encoded.bytes,WebSocketPeer.WRITE_MODE_BINARY)!=OK:
		_pending.erase(_request_serial);ticket.resolve({"ok":false,"error":"send_failed"})
	return ticket

func rpc_call(operation:String,body:Dictionary={})->Dictionary:
	var ticket:=_send(operation,body)
	return ticket.result if ticket.done else await ticket.finished

func context()->Dictionary:
	if world_session.is_empty():return {}
	return {"boot_id":world_session.boot_id,"session_epoch":world_session.session_epoch,"map_generation":world_session.map_generation,"map_ref":world_session.map_ref}
func is_world_ready()->bool:return is_logged_in() and world_session.get("ready",false) and _local_loaded_context==context()

func _valid_session(value:Dictionary)->bool:
	var visibility:Variant=value.get("visibility_protocol",0)
	return _peer_visibility._integer(visibility) and int(visibility)<=1 and value.get("protocol_version",0)==2 and not str(value.get("boot_id","")).is_empty() and int(value.get("session_epoch",0))>0 and int(value.get("session_epoch",0))<=9007199254740991 and int(value.get("map_generation",0))>0 and int(value.get("map_generation",0))<=9007199254740991 and preload("res://scripts/world3d/world_location.gd").map_ref_ok(str(value.get("map_ref",""))) and not str(value.get("ready_token","")).is_empty()

func _receive(data:Dictionary)->void:
	var id:=int(data.get("request_id",0));var entry:Dictionary=_pending.get(id,{})
	var incoming:Dictionary=data.get("world_session",{})
	if not incoming.is_empty():
		if not _valid_session(incoming):disconnect_server("不支持的服务器世界会话协议");return
		incoming=incoming.duplicate(true)
		for key:String in ["session_epoch","map_generation","movement_sequence","protocol_version","visibility_protocol"]:
			var value:Variant=incoming.get(key,0)
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)!=floorf(float(value)):
				disconnect_server("服务器会话序号无效");return
			incoming[key]=int(value)
		incoming.ready=incoming.get("ready",false)
		if world_session.is_empty() and entry.get("operation","")!="enter_world":return
		var incoming_context:={"boot_id":incoming.boot_id,"session_epoch":incoming.session_epoch,"map_generation":incoming.map_generation,"map_ref":incoming.map_ref}
		var changed:=incoming_context!=context()
		if changed and not world_session.is_empty():
			if incoming.boot_id!=world_session.boot_id or incoming.session_epoch<world_session.session_epoch or (incoming.session_epoch==world_session.session_epoch and incoming.map_generation<=world_session.map_generation):return
			if not data.get("resync",false) and entry.get("operation","")!="enter_world":return
		if changed:
			_movement.clear();_local_loaded_context.clear();actors.clear();_retired_actors.clear();_peer_visibility.clear();_visibility_recovering=false;business_snapshots.clear()
			_network_actions.clear()
			world3d_authority.release()
			_movement_sequence=int(incoming.get("movement_sequence",0))
			# Never put fresh context around old input, paths or Ready callbacks.
			for old:int in _pending.keys():
				if old==id or _pending[old].scope.is_empty():continue
				var cancelled:Dictionary=_pending[old];_pending.erase(old)
				cancelled.ticket.resolve({"ok":false,"error":"stale_world_response"})
		if not changed:incoming.ready=incoming.ready or world_session.get("ready",false)
		world_session=incoming.duplicate(true)
		_movement_sequence=maxi(_movement_sequence,int(incoming.get("movement_sequence",0)))
		var old_visibility:bool=not changed and incoming.get("visibility_protocol",0)==1 and data.get("visibility") is Dictionary and int(data.visibility.get("revision",0))<=_peer_visibility.revision
		if data.has("actor_3d") and not old_visibility:
			var actor:Dictionary=data.actor_3d
			if entry.get("operation","")=="enter_world":_session_character_id=str(actor.get("id",""))
			if incoming.get("visibility_protocol",0)!=1 or str(actor.get("id",""))==_session_character_id:_accept_actor(actor)
		if data.has("actors_3d") and incoming.get("visibility_protocol",0)!=1:
			for actor:Dictionary in data.actors_3d:_accept_actor(actor)
		if data.get("resync",false) and (changed or not data.get("visibility") is Dictionary):
			_movement.clear();_movement_sequence=int(self_actor.get("sequence",incoming.get("movement_sequence",0)))
		if incoming.get("visibility_protocol",0)==1 and data.get("visibility") is Dictionary:
			_apply_visibility(data.visibility)
			if world_session.is_empty():return
		var left:=str(data.get("actor_left","")) if incoming.get("visibility_protocol",0)!=1 else ""
		if not left.is_empty():_retired_actors[left]=maxi(int(_retired_actors.get(left,0)),int(data.get("actor_left_generation",0)))
		if actors.has(left) and actors[left].get("generation",0)==data.get("actor_left_generation",0):
			actors.erase(left);_network_actions.append({"type":"remote_despawn","id":left})
		if changed and entry.get("operation","")!="enter_world":world_changed.emit(world_session.duplicate(true))
	elif data.has("actor_3d") or data.has("actors_3d") or data.get("push",false):return
	if entry.is_empty():return
	_pending.erase(id)
	if not entry.scope.is_empty() and entry.scope!=context():
		entry.ticket.resolve({"ok":false,"error":"stale_world_response"});return
	entry.ticket.resolve(data)

func _apply_visibility(update:Dictionary)->void:
	var result:Dictionary=_peer_visibility.apply(update,str(world_session.get("map_ref","")),_session_character_id)
	if not result.ok:disconnect_server("服务器视野同步数据无效");return
	if result.get("ignored",false):return
	if result.get("gap",false):
		if not _visibility_recovering:_recover_visibility()
		return
	for id:String in result.get("removed",[]):
		actors.erase(id);_network_actions.append({"type":"remote_despawn","id":id})
	for actor:Dictionary in result.get("actors",[]):_accept_actor(actor)

func _recover_visibility()->void:
	_visibility_recovering=true
	var scope:=context();var connection:=_connection_revision
	var result:Dictionary=await rpc_call("snapshot_actors")
	if connection!=_connection_revision or scope!=context():return
	_visibility_recovering=false
	if not result.get("ok",false) or not result.get("visibility",{}).get("full_snapshot",false):
		disconnect_server("视野同步中断，请重连恢复快照")

func _receive_world_snapshot(body:Dictionary)->void:
	var message:={"world_session":body.get("data",{}),"actor_3d":body.get("actor_3d",{}),"actors_3d":body.get("actors_3d",[]),"resync":true,"ok":true,"push":true}
	if body.get("visibility") is Dictionary:message.visibility=body.visibility
	_receive(message)

func _accept_actor(actor:Dictionary)->void:
	var id:=str(actor.get("id",""));var location:Dictionary=actor.get("location",{})
	if id.is_empty() or location.get("map_ref","")!=world_session.get("map_ref",""):return
	if int(actor.get("generation",0))<=int(_retired_actors.get(id,-1)):return
	var point:Dictionary=location.get("position_m",{})
	var vector:=Vector3(point.get("x",0.),point.get("y",0.),point.get("z",0.))
	if not vector.is_finite():return
	var old:Dictionary=actors.get(id,{})
	if not old.is_empty() and (int(actor.get("generation",0))<int(old.get("generation",0)) or (actor.get("generation",0)==old.get("generation",0) and int(actor.get("sequence",0))<int(old.get("sequence",0)))):return
	actors[id]=actor.duplicate(true)
	if id==_session_character_id:
		if actor.get("generation",0)!=world_session.get("map_generation",0):return
		self_actor=actor.duplicate(true);_movement_sequence=maxi(_movement_sequence,int(actor.get("sequence",0)))
		world3d_authority.apply_actor(actor)
	else:
		_network_actions.append({"type":"remote_spawn","player":_peer_row(actor)})

func _peer_row(actor:Dictionary)->Dictionary:
	var p:Dictionary=actor.get("location",{}).get("position_m",{})
	return {"id":str(actor.get("id","")),"name":"玩家 "+str(actor.get("id","")),"map_path":_map_path,"position_m":[p.get("x",0.),p.get("y",0.),p.get("z",0.)],"generation":actor.get("generation",0),"gender":"male","equipment":[]}

func fetch_characters()->void:
	if _fetch_inflight:return
	_fetch_inflight=true
	var result:Dictionary=await rpc_call("fetch_characters")
	_fetch_inflight=false
	var rows:Array=[]
	if result.get("ok",false):
		for row:Dictionary in result.get("characters",[]):rows.append(_character(row))
	characters_ready.emit(rows)
	if not result.get("ok",false):characters_failed.emit(_message(result))

func _character(row:Dictionary)->Dictionary:
	var character:=row.duplicate(true)
	character["hp"]=row.get("hp",0);character["hp_max"]=row.get("hp_max",100)
	character["customization"]={};character["equipment"]=[]
	preload("res://scripts/char/character_body_migration.gd").apply(character)
	return character

func create_character(char_name:String,class_id:String,look_id:String,gender:String="female",customization:Dictionary={})->void:
	if _create_inflight:return
	if not customization.is_empty():
		character_created.emit(false,"真实服务器暂不保存自定义外观，请选择基础外观",{});return
	_create_inflight=true
	var result:Dictionary=await rpc_call("create_character",{"name":char_name,"class_id":class_id,"look_id":look_id,"gender":gender})
	_create_inflight=false
	character_created.emit(result.get("ok",false),_message(result),_character(result.character) if result.has("character") else {})

func enter_world(character_id:int)->void:enter_world3d(character_id)
func enter_world3d(character_id:int)->void:
	if _enter_inflight:return
	_enter_inflight=true;_selected_id=character_id
	var result:Dictionary=await rpc_call("enter_world",{"character_id":character_id,"visibility_protocol":1})
	if result.get("ok",false):result=prepare_authoritative_map()
	if result.get("ok",false):result=await refresh_world_snapshots()
	_enter_inflight=false
	if not result.get("ok",false):enter_world_ready.emit(false,_message(result),{});return
	var session:=get_node_or_null("/root/GameSession")
	var character:Dictionary=session.selected_character.duplicate(true) if session!=null else {"id":character_id,"gender":"female"}
	character["customization"]=character.get("customization",{})
	combat_stats.reset_player(int(character.get("level",1)))
	_project_snapshots()
	enter_world_ready.emit(true,"已连接真实服务器，正在加载权威地图",{"character":character,"combat":combat_stats.snapshot_player_stats(),"inventory":gameplay.projection.bag(),"gold":business_snapshots.get("progression",{}).get("gold",0),"equipment":_equipment_rows(),"quests":snapshot_quest_journal(),"world_session":world_session.duplicate(true),"map_ref":world_session.map_ref})

func refresh_world_snapshots()->Dictionary:
	var scope:=context();var snapshots:Dictionary={}
	for name:String in ["inventory","attributes","progression","combat-state","entities","skills","statuses","areas","party","alliance","rewards","resurrection"]:
		var result:Dictionary=await _read_rewards() if name=="rewards" else await request_api("/v1/gameplay/"+name)
		if not result.ok:return {"ok":false,"error":"无法恢复服务器快照："+name+" "+str(result.get("error",""))}
		snapshots[name]=result.body.get("data",{})
	var sky:Dictionary=await request_api("/v1/environment")
	if not sky.ok:return sky
	snapshots.environment=sky.body
	var interactions:Dictionary=await _read_interactions()
	if not interactions.ok:return interactions
	snapshots.interactions=interactions.data
	var final:Dictionary=await request_api("/v1/world/session")
	if not final.ok or scope!=context() or _http_context(final.body.get("data",{}))!=scope:return {"ok":false,"error":"world_changed_during_snapshot"}
	_receive_world_snapshot(final.body)
	business_snapshots=snapshots;_snapshot_revision+=1
	return await gameplay.projection.hydrate()

func _read_rewards()->Dictionary:
	var rows:Array=[];var after:=""
	for page in 64:
		var result:Dictionary=await request_api("/v1/gameplay/rewards?limit=50"+("&after="+after if not after.is_empty() else ""))
		if not result.ok:return result
		var data:Dictionary=result.body.get("data",{})
		for row:Dictionary in data.get("rewards",[]):
			if not row.get("claimed",false):rows.append(row)
		if rows.size()>512:return {"ok":false,"error":"reward_snapshot_budget"}
		if not data.get("more",false):return {"ok":true,"body":{"data":{"rewards":rows}}}
		var next:=str(data.get("next",""))
		if next.is_empty() or next==after:return {"ok":false,"error":"reward_cursor_loop"}
		after=next
	return {"ok":false,"error":"reward_page_budget"}

func _http_context(value:Dictionary)->Dictionary:
	return {"boot_id":value.get("boot_id",""),"session_epoch":int(value.get("session_epoch",0)),"map_generation":int(value.get("map_generation",0)),"map_ref":value.get("map_ref","")}

func _read_interactions()->Dictionary:
	var objects:Array=[];var cursor:="";var first:Dictionary={}
	for page in 64:
		var result:Dictionary=await request_api("/v1/world/interactions"+("?cursor="+cursor.uri_encode() if not cursor.is_empty() else ""))
		if not result.ok:return result
		var data:Dictionary=result.body
		if first.is_empty():first=data.duplicate(true)
		if data.get("revision")!=first.get("revision") or data.get("definition_revision")!=first.get("definition_revision") or data.get("access_revision",0)!=first.get("access_revision",0):return {"ok":false,"error":"interaction_revision_changed"}
		if data.get("objects") is Array:objects.append_array(data.objects)
		if objects.size()>16384:return {"ok":false,"error":"interaction_object_budget"}
		var next:=str(data.get("next_cursor",""))
		if next.is_empty():first.objects=objects;return {"ok":true,"data":first}
		if next==cursor:return {"ok":false,"error":"interaction_cursor_loop"}
		cursor=next
	return {"ok":false,"error":"interaction_page_budget"}

func _project_snapshots()->void:
	var alive:bool=combat_stats.player_alive()
	var state:Variant=business_snapshots.get("combat-state",{})
	if state is Dictionary:
		for key:String in ["hp","hp_max","mp","mp_max"]:
			if state.has(key):combat_stats.player[key]=int(state[key])
	var progression:Variant=business_snapshots.get("progression",{})
	if progression is Dictionary:
		combat_stats.player["level"]=int(progression.get("level",1));combat_stats.player["exp"]=int(progression.get("experience",0))
	gameplay.projection.apply()
	awaiting_respawn=not combat_stats.player_alive()
	if alive and awaiting_respawn:_network_actions.append({"type":"player_died"})
	if not alive and not awaiting_respawn:_network_actions.append({"type":"player_revived"})

func _equipment_rows()->Array:
	return gameplay.projection.equipment()

func _refresh_runtime_snapshots()->void:
	_snapshot_inflight=true;var scope:=context();var revision:=_connection_revision
	for name:String in ["combat-state","inventory","attributes","progression","entities","skills","statuses","areas","party","alliance","rewards","resurrection"]:
		var response:Dictionary=await _read_rewards() if name=="rewards" else await request_api("/v1/gameplay/"+name)
		if scope!=context():_finish_runtime_snapshot(revision);return
		if response.ok:business_snapshots[name]=response.body.get("data",{})
	var sky:Dictionary=await request_api("/v1/environment")
	if scope!=context():_finish_runtime_snapshot(revision);return
	if sky.ok:business_snapshots.environment=sky.body
	var interactions:Dictionary=await _read_interactions()
	if scope!=context():_finish_runtime_snapshot(revision);return
	if interactions.ok:business_snapshots.interactions=interactions.data;_snapshot_revision+=1
	var projected:Dictionary=await gameplay.projection.hydrate()
	if scope!=context():_finish_runtime_snapshot(revision);return
	if not projected.ok:_finish_runtime_snapshot(revision);return
	_project_snapshots()
	_network_actions.append_array(gameplay.projection.actions())
	_finish_runtime_snapshot(revision)

func _finish_runtime_snapshot(revision:int)->void:
	if revision==_connection_revision:_snapshot_inflight=false

func restore_map_interactions(map_root:Node)->void:
	if int(map_root.get_meta("remote_interaction_revision",-1))==_snapshot_revision:return
	map_root.set_meta("remote_interaction_revision",_snapshot_revision)
	for row:Dictionary in business_snapshots.get("interactions",{}).get("objects",[]):
		if row.get("kind")!="fixture" or row.get("state") not in ["open","closed"]:continue
		preload("res://scripts/world3d/building_fixtures.gd").set_runtime(map_root,str(row.get("owner_id","")),str(row.get("fixture_id","")),1. if row.state=="open" else 0.,0.)

func interact_nearest(feet:Vector3)->void:
	var page:Dictionary=business_snapshots.get("interactions",{});var selected:Dictionary={};var distance:=INF
	var creature:=""
	for id:String in gameplay.projection.entities:
		var row:Dictionary=gameplay.projection.entities[id]
		if not row.get("interactable",false) or row.get("state",{}).get("dead",false):continue
		var p:Dictionary=row.get("position_m",{})
		var d:=feet.distance_to(Vector3(p.get("x",0.),p.get("y",0.),p.get("z",0.)))
		if d<=3. and d<distance:creature=id;distance=d
	for row:Dictionary in page.get("objects",[]):
		var point:Variant=row.get("position",[])
		if not point is Array or point.size()!=3 or row.get("actions",[]).is_empty() and not row.get("access") is Dictionary:continue
		var d:=feet.distance_to(Vector3(point[0],point[1],point[2]))
		if d<=float(row.get("radius_m",0.)) and d<distance:selected=row;distance=d;creature=""
	if not creature.is_empty():gameplay.dispatch("interact",[creature]);return
	if selected.is_empty():return
	_network_actions.append_array(gameplay.environment.menu(selected,feet))

func snapshot_world3d_sky(_map_id:String)->Dictionary:return business_snapshots.get("environment",{}).duplicate(true)

func resolve_map(map_ref:String)->String:
	var Paths=preload("res://scripts/world3d/map_paths.gd")
	var mappings:Variant=ProjectSettings.get_setting("rmmo/network/map_paths",{})
	if mappings is Dictionary and mappings.has(map_ref):
		var path:=str(mappings[map_ref])
		if not path.is_absolute_path():path=Paths.external_root().path_join(path)
		return path if Paths.allowed(path) and FileAccess.file_exists(path) else ""
	var catalog=preload("res://scripts/world_editor/resource_pack_catalog.gd").new()
	var matches:Array=[]
	for pack:Dictionary in catalog.packs():
		for map:Dictionary in catalog.maps_in(pack):
			if str(pack.id)+"/"+str(map.name)==map_ref:matches.append(map.path)
	return str(matches[0]) if matches.size()==1 else ""

func prepare_authoritative_map()->Dictionary:
	if self_actor.is_empty() or world_session.is_empty():return {"ok":false,"error":"服务器未返回完整世界快照"}
	_map_path=resolve_map(world_session.map_ref)
	if _map_path.is_empty():return {"ok":false,"error":"找不到服务器地图 %s，请配置 rmmo/network/map_paths"%world_session.map_ref}
	var session:=get_node_or_null("/root/GameSession")
	if session!=null:
		var p:Dictionary=self_actor.location.get("position_m",{})
		session.world3d_requested=true;session.world3d_map_path=_map_path
		session.world3d_spawn=Vector3(p.get("x",0.),p.get("y",0.),p.get("z",0.))+Vector3.UP*.9
	return {"ok":true}

func confirm_world_ready(map_ref:String)->Dictionary:
	var scope:=context()
	if scope.is_empty() or map_ref!=scope.map_ref:return {"ok":false,"error":"wrong_loaded_map"}
	var result:Dictionary=await rpc_call("world_ready",{"ready_token":world_session.ready_token})
	if result.get("ok",false) and context()==scope and world_session.get("ready",false):_local_loaded_context=scope;return result
	return {"ok":false,"error":_message(result)}

func queue_movement(direction:Vector3,run:bool,jump:bool=false,fly:bool=false)->Dictionary:
	if not is_world_ready():return {"ok":false,"reason":"world_not_ready"}
	if not direction.is_finite():return {"ok":false,"reason":"invalid_direction"}
	_movement={"direction":{"x":direction.x,"y":direction.y,"z":direction.z},"run":run,"jump":jump or _movement.get("jump",false),"fly":fly}
	return {"ok":true,"queued":true}

func _send_movement()->void:
	var request:=_movement.duplicate(true);_movement.jump=false
	_movement_sequence+=1;request.sequence=_movement_sequence;_move_inflight=true
	var result:Dictionary=await rpc_call("try_move",request)
	_move_inflight=false
	if result.get("resync",false):_movement.clear()
	if not result.get("ok",false) and not result.get("resync",false):_network_actions.append({"type":"system_message","text":_message(result)})

func try_move_world(sequence:int,direction:Vector3,speed_mps:float,jump:bool=false)->Dictionary:
	return world3d_authority.move_intent(sequence,direction,speed_mps,jump)

func find_path(goal:Vector3)->Dictionary:
	if not is_world_ready():return {"ok":false,"error":"world_not_ready"}
	return await rpc_call("find_path",{"goal":{"x":goal.x,"y":goal.y,"z":goal.z}})

func leave_world()->Dictionary:
	_movement.clear()
	if world_session.is_empty():return {"ok":true}
	var result:Dictionary=await rpc_call("leave_world")
	if result.get("ok",false):
		world_session.clear();self_actor.clear();actors.clear();_peer_visibility.clear();_local_loaded_context.clear();_session_character_id="";return result
	# Leave may have committed before a later cleanup error. Query, never replay.
	var recovery:Dictionary=await request_api("/v1/world/session")
	if recovery.get("status",0)==403:world_session.clear();self_actor.clear();actors.clear();return {"ok":true,"cleanup_pending":true}
	if recovery.get("status",0)==200 and recovery.get("body",{}).get("ok",false):
		var body:Dictionary=recovery.body
		_receive_world_snapshot(body)
	return result

func request_api(path:String,method:int=HTTPClient.METHOD_GET,body:Dictionary={})->Dictionary:
	if not is_logged_in():return {"ok":false,"error":"login_required"}
	if not path.begins_with("/v1/") or path.contains("://") or path.contains("\r") or path.contains("\n") or path.begins_with("//"):return {"ok":false,"error":"invalid_api_path"}
	var scope:=context();var revision:=_connection_revision
	var headers:=PackedStringArray(["Authorization: Bearer "+_token,"Content-Type: application/json","Accept: application/json"])
	if method not in [HTTPClient.METHOD_GET,HTTPClient.METHOD_HEAD]:
		if not is_world_ready():return {"ok":false,"error":"world_not_ready"}
		headers.append_array(PackedStringArray(["X-RMMO-Boot-ID: "+scope.boot_id,"X-RMMO-Session-Epoch: "+str(scope.session_epoch),"X-RMMO-Map-Generation: "+str(scope.map_generation),"X-RMMO-Map-Ref: "+scope.map_ref]))
	if _http_requests.size()>=32:return {"ok":false,"error":"http_request_limit"}
	var request:=HTTPRequest.new();request.timeout=_timeout();request.body_size_limit=8*1048576;request.max_redirects=0;add_child(request)
	var ticket:=Ticket.new();_http_requests[request]=ticket
	request.request_completed.connect(func(result:int,status:int,response_headers:PackedStringArray,bytes:PackedByteArray):ticket.resolve({"response":[result,status,response_headers,bytes]}),CONNECT_ONE_SHOT)
	var err:=request.request(_endpoint.http+path,headers,method,"" if method==HTTPClient.METHOD_GET else JSON.stringify(body,"",true,true))
	if err!=OK:_http_requests.erase(request);request.queue_free();return {"ok":false,"error":"http_request_failed"}
	var completion:Dictionary=ticket.result if ticket.done else await ticket.finished
	if not completion.has("response"):return completion
	var response:Array=completion.response
	_http_requests.erase(request);request.queue_free()
	if revision!=_connection_revision or scope!=context() and path!="/v1/world/session":return {"ok":false,"error":"stale_world_response"}
	var parsed:Variant=JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:return {"ok":false,"status":int(response[1]),"error":"invalid_json_response"}
	var ok:bool=response[0]==HTTPRequest.RESULT_SUCCESS and response[1]>=200 and response[1]<300 and parsed.get("ok",true)
	if response[1]==401:disconnect_server("登录已失效，请重新登录")
	if response[1]==409 and method!=HTTPClient.METHOD_GET:
		var loaded:=_local_loaded_context==scope
		_movement.clear();_local_loaded_context.clear()
		# A business rejection need not invalidate admission. Read the actual
		# session before deciding; never replay the rejected operation.
		var recovery:Dictionary=await request_api("/v1/world/session")
		if recovery.ok:
			var snapshot:Dictionary=recovery.body
			_receive_world_snapshot(snapshot)
			if loaded and scope==context() and world_session.get("ready",false):_local_loaded_context=scope
	return {"ok":ok,"status":int(response[1]),"body":parsed,"error":str(parsed.get("error",""))}

func poll_combat_tick()->Array:
	var actions:=_network_actions;_network_actions=[];return actions
func snapshot_remote_players()->Array:
	var result:Array=[]
	for id:String in actors:
		if id!=_session_character_id:result.append(_peer_row(actors[id]))
	return result
func player_move_speed_mul()->float:return 1.
func player_is_mounted()->bool:return false
func player_in_safe_zone()->bool:return false
func load_world_pack(_pack:String,_map:String="",_cell:Vector2i=Vector2i(-1,-1))->bool:return false
func register_npc(_id:String,_x:int,_y:int,_hostile:bool=false,_aggressive:bool=false,_facing:int=2,_wander:int=0,_group:int=0,_spawn:Dictionary={},_home:Vector2i=Vector2i(-9999,-9999))->void:pass
func set_player_cell(_x:int,_y:int)->void:pass
func mount_world3d_sky(_map:String,_path:String)->void:pass
func register_loaded_world3d_environment(_path:String,_extras:Dictionary)->void:pass
func world3d_mount_actors(_table)->void:pass
func world3d_release_actors()->void:pass
func collect_autorun()->Array:return []
func _remote_notice(operation:String)->void:_network_actions.append_array(_unsupported(operation).actions)
func _message(result:Dictionary)->String:return str(result.get("error",result.get("message","请求失败")))
