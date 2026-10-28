extends SceneTree
const Real=preload("res://scripts/net/real_server.gd")
const NS="11111111-1111-4111-8111-111111111111:92205a4714219670:"
const DUMMY=NS+"00000000-0000-4000-8000-000000000f12"
const STRIKE=NS+"935ae5bb-e846-44ca-9f8a-90f9aa2f5161"
class Metered extends Real:
	var http:Dictionary={}
	var frames:=0
	var events:=0
	var bytes:=0
	var commands:Dictionary={}
	var battle_started:=0
	var first_event_after_ms:=-1
	func request_api(path:String,method:int=HTTPClient.METHOD_GET,body:Dictionary={})->Dictionary:
		var key:=path.get_slice("?",0);http[key]=int(http.get(key,0))+1
		return await super.request_api(path,method,body)
	func _receive(data:Dictionary)->void:
		if data.has("runtime_snapshot_json"):frames+=1;bytes+=str(data.runtime_snapshot_json).to_utf8_buffer().size()
		if data.has("combat_events_json"):
			events+=1;bytes+=str(data.combat_events_json).to_utf8_buffer().size()
			if battle_started>0 and first_event_after_ms<0:first_event_after_ms=Time.get_ticks_msec()-battle_started
		super._receive(data)
	func gameplay_command(kind:String,body:Dictionary)->Dictionary:
		commands[kind]=int(commands.get(kind,0))+1
		return await super.gameplay_command(kind,body)
var server:Metered
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func pause(seconds:float)->void:await create_timer(seconds).timeout
func finish(request:Dictionary)->Dictionary:
	if not request.get("deferred",false):return request
	while true:
		var reply:Array=await server.response_ready
		if int(reply[0])==int(request.request_id):return reply[1]
	return {}
func run()->void:
	create_timer(45).timeout.connect(func():print("FAIL stream watchdog");quit(2))
	var address:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-server="):address=arg.trim_prefix("--test-server=")
		if arg.begins_with("--test-content-root="):ProjectSettings.set_setting("rmmo/content_root",arg.trim_prefix("--test-content-root="))
	server=Metered.new();root.add_child(server)
	server.register_account("stream_"+str(Time.get_ticks_usec()),"integration-password",address)
	var auth:Array=await server.login_finished
	check(auth[0],"stream real account");if not auth[0]:quit(1);return
	server.create_character("流式联调","adventurer","1","male")
	var created:Array=await server.character_created
	check(created[0],"stream real character");if not created[0]:quit(1);return
	root.get_node("GameSession").selected_character=created[2]
	server.enter_world3d(int(created[2].id));var entered:Array=await server.enter_world_ready
	check(entered[0],"pre-Ready snapshot through negotiated WebSocket");if not entered[0]:print(entered);quit(1);return
	check(server.world_session.get("gameplay_protocol",0)==1 and server.runtime_stream.active,"gameplay stream capability negotiated")
	await pause(.6)
	check((await server.confirm_world_ready(server.world_session.map_ref)).ok,"Ready after several stream scheduler ticks")
	await pause(.4)
	server.http.clear();server.commands.clear();server.frames=0;server.events=0;server.bytes=0
	var started:=Time.get_ticks_msec();server.battle_started=started
	var cast:Dictionary=await finish(server.request_cast(STRIKE,DUMMY))
	check(cast.ok,"cast uses WebSocket gameplay command")
	await pause(1.2)
	var attack:Dictionary=await finish(server.try_attack(DUMMY,0,0))
	check(attack.ok,"attack uses WebSocket gameplay command")
	await pause(.6)
	check(server.frames>0 and server.events>0 and server.gameplay._event_cursor>0,"resource changes and durable combat events pushed after Ready")
	check(server.gameplay._event_cursor==server.gameplay._event_acked,"stream ACK persists delivered events")
	check(server.commands.get("cast",0)==1 and server.commands.get("attack",0)==1 and server.commands.get("ack_events",0)>0,"combat operations and event ACK all use stream")
	var forbidden:Array=[]
	for path:String in server.http:
		if path!="/v1/environment" and not path.begins_with("/v1/gameplay/definition"):forbidden.append(path)
	check(forbidden.is_empty(),"normal combat performs zero HTTP state/event/mutation requests: "+str(forbidden))
	print("STREAM_SAMPLE elapsed_ms=",Time.get_ticks_msec()-started," resource_frames=",server.frames," event_frames=",server.events," json_payload_bytes=",server.bytes," first_combat_event_after_ms=",server.first_event_after_ms," http=",server.http," commands=",server.commands)
	var applied:int=server.gameplay._event_cursor
	var recovered:Dictionary=await server.reconnect()
	check(recovered.ok,"stream reconnect restores baseline")
	if recovered.ok:
		check((await server.confirm_world_ready(server.world_session.map_ref)).ok,"stream reconnect Ready barrier")
		await pause(.5)
		check(server.gameplay._event_cursor>=applied and server.gameplay._event_acked>=applied,"reconnect preserves applied cursor and acknowledges without replay")
		check(server.runtime_stream.active,"runtime subscription resumes after reconnect")
	server.disconnect_server();server.queue_free()
	print("REAL_RUNTIME_STREAM_TESTS failures=",failures);quit(0 if failures==0 else 1)
