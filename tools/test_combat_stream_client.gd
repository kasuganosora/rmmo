extends SceneTree
## Exercises the production event-consumer state machine with controlled loss.
const Gameplay=preload("res://scripts/net/remote/gameplay.gd")
const Snapshot=preload("res://scripts/net/remote/runtime_snapshot.gd")
var failures:=0

class Ticket extends RefCounted:
	signal finished(result:Dictionary)

class EventTransport extends Node:
	signal response_ready(id:int,result:Dictionary)
	var world_session:Dictionary={"boot_id":"boot","session_epoch":1,"map_generation":1,"map_ref":"test/map","gameplay_protocol":1}
	var endpoint_address:="http://test:7777"
	var _session_user:="test-user"
	var _selected_id:=1
	var _runtime_snapshot=Snapshot.new()
	var _network_actions:Array=[]
	var commands:Array=[]
	var http_calls:Array=[]
	var entered:=true
	var fail_ack:=0
	var durable_ack:=0
	var max_cursor:=9007199254740991
	var small_queue:=false
	var held_ack:Ticket
	var disconnected:=""
	func context()->Dictionary:
		return {"boot_id":world_session.boot_id,"session_epoch":world_session.session_epoch,"map_generation":world_session.map_generation,"map_ref":world_session.map_ref}
	func is_world_ready()->bool:return entered
	func disconnect_server(message:String)->void:disconnected=message;entered=false
	func gameplay_command(kind:String,body:Dictionary)->Dictionary:
		commands.append({"kind":kind,"body":body.duplicate(true)})
		if kind=="subscribe_events":
			if small_queue:return {"ok":false,"error":"combat_stream_unavailable"}
			if int(body.after)>max_cursor:return {"ok":false,"error":"invalid_combat_cursor"}
			return {"ok":true,"body":{"data":{"subscribed":true}}}
		if kind=="ack_events":
			durable_ack=maxi(durable_ack,int(body.through))
			if held_ack!=null:return await held_ack.finished
			if fail_ack>0:fail_ack-=1;return {"ok":false,"error":"lost_ack_response"}
			return {"ok":true,"body":{"data":{"through":body.through}}}
		return {"ok":false,"error":"unexpected_command"}
	func request_api(path:String,_method:int=HTTPClient.METHOD_GET,_body:Dictionary={})->Dictionary:
		http_calls.append(path)
		return {"ok":true,"body":{"data":{"events":[],"next_cursor":durable_ack,"more":false}}}

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func event_page(cursor:int,map_ref:String="test/map")->String:
	return JSON.stringify({"events":[{"cursor":cursor,"event":{"event_id":"event-"+str(cursor),"map":map_ref}}],"next_cursor":cursor,"more":false})

func run()->void:
	var transport:=EventTransport.new();root.add_child(transport)
	var consumer:=Gameplay.new(transport)
	transport.entered=false
	await consumer.poll_events()
	check(transport.commands.is_empty(),"event subscription waits for WorldReady")
	transport.entered=true
	await consumer._poll_stream_events()
	check(consumer._event_stream_active and transport.commands.size()==1 and transport.commands[0].kind=="subscribe_events" and transport.commands[0].body.after==0,"ready client subscribes over WS")
	transport.fail_ack=1
	consumer.receive_stream_events(event_page(1))
	check(consumer._event_cursor==1 and consumer._event_acked==0 and transport._network_actions.size()==1 and transport.durable_ack==1,"applied event survives lost durable ACK response")
	consumer.receive_stream_events(event_page(1))
	check(transport._network_actions.size()==1 and consumer._event_acked==1,"duplicate pending page is not displayed twice and is ACKed again")
	check(transport.http_calls.is_empty(),"normal event delivery and ACK never poll HTTP")
	# A response may be lost immediately before a reconnect. The same identity
	# must resume its applied cursor and ACK it even if storage returns no page.
	transport.fail_ack=1
	consumer.receive_stream_events(event_page(2))
	check(consumer._event_cursor==2 and consumer._event_acked==1,"second lost ACK leaves local applied cursor ahead")
	consumer.cancel();transport.world_session.session_epoch=2
	await consumer._poll_stream_events()
	check(consumer._event_stream_active and consumer._event_cursor==2 and transport.commands.back().body.after==2,"same character reconnect resumes applied cursor")
	consumer._events_at=0
	await consumer._poll_stream_events()
	check(consumer._event_acked==2 and transport.commands.back().kind=="ack_events" and transport.commands.back().body.through==2,"empty resumed mailbox still receives the missing ACK")
	consumer.receive_stream_events(event_page(2))
	check(transport._network_actions.size()==2,"replayed reconnect event remains suppressed")
	# An ACK result from an old world must not update the new world's consumer.
	transport.held_ack=Ticket.new()
	consumer.receive_stream_events(event_page(3))
	check(consumer._event_ack_busy,"ACK can remain in flight")
	consumer.reset_event_stream();transport.world_session.session_epoch=3
	transport.held_ack.finished.emit({"ok":true});transport.held_ack=null
	check(consumer._event_acked==0 and not consumer._event_ack_busy,"late old-world ACK cannot publish into reset subscription")
	await consumer._poll_stream_events()
	check(consumer._event_cursor==3,"same character world transition retains deduplication cursor")
	consumer.receive_stream_events(event_page(4,"previous/map"))
	check(consumer._event_cursor==4 and transport._network_actions.size()==3,"old-map event advances delivery without displaying in current map")
	# Cursor reuse after a database restore requires an explicit server rejection;
	# ordinary reconnects above must retain deduplication state.
	consumer.reset_event_stream();transport.world_session.boot_id="new-boot";transport.world_session.session_epoch=4;transport.max_cursor=0
	await consumer._poll_stream_events()
	check(consumer._event_cursor==0 and consumer._event_acked==0 and not consumer._event_applied.has(consumer._event_identity),"typed invalid cursor clears only rejected identity after database restore")
	consumer._events_at=0
	await consumer._poll_stream_events()
	check(consumer._event_stream_active and transport.commands.back().body.after==0,"cursor rejection recovers with a fresh subscription")
	consumer.receive_stream_events(event_page(1))
	check(transport._network_actions.size()==4,"new restored mailbox can display reused cursor")
	consumer.cancel();transport._selected_id=2;transport.world_session.session_epoch=5
	await consumer._poll_stream_events()
	check(consumer._event_cursor==0 and transport.commands.back().body.after==0,"another character cannot inherit previous character cursor")
	# The bounded resume cache must retain recent characters and release old ones.
	var had_setting:=ProjectSettings.has_setting("rmmo/network/event_resume_cache_entries")
	var previous:Variant=ProjectSettings.get_setting("rmmo/network/event_resume_cache_entries",64)
	ProjectSettings.set_setting("rmmo/network/event_resume_cache_entries",8)
	transport.max_cursor=9007199254740991
	for index in 20:
		consumer.reset_event_stream();transport._selected_id=index+10;transport.world_session.session_epoch+=1
		await consumer._poll_stream_events();consumer._event_cursor=index+1
	consumer.reset_event_stream()
	check(consumer._event_applied.size()==8 and consumer._event_applied.has(transport.endpoint_address+"|"+transport._session_user+"|29") and not consumer._event_applied.has(transport.endpoint_address+"|"+transport._session_user+"|10"),"resume cursor cache obeys configured bound and keeps newest identities")
	if had_setting:ProjectSettings.set_setting("rmmo/network/event_resume_cache_entries",previous)
	else:ProjectSettings.clear("rmmo/network/event_resume_cache_entries")
	transport.small_queue=true;transport._selected_id=50;transport.world_session.session_epoch+=1
	await consumer._poll_stream_events()
	check(consumer._event_stream_legacy and not consumer._event_stream_active,"small socket queue explicitly switches only event delivery to compatibility")
	await consumer.poll_events()
	var http_count:int=transport.http_calls.size()
	await consumer.poll_events()
	check(http_count==1 and transport.http_calls.size()==1,"capacity fallback is rate limited and does not poll HTTP each frame")
	check(transport.disconnected.is_empty(),"valid recovery scenarios do not disconnect consumer")
	transport.free()
	print("combat stream client failures=",failures)
	quit(1 if failures else 0)
