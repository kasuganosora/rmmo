extends SceneTree
## Two actual adapters, actual WebSockets/HTTP, and authoritative Go movement.
const Real=preload("res://scripts/net/real_server.gd")
var failures:=0

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func _initialize()->void:run.call_deferred()

func wait_until(predicate:Callable,seconds:float=3.)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return bool(predicate.call())

func admit(server:Node,address:String,label:String)->bool:
	server.register_account("visibility_"+label+str(Time.get_ticks_usec()),"integration-password",address)
	var auth:Array=await server.login_finished
	if not auth[0]:check(false,label+" authentication");return false
	server.create_character(label,"adventurer","1","male")
	var created:Array=await server.character_created
	if not created[0]:check(false,label+" character");return false
	root.get_node("GameSession").selected_character=created[2]
	server.enter_world3d(int(created[2].id))
	var admitted:Array=await server.enter_world_ready
	if not admitted[0]:
		check(false,label+" admission: "+str(admitted[1]))
		for entity:Dictionary in server.business_snapshots.get("entities",[]):
			var reply:Dictionary=await server.request_api("/v1/gameplay/definition?kind="+str(entity.get("kind","")).uri_encode()+"&uuid="+str(entity.get("definition","")).uri_encode())
			print("definition diagnostic ",entity.get("kind","")," ",reply.get("status",0)," ",reply.get("error",""))
		return false
	var ready:Dictionary=await server.confirm_world_ready(server.world_session.map_ref)
	check(ready.get("ok",false) and server.world_session.get("visibility_protocol",0)==1,label+" negotiated AOI and Ready")
	return ready.get("ok",false)

func move_x(server:Node,target:float)->void:
	var initial:float=server.self_actor.location.position_m.get("x",0.)
	var direction:=1. if target>initial else -1.
	server.queue_movement(Vector3(direction,0,0),true)
	var reached:=await wait_until(func():return direction*(float(server.self_actor.location.position_m.get("x",0.))-target)>=0,8.)
	server.queue_movement(Vector3.ZERO,false)
	var until:=Time.get_ticks_msec()+200
	while Time.get_ticks_msec()<until:await process_frame
	check(reached,"authoritative movement reached boundary position")
	if not reached:print("movement diagnostic target=",target," actor=",server.self_actor.get("location",{}))

func run()->void:
	create_timer(65).timeout.connect(func():print("FAIL visibility watchdog timeout");quit(2))
	var address:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-server="):address=arg.trim_prefix("--test-server=")
		if arg.begins_with("--test-content-root="):ProjectSettings.set_setting("rmmo/content_root",arg.trim_prefix("--test-content-root="))
	var own:=Real.new();var peer:=Real.new();root.add_child(own);root.add_child(peer)
	own.connection_lost.connect(func(reason:String):print("observer connection closed: ",reason))
	peer.connection_lost.connect(func(reason:String):print("peer connection closed: ",reason))
	if await admit(own,address,"observer") and await admit(peer,address,"peer"):
		var peer_id:=str(peer._selected_id);var own_id:=str(own._selected_id)
		check(await wait_until(func():return own.actors.has(peer_id) and peer.actors.has(own_id)),"both clients see nearby admission")
		var generation:int=peer.self_actor.generation
		# Admission places overlapping bodies on a free side of the spawn.
		# Walk away on that side so the observer's authoritative capsule does
		# not block this visibility test before it crosses the AOI boundary.
		var origin:float=own.self_actor.location.position_m.get("x",0.)
		var side:float=1. if float(peer.self_actor.location.position_m.get("x",0.))>=origin else -1.
		var saved:Dictionary=(await own.request_api("/v1/world/session")).body.duplicate(true)
		await move_x(peer,origin+side*13.)
		check(await wait_until(func():return not own.actors.has(peer_id) and not peer.actors.has(own_id)),"both clients hide beyond outer distance")
		check(not own._retired_actors.has(peer_id),"distance hiding does not retire the live generation")
		own._receive_world_snapshot(saved)
		check(not own.actors.has(peer_id) and own.is_world_ready(),"late real HTTP snapshot cannot resurrect a hidden peer or revoke Ready")
		await move_x(peer,origin+side*9.)
		check(not own.actors.has(peer_id),"hidden peer stays hidden inside hysteresis band")
		await move_x(peer,origin+side*7.)
		check(await wait_until(func():return own.actors.has(peer_id) and peer.actors.has(own_id)),"same live generation reenters on both clients")
		check(int(own.actors.get(peer_id,{}).get("generation",0))==generation,"reentry preserves actor generation")
		# Drop one delta in the local projection, then let a real server delta
		# trigger the adapter's scoped RPC recovery (no fabricated server state).
		own._peer_visibility.revision=maxi(1,own._peer_visibility.revision-1)
		peer.queue_movement(Vector3.RIGHT,true)
		var before:int=own._peer_visibility.revision
		check(await wait_until(func():return own._peer_visibility.revision>before+1 and not own._visibility_recovering),"revision gap recovers through real snapshot RPC")
		peer.queue_movement(Vector3.ZERO,false)
		var previous_epoch:int=own.world_session.session_epoch
		own.disconnect_server()
		var restored:Dictionary=await own.reconnect()
		check(restored.get("ok",false) and own.world_session.session_epoch>previous_epoch and own.actors.has(peer_id),"reconnect rebuilds nearby projection in a fresh epoch")
		check((await own.confirm_world_ready(own.world_session.map_ref)).get("ok",false),"reconnect requires fresh Ready confirmation")
		check(await wait_until(func():return peer.actors.has(own_id)),"neighbor sees the reconnected observer")
		check((await peer.leave_world()).get("ok",false),"explicit world departure succeeds")
		check(await wait_until(func():return not own.actors.has(peer_id)),"permanent departure removes visible projection")
		peer.enter_world3d(int(peer_id))
		var again:Array=await peer.enter_world_ready
		check(again[0] and await wait_until(func():return own.actors.has(peer_id)),"departed character can enter again with a new body")
		check(int(own.actors.get(peer_id,{}).get("generation",0))>generation,"permanent reentry has a fresh generation")
	own.disconnect_server();peer.disconnect_server();own.queue_free();peer.queue_free()
	print("REAL_VISIBILITY_TESTS failures=",failures);quit(0 if failures==0 else 1)
