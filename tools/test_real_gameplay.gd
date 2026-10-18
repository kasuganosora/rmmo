extends SceneTree
const Real=preload("res://scripts/net/real_server.gd")
const NS="11111111-1111-4111-8111-111111111111:92205a4714219670:"
const NPC=NS+"00000000-0000-4000-8000-000000000008"
const HERB=NS+"00000000-0000-4000-8000-000000000001"
const POTION=NS+"00000000-0000-4000-8000-000000000002"
const SWORD=NS+"00000000-0000-4000-8000-00000000000c"
const QUEST=NS+"00000000-0000-4000-8000-000000000f01"
const DUMMY=NS+"00000000-0000-4000-8000-000000000f12"
const HEAL=NS+"7de8d659-52d1-4d13-81fd-a72b5c5ad031"
const STRIKE=NS+"935ae5bb-e846-44ca-9f8a-90f9aa2f5161"
var server:Node
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func finish(request:Dictionary,label:String,expected:bool=true)->Dictionary:
	var result:=request
	if request.get("deferred",false):
		while true:
			var reply:Array=await server.response_ready
			if int(reply[0])==int(request.request_id):result=reply[1];break
	check(bool(result.get("ok",false))==expected,label)
	if bool(result.get("ok",false))!=expected:print(result)
	check(result.get("actions",[]).is_empty(),label+" delivers actions only through polling")
	return result
func pause(seconds:float)->void:await create_timer(seconds).timeout
func item_instance(definition:String)->String:
	for row:Dictionary in server.gameplay.projection.bag():
		if row.definition_id==definition:return str(row.id)
	return ""
func run()->void:
	create_timer(65).timeout.connect(func():print("FAIL gameplay watchdog timeout");quit(2))
	var address:=""
	for arg:String in OS.get_cmdline_user_args():
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
		if fixture.get("owner_id")=="integration-building":opened=fixture.get("state")=="open"
	check(opened,"map fixture snapshot changes only after server commit")
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",.5]),"partial fixture state rejected",false)
	await finish(server.gameplay.dispatch("fixture",["integration-building","gate",0.]),"close authoritative map fixture")
	var initial_gold:int=server.inventory.get_gold()
	await finish(server.try_interact(NPC,0,0),"NPC dialogue")
	await finish(server.try_accept_quest(QUEST),"accept quest")
	check(server.snapshot_quest_journal()[0].title=="Integration dialogue quest","quest title uses existing HUD contract")
	await finish(server.try_abandon_quest(QUEST),"abandon exact accepted quest")
	check(server.snapshot_quest_journal().is_empty(),"abandon projects journal")
	await finish(server.try_accept_quest(QUEST),"reaccept quest")
	await finish(server.try_interact(NPC,0,0),"talk objective")
	await finish(server.try_turn_in_quest(QUEST),"complete quest and persist rewards")
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
	await pause(.7)
	await finish(server.try_attack(DUMMY,0,0),"basic attack with entity generation")
	await pause(.3)
	check(int(server.gameplay.projection.entities[DUMMY].state.hp)<1000,"server damage reaches target projection")
	var cursor:int=server.gameplay._event_cursor
	check(cursor>0,"combat event delivery consumed")
	var events:Dictionary=await server.request_api("/v1/gameplay/combat-events?after=0&limit=100")
	check(events.ok and events.body.data.get("events",[]).is_empty(),"combat event ACK prevents replay")
	await finish(server.try_loot_take_all(),"claim durable kill drop")
	check(server.inventory.get_qty(HERB)==7,"kill drop reaches authoritative bag once")
	var gold:int=server.inventory.get_gold()
	server.disconnect_server()
	var reconnect:Dictionary=await server.reconnect()
	check(reconnect.ok,"reconnect after inventory and shop writes")
	if not reconnect.ok:print(reconnect);quit(1);return
	check((await server.confirm_world_ready(server.world_session.map_ref)).ok,"fresh Ready after reconnect")
	check(server.inventory.get_gold()==gold and server.inventory.get_qty(POTION)==1,"durable gameplay restored without duplicate grants")
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
