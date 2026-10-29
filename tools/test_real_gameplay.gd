extends SceneTree
const Real=preload("res://scripts/net/real_server.gd")
const NS="11111111-1111-4111-8111-111111111111:92205a4714219670:"
const NPC=NS+"00000000-0000-4000-8000-000000000008"
const HERB=NS+"00000000-0000-4000-8000-000000000001"
const POTION=NS+"00000000-0000-4000-8000-000000000002"
const SWORD=NS+"00000000-0000-4000-8000-00000000000c"
const QUEST=NS+"00000000-0000-4000-8000-000000000f01"
const LEVEL_QUEST=NS+"00000000-0000-4000-8000-000000000f21"
const ENV_QUEST=NS+"00000000-0000-4000-8000-000000000f22"
const DUMMY=NS+"00000000-0000-4000-8000-000000000f12"
const HEAL=NS+"7de8d659-52d1-4d13-81fd-a72b5c5ad031"
const STRIKE=NS+"935ae5bb-e846-44ca-9f8a-90f9aa2f5161"
var server:Node
var failures:=0
var quest_social:=false
class DelayedGuildPeer extends Real:
	signal guild_read_held
	signal release_guild_read
	var hold_guild_read:=false
	var held_guild:Dictionary={}
	func request_api(path:String,method:int=HTTPClient.METHOD_GET,body:Dictionary={})->Dictionary:
		var result:Dictionary=await super.request_api(path,method,body)
		if hold_guild_read and path=="/v1/gameplay/guilds" and method==HTTPClient.METHOD_GET:
			hold_guild_read=false;held_guild=result.get("body",{}).get("data",{}).duplicate(true)
			guild_read_held.emit()
			await release_guild_read
		return result
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func finish(request:Dictionary,label:String,expected:bool=true,peer:Node=null)->Dictionary:
	var signal_owner:Node=server if peer==null else peer
	var result:=request
	if request.get("deferred",false):
		while true:
			var reply:Array=await signal_owner.response_ready
			if int(reply[0])==int(request.request_id):result=reply[1];break
	check(bool(result.get("ok",false))==expected,label)
	if bool(result.get("ok",false))!=expected:print(result)
	check(result.get("actions",[]).is_empty(),label+" delivers actions only through the durable event channel")
	return result
func pause(seconds:float)->void:await create_timer(seconds).timeout
func wait_for_basic_attack()->bool:
	# Fast conditional snapshots no longer hide the skill's one-second GCD
	# behind fourteen serial HTTP reads. Observe the authoritative deadline.
	var deadline:=Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline:
		var skills:Dictionary=await server.request_api("/v1/gameplay/skills")
		var state:Dictionary=await server.request_api("/v1/gameplay/combat-state")
		if not skills.ok or not state.ok:return false
		var timing:Dictionary=skills.body.data
		var game_time:=float(state.body.data.server_elapsed)*1000000.
		if timing.get("last",{}).get("status","")!="casting" and game_time>=float(timing.get("busy_until_game_us",0)) and game_time>=float(timing.get("groups_game_us",{}).get("combat",0)) and float(state.body.data.server_elapsed)>=float(state.body.data.get("ready_at_game",0)):return true
		await pause(.05)
	return false
func item_instance(definition:String)->String:
	for row:Dictionary in server.gameplay.projection.bag():
		if row.definition_id==definition:return str(row.id)
	return ""
func run()->void:
	create_timer(90).timeout.connect(func():print("FAIL gameplay watchdog timeout");quit(2))
	var address:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--test-quest-social":quest_social=true
		if arg.begins_with("--test-server="):address=arg.trim_prefix("--test-server=")
		if arg.begins_with("--test-content-root="):ProjectSettings.set_setting("rmmo/content_root",arg.trim_prefix("--test-content-root="))
	server=Real.new();root.add_child(server)
	server.register_account("gameplay_"+str(Time.get_ticks_usec()),"integration-password",address)
	var auth:Array=await server.login_finished
	check(auth[0],"real account registration");if not auth[0]:quit(1);return
	server.create_character("玩法联调","adventurer","1","male")
	var created:Array=await server.character_created
	check(created[0],"real character creation");if not created[0]:quit(1);return
	var character:Dictionary=created[2];root.get_node("GameSession").selected_character=character
	server.enter_world3d(int(character.id))
	var entered:Array=await server.enter_world_ready
	check(entered[0],"all gameplay read models hydrate before Ready")
	if not entered[0]:print(entered);quit(1);return
	check(absf(float(server.self_actor.body_height)-2.05)<.00001,"trusted avatar profile crosses protobuf")
	check(server.snapshot_skill_book().known.has(HEAL),"configured starter grants reach skill book")
	check(not server.try_inventory_sort().get("deferred",false),"business mutations blocked before Ready")
	check((await server.confirm_world_ready(server.world_session.map_ref)).ok,"Ready handshake")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",1.]),"open authoritative map fixture")
	var opened:=false
	for fixture:Dictionary in server.business_snapshots.interactions.objects:
		if fixture.get("owner_id")=="integration-building" and fixture.get("fixture_id")=="gate":opened=fixture.get("state")=="open"
	check(opened,"map fixture snapshot changes only after server commit")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",.5]),"partial fixture state rejected",false)
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",0.]),"close authoritative map fixture")
	await housing_checks(address)
	var initial_gold:int=server.inventory.get_gold()
	await finish(server.try_interact(NPC,0,0),"NPC dialogue")
	await finish(server.try_accept_quest(QUEST),"accept quest")
	check(server.snapshot_quest_journal()[0].title=="Integration dialogue quest","quest title uses existing HUD contract")
	var accepted:Dictionary=server.business_snapshots.progression.quests[0]
	check(accepted.get("accepted_at_key") is String,"quest snapshot carries exact acceptance key")
	if quest_social:check(accepted.get("acceptance_id") is String,"quest snapshot carries exact acceptance identity")
	accepted.accepted_at_game=float(accepted.accepted_at_game)+1e-10
	await finish(server.try_abandon_quest(QUEST),"abandon exact accepted quest")
	check(server.snapshot_quest_journal().is_empty(),"abandon projects journal")
	await finish(server.try_accept_quest(QUEST),"reaccept quest")
	await finish(server.try_interact(NPC,0,0),"talk objective")
	if quest_social:
		var stale_completion:Dictionary=await server.request_api("/v1/gameplay/interactions",HTTPClient.METHOD_POST,{"target":server.gameplay.projection.target(NPC),"action":"complete","quest":QUEST,"acceptance_id":str(accepted.acceptance_id)})
		check(not stale_completion.ok and server.inventory.get_gold()==initial_gold,"old acceptance cannot complete reaccepted quest or grant local rewards")
	await finish(server.try_turn_in_quest(QUEST),"complete quest and persist rewards")
	if quest_social:check(server.snapshot_quest_journal().is_empty(),"completion no longer consumes active quest capacity")
	check(server.inventory.get_gold()==initial_gold+100 and server.inventory.get_qty(HERB)==4,"quest gold and items come from server")
	await finish(server.try_dialogue_choice("shop_open:"+NPC),"open configured vendor")
	await finish(server.try_shop_buy(NPC,HERB,2),"purchase at trusted price")
	check(server.inventory.get_gold()==initial_gold+90 and server.inventory.get_qty(HERB)==6,"purchase updates authoritative projections")
	var herb:=item_instance(HERB)
	await finish(server.try_inventory_split(herb,2),"split by unique stack identity")
	check(server.gameplay.projection.instance(HERB).is_empty(),"ambiguous definition cannot select either stack")
	await finish(server.try_inventory_lock(herb,true),"lock exact stack")
	await finish(server.try_shop_sell(herb,1),"locked sale is rejected",false)
	check(server.inventory.get_gold()==initial_gold+90 and server.inventory.get_qty(HERB)==6,"rejected sale has no local reward")
	await finish(server.try_inventory_lock(herb,false),"unlock exact stack")
	await finish(server.try_shop_sell(herb,1),"sell exact stack")
	check(server.inventory.get_gold()==initial_gold+92 and server.inventory.get_qty(HERB)==5,"sale uses catalog price")
	await finish(server.try_shop_buyback(0),"buy back server ledger row")
	check(server.inventory.get_gold()==initial_gold+90 and server.inventory.get_qty(HERB)==6,"buyback restores items and cost")
	var sword:=item_instance(SWORD)
	await finish(server.try_equip_item(sword),"equip frozen equipment instance")
	check(server.equipment._equipped.get("weapon_main","")==sword,"HUD equipment uses exact instance")
	check(int(server.combat_stats.player.get("atk",0))>11,"effective equipment attributes projected")
	await finish(server.try_inventory_lock(sword,true),"lock equipped instance")
	await finish(server.try_inventory_lock(sword,false),"unlock equipped instance")
	await finish(server.try_unequip_item("weapon_main"),"unequip legacy slot mapped to modern protocol")
	await finish(server.try_use_item(item_instance(POTION)),"consumable executes authoritative cast")
	check(server.inventory.get_qty(POTION)==1,"consumable deducted once")
	await pause(1.)
	await finish(server.request_cast(STRIKE,DUMMY),"windup skill dispatch")
	check(server.combat_stats.skill_cd_remaining(STRIKE)>0.,"server skill cooldown projected")
	check(await wait_for_basic_attack(),"server skill recovery and global cooldown finish before basic attack")
	await finish(server.try_attack(DUMMY,0,0),"basic attack with entity generation")
	await pause(.3)
	check(int(server.gameplay.projection.entities[DUMMY].state.hp)<1000,"server damage reaches target projection")
	var cursor:int=server.gameplay._event_cursor
	check(cursor>0,"combat event delivery consumed")
	var events:Dictionary=await server.request_api("/v1/gameplay/combat-events?after=0&limit=100")
	check(events.ok and events.body.data.get("events",[]).is_empty(),"combat event ACK prevents replay")
	await finish(server.try_loot_take_all(),"claim durable kill drop")
	check(server.inventory.get_qty(HERB)==7,"kill drop reaches authoritative bag once")
	if quest_social:
		await quest_history_objective_checks()
		await guild_checks(address)
	elif not server.business_snapshots.progression.get("quest_history_available",false):
		var unsupported:Dictionary=await finish(server.try_quest_history(),"old server history reports unsupported",false)
		check(unsupported.get("unsupported",false),"old server history fallback is explicit")
		unsupported=await finish(server.try_guild_refresh(),"old server guild management reports unsupported",false)
		check(unsupported.get("unsupported",false),"old server guild fallback is explicit")
	var gold:int=server.inventory.get_gold()
	server.disconnect_server()
	var reconnect:Dictionary=await server.reconnect()
	check(reconnect.ok,"reconnect after inventory and shop writes")
	if not reconnect.ok:print(reconnect);quit(1);return
	check((await server.confirm_world_ready(server.world_session.map_ref)).ok,"fresh Ready after reconnect")
	check(server.inventory.get_gold()==gold and server.inventory.get_qty(POTION)==1,"durable gameplay restored without duplicate grants")
	if quest_social:
		var history:Dictionary=await finish(server.try_quest_history("",1),"completion history restores after reconnect")
		check(history.get("data",{}).get("quests",[]).size()==1,"reconnect history uses a bounded page")
	# Move toward a remote aggressive fixture using only actual movement intents.
	server.queue_movement(Vector3.LEFT,true)
	var deadline:=Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<deadline and server.combat_stats.player_alive():await process_frame
	server.queue_movement(Vector3.ZERO,false)
	check(not server.combat_stats.player_alive(),"actual monster simulation causes authoritative death")
	if not server.combat_stats.player_alive():
		await finish(server.try_respawn(),"respawn recovers changed actor generation")
		check(server.business_snapshots.resurrection.alive and server.combat_stats.player_alive(),"revived state reaches client")
		check(not server.is_world_ready(),"respawn requires Ready for fresh actor generation")
		check((await server.confirm_world_ready(server.world_session.map_ref)).ok and server.is_world_ready(),"respawn leaves a usable world session after Ready")
	server.disconnect_server();server.queue_free()
	print("REAL_GAMEPLAY_TESTS failures=",failures);quit(0 if failures==0 else 1)

func housing_checks(address:String)->void:
	var view:Dictionary=await finish(server.try_house_permissions("integration-home"),"owner opens house permissions")
	check(view.get("data",{}).get("can_manage",false),"personal owner manages house")
	var panel:=preload("res://scripts/ui/house_permissions.gd").new();root.add_child(panel);panel.show_house(view.data,server)
	check(panel.get_child_count()>0,"house permission UI builds without art dependencies")
	var visitor:=Real.new();root.add_child(visitor)
	visitor.register_account("resident_"+str(Time.get_ticks_usec()),"integration-password",address)
	var auth:Array=await visitor.login_finished
	check(auth[0],"second real player authenticates for housing")
	if not auth[0]:visitor.queue_free();return
	visitor.create_character("共享住户","adventurer","1","male")
	var created:Array=await visitor.character_created
	if not created[0]:check(false,"second house character");visitor.queue_free();return
	visitor.enter_world3d(int(created[2].id))
	var admission:Array=await visitor.enter_world_ready
	check(admission[0],"visitor enters public map")
	if not admission[0]:print(admission);visitor.queue_free();return
	check((await visitor.confirm_world_ready(visitor.world_session.map_ref)).ok,"visitor confirms Ready")
	var private_view:Dictionary=await finish(visitor.try_house_permissions("integration-home"),"visitor reads house rights",true,visitor)
	check(not private_view.get("data",{}).get("can_enter",true),"closed private house denies visitor")
	await finish(visitor.gameplay.dispatch("fixture",["integration-building","gate",1.]),"visitor cannot open private entrance",false,visitor)
	await finish(server.gameplay.dispatch("fixture",["integration-building","casement",1.]),"owner opens real window")
	private_view=await finish(visitor.try_house_permissions("integration-home"),"read rights after opening window",true,visitor)
	check(not private_view.data.can_enter,"window does not grant entry")
	var denied:Dictionary=await visitor.find_path(Vector3(1,0,1))
	check(not denied.get("ok",false),"unauthorized real navigation rejects house destination")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",1.]),"owner opens entrance to guests")
	private_view=await finish(visitor.try_house_permissions("integration-home"),"read open entrance rights",true,visitor)
	check(private_view.data.can_enter and private_view.data.open_to_visitors,"open entrance lets unshared visitor enter")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",0.]),"owner closes private entrance")
	await finish(server.gameplay.dispatch("fixture",["integration-building","casement",0.]),"owner closes real window")
	panel._submit({"action":"grant","member_name":"共享住户","enter":true,"operate":true,"manage":true})
	check(panel._pending_request>0,"permission UI submits real sharing request")
	var shared:Dictionary=await finish({"deferred":true,"request_id":panel._pending_request},"grant shared house management by character name")
	check(panel._pending_request==0,"permission UI releases pending state after response")
	check(shared.get("data",{}).get("members",[]).size()==1,"shared member visible to manager")
	private_view=await finish(visitor.try_house_permissions("integration-home"),"shared player refreshes rights",true,visitor)
	check(private_view.data.can_enter and private_view.data.can_manage,"personal house supports multiple managers")
	await finish(visitor.gameplay.dispatch("fixture",["integration-building","casement",1.]),"shared player operates window",true,visitor)
	var action_rows:Array=visitor.gameplay.environment.menu(visitor.business_snapshots.interactions.objects[0],Vector3(0,0,4))
	check(action_rows[0].options.size()>=2,"environment menu lists door/window and permissions")
	var window_choice:=""
	for key:String in visitor.gameplay.environment.options:
		var choice:Dictionary=visitor.gameplay.environment.options[key]
		if choice.operation=="map_interaction" and choice.args[1]=="close":window_choice=key
	check(not window_choice.is_empty(),"environment menu exposes shared window close action")
	if not window_choice.is_empty():await finish(visitor.try_dialogue_choice(window_choice),"environment menu choice changes real fixture",true,visitor)
	panel.queue_free();visitor.disconnect_server();visitor.queue_free()

func quest_history_objective_checks()->void:
	await finish(server.try_interact(NPC,0,0),"refresh NPC before new objectives")
	await finish(server.try_accept_quest(LEVEL_QUEST),"accept authoritative reach-level objective")
	var journal:Array=server.snapshot_quest_journal()
	check(journal.size()==1 and journal[0].status=="ready" and journal[0].objectives[0].cur==1,"reach-level readiness projected from server")
	await finish(server.try_turn_in_quest(LEVEL_QUEST),"complete reach-level quest")
	await finish(server.try_accept_quest(ENV_QUEST),"accept environment state and operation objectives")
	journal=server.snapshot_quest_journal()
	check(journal.size()==1 and journal[0].status=="in_progress","closed fixture keeps environment quest incomplete")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",1.]),"successful environment operation advances quest")
	journal=server.snapshot_quest_journal()
	check(journal.size()==1 and journal[0].status=="ready" and journal[0].objectives[1].cur==1,"state and actor operation progress reach existing quest HUD")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",0.]),"state objective tracks closing fixture")
	journal=server.snapshot_quest_journal()
	check(journal[0].status=="in_progress" and journal[0].objectives[0].cur==0 and journal[0].objectives[1].cur==1,"state progress reverses while committed operation count remains")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",1.]),"restore environment state for turn-in")
	await finish(server.try_turn_in_quest(ENV_QUEST),"complete environment quest")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",0.]),"close fixture after environment test")
	var configured:Dictionary=await finish(server.try_quest_history(),"default history page follows configured maximum of one")
	check(configured.data.quests.size()==1 and configured.data.has_more,"default UI page request works with history page limit below twenty")
	var first:Dictionary=await finish(server.try_quest_history("",1),"read first bounded history page")
	check(first.data.quests.size()==1 and first.data.has_more and first.data.quests[0].definition_id==ENV_QUEST,"history contains frozen latest completion and next cursor")
	var next:Dictionary=await finish(server.try_quest_history(str(first.data.next_cursor),1),"read next history page")
	check(next.data.quests.size()==1 and next.data.quests[0].definition_id==LEVEL_QUEST and next.data.quests[0].id!=first.data.quests[0].id,"keyset history page has distinct prior completion")
	check(server.snapshot_quest_journal().is_empty(),"history reads never repopulate active journal")

func guild_checks(address:String)->void:
	var peer:=DelayedGuildPeer.new();root.add_child(peer)
	peer.register_account("guild_"+str(Time.get_ticks_usec()),"integration-password",address)
	var auth:Array=await peer.login_finished
	check(auth[0],"guild peer authenticates")
	if not auth[0]:peer.queue_free();return
	peer.create_character("公会成员","adventurer","1","male")
	var created:Array=await peer.character_created
	check(created[0],"guild peer character created")
	if not created[0]:peer.queue_free();return
	peer.enter_world3d(int(created[2].id));var admission:Array=await peer.enter_world_ready
	check(admission[0],"guild peer hydrates current roster")
	if not admission[0]:peer.queue_free();return
	check((await peer.confirm_world_ready(peer.world_session.map_ref)).ok,"guild peer Ready")
	var before:int=server.inventory.get_gold()
	var view:Dictionary=await finish(server.try_guild_refresh(),"read real guild creation policy")
	await finish(server.try_guild_create("联调公会"),"create real guild")
	check(server.snapshot_guild().members.size()==1 and server.inventory.get_gold()==before-int(view.data.creation_fee),"guild roster and fee are authoritative")
	await finish(server.try_guild_invite("公会成员"),"invite real character by name")
	var deadline:=Time.get_ticks_msec()+2500
	while peer.snapshot_guild().get("invites",[]).is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	var incoming:Array=peer.snapshot_guild().get("invites",[])
	check(incoming.size()==1,"guild invitation arrives through existing runtime stream")
	if incoming.is_empty():peer.disconnect_server();peer.queue_free();return
	await finish(peer.try_guild_invite_respond(str(incoming[0].invite_id),false),"decline actual guild invitation",true,peer)
	check(peer.snapshot_guild().invites.is_empty(),"decline clears pending invitation")
	await finish(server.try_guild_refresh(),"refresh leader revision after declined invitation")
	await finish(server.try_guild_invite("公会成员"),"invite after decline")
	await finish(peer.try_guild_refresh(),"refresh invite on demand",true,peer)
	incoming=peer.snapshot_guild().invites
	if incoming.is_empty():check(false,"second guild invitation available");peer.disconnect_server();peer.queue_free();return
	await finish(peer.try_guild_invite_respond(str(incoming[0].invite_id),true),"accept actual guild invitation",true,peer)
	check(peer.snapshot_guild().members.size()==2,"accepted member receives trusted roster")
	await finish(peer.try_guild_disband(),"member cannot disband guild",false,peer)
	check(peer.snapshot_guild().members.size()==2,"denied guild operation never mutates local membership")
	await finish(server.try_guild_refresh(),"leader refresh before kick")
	peer.hold_guild_read=true
	var delayed_read:Dictionary=peer.try_guild_refresh()
	await peer.guild_read_held
	check(not str(peer.held_guild.get("id","")).is_empty(),"delayed real HTTP read captured membership before kick")
	await finish(server.try_guild_kick(str(created[2].id)),"leader kicks real member")
	deadline=Time.get_ticks_msec()+2500
	while not str(peer.snapshot_guild().get("id","")).is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(str(peer.snapshot_guild().get("id","")).is_empty(),"kick removes peer membership through runtime push")
	(func():peer.release_guild_read.emit()).call_deferred()
	await finish(delayed_read,"resolve guild HTTP after newer WebSocket publication",true,peer)
	check(str(peer.snapshot_guild().get("id","")).is_empty(),"late real HTTP response cannot restore kicked membership")
	await finish(server.try_guild_invite("公会成员"),"invite kicked member again")
	await finish(peer.try_guild_refresh(),"refresh reinvitation",true,peer)
	if peer.snapshot_guild().invites.is_empty():check(false,"reinvitation available");peer.disconnect_server();peer.queue_free();return
	await finish(peer.try_guild_invite_respond(str(peer.snapshot_guild().invites[0].invite_id),true),"member rejoins real guild",true,peer)
	await finish(peer.try_guild_leave(),"member leaves real guild",true,peer)
	check(str(peer.snapshot_guild().get("id","")).is_empty(),"leave clears trusted membership")
	await finish(server.try_guild_refresh(),"refresh after member departure")
	await finish(server.try_guild_disband(),"leader disbands real guild")
	check(str(server.snapshot_guild().get("id","")).is_empty(),"disband clears leader membership")
	peer.disconnect_server();peer.queue_free()
