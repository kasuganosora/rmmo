extends SceneTree
## Two real clients, temporary content, no forged combat/progression snapshots.
const Real=preload("res://scripts/net/real_server.gd")
const NS="11111111-1111-4111-8111-111111111111:92205a4714219670:"
const NPC=NS+"00000000-0000-4000-8000-000000000008"
const QUEST=NS+"00000000-0000-4000-8000-000000000f01"
const HEAL=NS+"00000000-0000-4000-8000-00000000f101"
const DEPENDENT=NS+"00000000-0000-4000-8000-00000000f102"
const PASSIVE=NS+"00000000-0000-4000-8000-00000000f103"
const BUFF=NS+"00000000-0000-4000-8000-00000000f104"
const BURST=NS+"00000000-0000-4000-8000-00000000f105"
const REVIVE=NS+"00000000-0000-4000-8000-00000000f106"
const HURT=NS+"00000000-0000-4000-8000-00000000f121"
const KILLER=NS+"00000000-0000-4000-8000-00000000f122"
var failures:=0
class RecordedClient extends Real:
	var http_mutations:Array=[]
	var commands:Array=[]
	func request_api(path:String,method:int=HTTPClient.METHOD_GET,body:Dictionary={})->Dictionary:
		if method==HTTPClient.METHOD_POST:http_mutations.append({"path":path,"body":body.duplicate(true)})
		return await super.request_api(path,method,body)
	func gameplay_command(kind:String,body:Dictionary)->Dictionary:
		commands.append({"kind":kind,"body":body.duplicate(true)})
		return await super.gameplay_command(kind,body)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func wait_until(predicate:Callable,seconds:float=3.)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return bool(predicate.call())
func pause(seconds:float)->void:await create_timer(seconds).timeout
func finish(client:Node,request:Dictionary,label:String,expected:bool=true)->Dictionary:
	var result:=request
	if request.get("deferred",false):
		while true:
			var reply:Array=await client.response_ready
			if int(reply[0])==int(request.request_id):result=reply[1];break
	check(bool(result.get("ok",false))==expected,label)
	if bool(result.get("ok",false))!=expected:print("diagnostic ",result)
	return result
func admit(client:Node,address:String,label:String)->bool:
	client.register_account("skills_"+label+str(Time.get_ticks_usec()),"integration-password",address)
	var auth:Array=await client.login_finished
	if not auth[0]:check(false,label+" authentication");return false
	client.create_character(label,"adventurer","1","male")
	var created:Array=await client.character_created
	if not created[0]:check(false,label+" creation");return false
	root.get_node("GameSession").selected_character=created[2]
	client.enter_world3d(int(created[2].id))
	var admitted:Array=await client.enter_world_ready
	if not admitted[0]:check(false,label+" admission "+str(admitted));return false
	var ready:Dictionary=await client.confirm_world_ready(client.world_session.map_ref)
	check(ready.get("ok",false) and client.world_session.get("gameplay_protocol",0)==1,label+" real runtime/WS Ready")
	return ready.get("ok",false)
func training(client:Node)->Dictionary:return client.snapshot_skill_training()
func hp(client:Node)->int:return int(client.combat_stats.player.get("hp",0))
func move_axis(client:Node,axis:String,target:float)->bool:
	var start:float=client.self_actor.location.position_m.get(axis,0.)
	var sign_value:=1. if target>start else -1.
	var direction:=Vector3(sign_value,0,0) if axis=="x" else Vector3(0,0,sign_value)
	client.queue_movement(direction,true)
	var reached:=await wait_until(func():return not client.combat_stats.player_alive() or sign_value*(float(client.self_actor.location.position_m.get(axis,0.))-target)>=0.,5.)
	client.queue_movement(Vector3.ZERO,false)
	await pause(.15)
	return reached
func run()->void:
	create_timer(90).timeout.connect(func():print("FAIL skill system watchdog timeout");quit(2))
	var address:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-server="):address=arg.trim_prefix("--test-server=")
		if arg.begins_with("--test-content-root="):ProjectSettings.set_setting("rmmo/content_root",arg.trim_prefix("--test-content-root="))
	var own:=RecordedClient.new();var peer:=RecordedClient.new();root.add_child(own);root.add_child(peer)
	if await admit(own,address,"healer") and await admit(peer,address,"ally"):
		await exercise(own,peer)
	own.disconnect_server();peer.disconnect_server();own.queue_free();peer.queue_free()
	print("REAL_SKILL_SYSTEM_TESTS failures=",failures);quit(0 if failures==0 else 1)
func exercise(own:Node,peer:Node)->void:
	var peer_id:=str(peer._selected_id)
	check(await wait_until(func():return own.actors.has(peer_id)),"real peer is visible and targetable")
	check(not own.gameplay.projection.target(peer_id).is_empty(),"player target carries real map and generation")
	var initial:Dictionary=training(own)
	check(initial.get("enabled",false) and initial.get("entries",[]).size()==3,"training policy reaches existing skills runtime resource")
	check(own._runtime_snapshot.versions.size()==13,"runtime retains 13 versioned resources")
	await finish(own,own.try_interact(NPC,0,0),"open real NPC quest menu")
	await finish(own,own.try_accept_quest(QUEST),"accept funding quest")
	await finish(own,own.try_interact(NPC,0,0),"complete talk objective")
	await finish(own,own.try_turn_in_quest(QUEST),"claim actual training gold and experience")
	var funded:=int(training(own).get("gold",0))
	check(funded==int(initial.get("gold",0))+100,"authoritative gold funds training")
	await finish(own,own.try_learn_skill(DEPENDENT),"rank prerequisite rejects early unlock",false)
	check(int(training(own).get("gold",0))==funded,"rejected learning has no cost")
	await finish(own,own.try_learn_skill(HEAL),"learn rank one")
	check(own.gameplay.projection.training_entry(HEAL).get("rank",0)==1 and own.snapshot_skill_book().known.has(HEAL),"learned active skill reaches usable book")
	var prior_definition:Dictionary=await own.gameplay.projection.definition("skills",HEAL)
	await finish(own,own.try_learn_skill(HEAL),"upgrade learned skill")
	var ranked:Dictionary=await own.gameplay.projection.definition("skills",HEAL)
	check(own.gameplay.projection.training_entry(HEAL).get("rank",0)==2 and JSON.stringify(ranked)!=JSON.stringify(prior_definition),"rank changes invalidate effective definition cache")
	var learning_body:Dictionary=own.http_mutations[-1].body.duplicate(true)
	var after_learning:=int(training(own).gold)
	var replay:Dictionary=await own.request_api("/v1/gameplay/skill-training",HTTPClient.METHOD_POST,learning_body)
	check(replay.ok and int(replay.body.data.gold)==after_learning,"identical learning sequence replay never charges twice")
	await finish(own,own.try_learn_skill(DEPENDENT),"rank two unlocks dependent skill")
	await finish(own,own.try_learn_skill(PASSIVE),"learn passive rule")
	check(own.gameplay.projection.training_entry(PASSIVE).get("rank",0)==1 and not own.gameplay.projection.training_entry(PASSIVE).get("granted",true),"passive rank is displayed without active cast authorization")
	await finish(own,own.request_cast(PASSIVE),"learned passive cannot be manually cast",false)
	var stats:Dictionary=own.business_snapshots.inventory.stats
	check(stats.get("rules_version",0)>=1 and own.combat_stats.player.get("authoritative",false),"shared effective attributes replace client defaults")
	check(not own.combat_stats.player.has("m_atk") and not own.combat_stats.player.has("cp"),"real projection contains no mock magic attack or CP")
	if int(own.combat_stats.player.get("attr_points",0))>0:
		var free_before:=int(own.combat_stats.player.attr_points)
		await finish(own,own.try_allocate_attr("str",1),"allocate actual earned attribute point")
		var before_reset:=int(training(own).gold)
		await finish(own,own.try_attr_respec(),"reset attributes using server policy")
		check(int(training(own).gold)==before_reset-3 and int(own.combat_stats.player.attr_points)==free_before,"attribute reset uses configured gold and restores points")
	else:check(false,"synthetic quest grants attribute point for reset acceptance")
	var baseline_attack:=int(own.combat_stats.player.atk)
	await finish(own,own.request_cast(BUFF),"cast composite buff through WebSocket")
	var active:Dictionary=own.gameplay.projection.statuses_snapshot()
	check(active.get("active",[]).size()==1 and int(own.combat_stats.player.atk)>baseline_attack,"buff modifiers change authoritative effective attributes")
	check(is_equal_approx(own.player_move_speed_mul(),1.2),"movement multiplier comes from actual authoritative status control")
	if not active.get("active",[]).is_empty():
		var status_id:=str(active.active[0].status_id)
		var cancel_body:={"status_id":status_id,"expected_sequence":int(active.sequence)}
		check(status_id in own.business_snapshots.statuses.get("cancelable",[]),"server explicitly exposes cancelable buff")
		await finish(own,own.try_cancel_status(status_id),"cancel buff through real WebSocket")
		check(own.gameplay.projection.statuses_snapshot().get("active",[]).is_empty() and int(own.combat_stats.player.atk)==baseline_attack,"cancellation restores base attributes without local synthesis")
		check(is_equal_approx(own.player_move_speed_mul(),1.),"cancelled haste restores authoritative movement multiplier")
		replay=await own.gameplay_command("cancel_status",cancel_body)
		check(replay.ok,"same cancel receipt replays without applying another removal")
	var created_party:Dictionary=await own.request_api("/v1/gameplay/party/create",HTTPClient.METHOD_POST,{})
	check(created_party.ok,"create real party for friendly targets")
	var invited:Dictionary=await own.request_api("/v1/gameplay/party/invite",HTTPClient.METHOD_POST,{"target":peer_id})
	check(invited.ok,"invite real ally")
	var party:Dictionary=await peer.request_api("/v1/gameplay/party")
	var invites:Array=party.get("body",{}).get("data",{}).get("invitations",[])
	if invites.is_empty():check(false,"party invitation received");return
	check((await peer.request_api("/v1/gameplay/party/accept",HTTPClient.METHOD_POST,{"invitation":invites[0].id})).ok,"accept real party invitation")
	# Creature targeting is scoped to its live simulation chunk. Enter the
	# same negative-X chunk through real movement before attacking fixtures.
	check(await move_axis(own,"x",-1.),"healer enters creature simulation chunk")
	await move_axis(peer,"z",6.)
	peer.queue_movement(Vector3.LEFT,true)
	check(await wait_until(func():return hp(peer)<int(peer.combat_stats.player.hp_max),5.),"actual monster damages ally")
	peer.queue_movement(Vector3.ZERO,false)
	await finish(own,own.request_cast(BURST,HURT),"stop damage source using actual combat")
	await pause(.2)
	var injured_hp:=hp(peer)
	await finish(own,own.request_cast(HEAL,peer_id),"learned party skill heals another real player")
	check(await wait_until(func():return hp(peer)>injured_hp),"friendly healing changes remote authoritative HP")
	peer.queue_movement(Vector3.LEFT,true)
	check(await wait_until(func():return not peer.combat_stats.player_alive(),5.),"actual second monster causes ally death")
	peer.queue_movement(Vector3.ZERO,false)
	await finish(own,own.request_cast(BURST,KILLER),"remove killer before resurrection")
	var dead_target:Dictionary=own.gameplay.projection.target(peer_id)
	await finish(own,own.request_cast(REVIVE,peer_id),"resurrection targets actual dead player generation")
	check(await wait_until(func():return not peer.business_snapshots.resurrection.get("offer",{}).is_empty()),"resurrection offer arrives through runtime")
	var offer:Dictionary=peer.business_snapshots.resurrection.get("offer",{})
	if not offer.is_empty():
		var resolve_seq:=int(peer.business_snapshots.resurrection.get("resolve_sequence",0))+1
		await finish(peer,peer.try_resurrection_respond(str(offer.offer_id),true),"ally accepts resurrection through real adapter")
		check(peer.combat_stats.player_alive() and not peer.is_world_ready(),"revival restores HP and requires fresh generation Ready")
		check((await peer.confirm_world_ready(peer.world_session.map_ref)).ok,"revived client confirms fresh Ready")
		check(await wait_until(func():return own.gameplay.projection.target(peer_id)!=dead_target),"observer replaces dead target generation after revival")
		replay=await peer.request_api("/v1/gameplay/resurrection/resolve",HTTPClient.METHOD_POST,{"offer_id":offer.offer_id,"accept":true,"sequence":resolve_seq})
		check(replay.ok,"resurrection accept replays once without a second revival")
	var before_respec:=int(training(own).gold)
	await finish(own,own.try_skill_respec(),"reset learned ranks through policy")
	check(int(training(own).gold)==before_respec-7 and not own.snapshot_skill_book().known.has(HEAL) and own.snapshot_skill_book().known.has(BUFF),"respec refunds learned ranks and retains starter grants at configured cost")
	var saved_gold:=int(training(own).gold)
	own.disconnect_server()
	var restored:Dictionary=await own.reconnect()
	check(restored.ok,"real reconnect after training and status changes")
	if restored.ok:
		check((await own.confirm_world_ready(own.world_session.map_ref)).ok,"reconnect confirms Ready")
		check(int(training(own).gold)==saved_gold and own.gameplay.projection.training_entry(HEAL).get("rank",-1)==0 and own.gameplay.projection.statuses_snapshot().get("active",[]).is_empty(),"durable training reset and buff cancellation recover after reconnect")
	var forbidden:=false
	for request:Dictionary in own.http_mutations:
		if request.path in ["/v1/gameplay/casts","/v1/gameplay/attack","/v1/gameplay/statuses"]:forbidden=true
	check(not forbidden and own.commands.size()>=7,"combat and status commands use streaming WebSocket transport")
