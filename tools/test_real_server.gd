extends SceneTree
const Wire=preload("res://scripts/net/protocol/protobuf.gd")
const Real=preload("res://scripts/net/real_server.gd")
const Config=preload("res://scripts/net/connection_config.gd")
const Net=preload("res://scripts/net/net.gd")
var failures:=0
class Body extends CharacterBody3D:
	var surface_id:="ground"
	func _init()->void:
		var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";collider.shape=CapsuleShape3D.new();add_child(collider)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	create_timer(35).timeout.connect(func():print("FAIL test watchdog timeout");quit(2))
	check(Config.endpoint("127.0.0.1:7777").get("websocket")=="ws://127.0.0.1:7777/ws","plain host becomes server WebSocket URL")
	check(Config.endpoint("https://example.test:8443").get("websocket")=="wss://example.test:8443/ws","TLS remains enabled")
	for address:String in ["http://user:pass@host:7777","https://example.test/path","http://127.0.0.1:0","http://127.0.0.1:65536","http://host\r\nInjected: yes"]:check(not Config.endpoint(address).ok,"reject invalid endpoint")
	var bytes:=Wire.encode("ClientMessage",{"request_id":7,"login":{"username":"玩家","password":"test"}})
	check(bytes.ok,"encode login request")
	var decoded:=Wire.decode("ClientMessage",bytes.bytes)
	check(decoded.ok and decoded.data.login.username=="玩家" and decoded.data.request_id==7,"UTF-8 login wire roundtrip")
	var sequence:=9007199254740991
	bytes=Wire.encode("ServerMessage",{"world_session":{"session_epoch":sequence,"map_generation":sequence,"protocol_version":2},"actor_3d":{"sequence":sequence,"location":{"position_m":{"x":-123.125,"y":.4,"z":1000.75}}}})
	decoded=Wire.decode("ServerMessage",bytes.bytes)
	check(decoded.ok and decoded.data.world_session.session_epoch==sequence and decoded.data.actor_3d.sequence==sequence,"uint64 sequences retain exact integer precision")
	check(absf(decoded.data.actor_3d.location.position_m.x+123.125)<.000001,"protobuf uses double metre coordinates")
	for raw:PackedByteArray in [PackedByteArray([10,255]),PackedByteArray([0]),PackedByteArray([9,1]),PackedByteArray([8,128]),PackedByteArray([11]),PackedByteArray([8,255,255,255,255,255,255,255,255,255,255])]:check(not Wire.decode("ServerMessage",raw).ok,"malformed protobuf fails explicitly")
	var server:=Real.new();root.add_child(server)
	check(preload("res://scripts/net/net_client.gd").satisfies(server),"real adapter satisfies NetClient contract")
	check(server.inventory.snapshot().is_empty() and server._accounts.is_empty(),"real adapter has no starter rewards or demo accounts")
	var before:Dictionary=server.combat_stats.player.duplicate(true)
	check(not server.try_sit(true).ok and server.combat_stats.player==before,"unsupported operation cannot mutate local simulation")
	check(not server.queue_movement(Vector3.RIGHT,true).ok,"movement requires Ready handshake")
	world_fences(server)
	var address:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-server="):address=arg.trim_prefix("--test-server=")
		if arg.begins_with("--test-content-root="):ProjectSettings.set_setting("rmmo/content_root",arg.trim_prefix("--test-content-root="))
	if not address.is_empty():await integration(server,address)
	server.disconnect_server();server.queue_free()
	await switch_modes()
	print("REAL_SERVER_TESTS failures=",failures);quit(0 if failures==0 else 1)

func switch_modes()->void:
	var router:=root.get_node("ServerConnection")
	check(router.configure(false).ok and not Net.has_server_override(),"switch restores Mock provider")
	var mock:=Net.server()
	check(mock==root.get_node("MockServer") and mock.is_processing(),"Mock mode resumes its own simulation")
	mock.login("demo","demo","local")
	var logged:Array=await mock.login_finished
	check(logged[0],"Mock login remains functional after switching")
	check(not router.configure(true).ok,"active login prevents backend swap")
	mock.logout()
	check(router.configure(true,"http://127.0.0.1:7777").ok and Net.is_real_server(),"logout permits switching back to real mode")
	check(not mock.is_processing(),"real mode disables Mock simulation")

func integration(server:Node,address:String)->void:
	var name:="test_"+str(Time.get_ticks_usec())
	server.register_account(name,"integration-password",address)
	var auth:Array=await server.login_finished
	check(auth[0],"register over actual Go WebSocket/protobuf")
	if not auth[0]:return
	server.create_character("网络测试","adventurer","1","male")
	var created:Array=await server.character_created
	check(created[0],"create character on actual Go server")
	if not created[0]:return
	var character:Dictionary=created[2]
	root.get_node("GameSession").selected_character=character
	server.enter_world3d(int(character.id))
	var admission:Array=await server.enter_world_ready
	check(admission[0] and not server.world_session.get("ready",false),"enter returns unready server-issued world session")
	if not admission[0]:print(admission[1]);return
	check(server.business_snapshots.has("inventory") and server.business_snapshots.has("statuses") and server.business_snapshots.has("interactions"),"entry restores real business and map snapshots before Ready")
	server._selected_id=int(character.id)
	var scope:Dictionary=server.context()
	check(server.prepare_authoritative_map().ok and root.get_node("GameSession").world3d_map_path.ends_with("map.gltf"),"resolve authoritative map identity under configured local content root")
	check(not server.queue_movement(Vector3.RIGHT,true).ok,"pre-Ready movement blocked")
	var api:Dictionary=await server.request_api("/v1/world/session")
	check(api.ok and api.body.data.map_ref==scope.map_ref,"HTTP bearer authentication reaches same world session")
	var ready:Dictionary=await server.confirm_world_ready(scope.map_ref)
	check(ready.get("ok",false) and server.is_world_ready(),"matching Ready ticket unlocks movement")
	var start:float=server.self_actor.location.get("position_m",{}).get("x",0.)
	var body:=Body.new();root.add_child(body)
	server.world3d_authority.mount(body,null,scope.map_ref)
	var initial:Vector3=body.global_position
	server.try_move_world(1,Vector3.RIGHT,4.)
	check(body.global_position==initial,"queued input does not simulate local movement")
	var until:=Time.get_ticks_msec()+400
	while Time.get_ticks_msec()<until:await process_frame
	server.queue_movement(Vector3.ZERO,false)
	until=Time.get_ticks_msec()+150
	while Time.get_ticks_msec()<until:await process_frame
	check(server.self_actor.location.position_m.get("x",0.)>start+.2,"authoritative server tick moves actor")
	check(absf(body.global_position.x-float(server.self_actor.location.position_m.x))<.00001,"render body applies authoritative position snapshots")
	server.world3d_authority.release();body.queue_free()
	var path:Dictionary=await server.find_path(Vector3(start,0,4))
	check(path.get("ok",false) and not path.get("path",[]).is_empty(),"navigation path comes from Go server")
	api=await server.request_api("/v1/gameplay/inventory")
	check(api.ok,"read real inventory through authenticated HTTP")
	api=await server.request_api("/v1/gameplay/inventory",HTTPClient.METHOD_POST,{"sequence":1,"action":"sort"})
	check(api.ok,"HTTP mutation carries all world context headers")
	api=await server.request_api("/v1/gameplay/inventory",HTTPClient.METHOD_POST,{"sequence":2,"action":"unequip","slot":"weapon"})
	check(api.get("status",0)==409 and server.is_world_ready(),"business rejection recovers current session without freezing input or replaying")
	var own:Dictionary=server.self_actor.duplicate(true)
	var wrong:Dictionary=server.world_session.duplicate(true);wrong.map_ref="old/map"
	server._receive({"push":true,"ok":true,"world_session":wrong,"actor_3d":own})
	check(server.self_actor==own and server.context()==scope,"stale world push does not overwrite current session")
	var pending:Dictionary={"done":false}
	wait_for_http(server,pending)
	var old_epoch:int=server.world_session.session_epoch
	server.disconnect_server()
	await process_frame
	check(pending.done and pending.result.get("error")=="connection_closed","disconnect completes outstanding HTTP callbacks")
	check(not server.is_world_ready() and server._movement.is_empty(),"disconnect stops world input without Mock fallback")
	var restored:Dictionary=await server.reconnect()
	check(restored.get("ok",false) and server.world_session.session_epoch>old_epoch and not server.is_world_ready(),"reconnect requires a fresh server epoch and Ready ticket")
	if not restored.get("ok",false):return
	check((await server.confirm_world_ready(server.world_session.map_ref)).get("ok",false),"reconnected world confirms fresh Ready token")
	check(server._movement.is_empty(),"reconnect never replays old movement")
	var leave:Dictionary=await server.leave_world()
	check(leave.get("ok",false) and server.world_session.is_empty(),"leave releases world while account remains authenticated")
	server.logout()
	server.login(name,"integration-password",address)
	auth=await server.login_finished
	check(auth[0],"login reuses server-persisted account")
	server.fetch_characters()
	var list:Array=await server.characters_ready
	check(list.size()==1 and list[0].id==character.id,"character persists across real login")

func wait_for_http(server:Node,result:Dictionary)->void:
	result.result=await server.request_api("/v1/gameplay/inventory")
	result.done=true

func world_fences(server:Node)->void:
	var state:={"boot_id":"test","session_epoch":4,"map_generation":10,"map_ref":"test/map","ready_token":"ticket","ready":true,"movement_sequence":8,"protocol_version":2}
	server.world_session=state.duplicate(true);server._session_character_id="42"
	var actor:={"id":"42","generation":10,"sequence":8,"location":{"map_ref":"test/map","position_m":{"x":0.,"y":0.,"z":0.}}}
	server.self_actor=actor.duplicate(true)
	var ticket=Real.Ticket.new()
	server._pending[90]={"operation":"find_path","scope":server.context(),"ticket":ticket,"deadline":0}
	var transferred:Dictionary=state.duplicate(true);transferred.map_generation=11;transferred.ready=false;transferred.ready_token="new-ticket"
	var moved:Dictionary=actor.duplicate(true);moved.generation=11;moved.sequence=0
	server._receive({"push":true,"ok":true,"resync":true,"world_session":transferred,"actor_3d":moved})
	check(ticket.done and ticket.result.error=="stale_world_response","new map generation cancels old path callbacks")
	server._receive({"push":true,"ok":true,"world_session":state,"actor_3d":actor})
	check(server.world_session.map_generation==11 and server.self_actor.generation==11,"old generation cannot replace a transferred actor")
	var peer:Dictionary=moved.duplicate(true);peer.id="peer";peer.generation=20
	server._receive({"push":true,"ok":true,"world_session":transferred,"actor_3d":peer})
	server._receive({"push":true,"ok":true,"world_session":transferred,"actor_left":"peer","actor_left_generation":19})
	check(server.actors.has("peer"),"old departure cannot delete a newer actor instance")
	server._receive({"push":true,"ok":true,"world_session":transferred,"actor_left":"peer","actor_left_generation":20})
	server._receive({"push":true,"ok":true,"world_session":transferred,"actor_3d":peer})
	check(not server.actors.has("peer"),"late snapshot cannot resurrect a departed actor generation")
	server.disconnect_server()
	server._receive({"push":true,"ok":true,"world_session":transferred,"actor_3d":moved})
	check(server.world_session.is_empty(),"unsolicited old push cannot reopen an exited world")
	server._session_character_id=""
