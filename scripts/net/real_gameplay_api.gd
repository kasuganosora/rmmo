extends "res://scripts/net/remote_boundary.gd"
## Explicit real-service adapters. No local authoritative methods are inherited.
var gameplay=preload("res://scripts/net/remote/gameplay.gd").new(self)

func try_attack(npc_id:String,_player_x:int,_player_y:int)->Dictionary:
	return gameplay.dispatch("attack",[npc_id])
func try_use_skill(skill_id:String,target_npc_id:String="",_player_x:int=-9999,_player_y:int=-9999,_ground_x:int=-9999,_ground_y:int=-9999)->Dictionary:
	if skill_id=="basic_attack":return gameplay.dispatch("attack",[target_npc_id])
	return gameplay.dispatch("skill",[skill_id,target_npc_id])
func request_cast(skill_id:String,target_id:String="",ground:Variant=null)->Dictionary:
	if skill_id=="basic_attack":return gameplay.dispatch("attack",[target_id])
	return gameplay.dispatch("skill",[skill_id,target_id,ground])
func try_cancel_cast()->Dictionary:return gameplay.dispatch("cancel_cast")
func try_use_item(item_id:String)->Dictionary:return gameplay.dispatch("item",[item_id])
func try_equip_item(item_id:String,_slot:String="")->Dictionary:return gameplay.dispatch("inventory",[{"action":"equip","reference":item_id}])
func try_unequip_item(slot:String)->Dictionary:
	var reverse:Dictionary={}
	for key:String in gameplay.projection.SLOTS:reverse[gameplay.projection.SLOTS[key]]=key
	return gameplay.dispatch("inventory",[{"action":"unequip","slot":reverse.get(slot,slot)}])
func try_toggle_equip(item_id:String)->Dictionary:
	for row:Dictionary in gameplay.projection.equipment():
		if item_id==str(row.id):return try_unequip_item(str(row.slot))
	return try_equip_item(item_id)
func try_inventory_split(item_id:String,qty:int)->Dictionary:return gameplay.dispatch("inventory",[{"action":"split","reference":item_id,"quantity":qty}])
func try_inventory_sort()->Dictionary:return gameplay.dispatch("inventory",[{"action":"sort"}])
func try_inventory_lock(item_id:String,on:bool)->Dictionary:return gameplay.dispatch("inventory",[{"action":"lock","reference":item_id,"locked":on}])
func try_allocate_attr(stat_key:String,amount:int=1)->Dictionary:return gameplay.dispatch("inventory",[{"action":"allocate","attribute":stat_key,"quantity":amount}])
func try_interact(npc_id:String,_player_x:int,_player_y:int)->Dictionary:return gameplay.dispatch("interact",[npc_id])
func try_dialogue_choice(option_id:String="",_option_index:int=-1)->Dictionary:
	if option_id.begins_with("environment:"):return gameplay.environment.choose(option_id)
	for prefix:String in ["quest_accept:","quest_turn_in:","shop_open:"]:
		if not option_id.begins_with(prefix):continue
		var id:=option_id.substr(prefix.length())
		if prefix=="shop_open:":return gameplay.dispatch("shop_open",[id])
		return gameplay.dispatch("quest",["accept" if prefix=="quest_accept:" else "complete",id])
	return gameplay.failure("此对话选项不属于服务器当前菜单")
func try_event_choice(option_id:String="",option_index:int=-1)->Dictionary:return try_dialogue_choice(option_id,option_index)
func try_accept_quest(quest_id:String)->Dictionary:return gameplay.dispatch("quest",["accept",quest_id])
func try_turn_in_quest(quest_id:String)->Dictionary:return gameplay.dispatch("quest",["complete",quest_id])
func try_abandon_quest(quest_id:String)->Dictionary:return gameplay.dispatch("abandon_quest",[quest_id])
func try_respawn(_where:String="town")->Dictionary:return gameplay.dispatch("respawn")
func try_shop_buy(_shop_id:String,item_id:String,qty:int=1)->Dictionary:return gameplay.dispatch("shop",[{"action":"buy","item":item_id,"quantity":qty}])
func try_shop_sell(item_id:String,qty:int=1)->Dictionary:return gameplay.dispatch("shop",[{"action":"sell","reference":item_id,"quantity":qty}])
func try_shop_buyback(index:int,_qty:int=-1)->Dictionary:
	var rows:Array=snapshot_shop_buyback()
	if index<0 or index>=rows.size():return gameplay.failure("回购物品已变化，请刷新商店")
	return gameplay.dispatch("shop",[{"action":"buyback","index":int(rows[index].get("index",index))}])
func try_shop_close()->Dictionary:
	gameplay.projection.shop_revision+=1
	gameplay.projection.shop.clear()
	return {"ok":true,"actions":[]}
func snapshot_quest_journal()->Array:return gameplay.projection.quests.duplicate(true)
func snapshot_skill_book()->Dictionary:return combat_stats.skill_book.snapshot()
func snapshot_skill_catalog()->Array:return skill_catalog.list_all()
func snapshot_party()->Dictionary:return gameplay.transport.business_snapshots.get("party",{}).duplicate(true)
func snapshot_shop(_shop_id:String="starter_goods")->Dictionary:return gameplay.projection.shop.duplicate(true)
func snapshot_shop_buyback()->Array:return gameplay.projection.shop.get("buyback",[]).duplicate(true)

func nearest_reward()->String:
	var point:Dictionary=gameplay.transport.self_actor.get("location",{}).get("position_m",{})
	var feet:=Vector3(point.get("x",0.),point.get("y",0.),point.get("z",0.))
	for row:Dictionary in gameplay.transport.business_snapshots.get("rewards",{}).get("rewards",[]):
		var reward:Dictionary=row.get("reward",{})
		var p:Dictionary=reward.get("position_m",{})
		if not row.get("claimed",false) and reward.get("map")==gameplay.transport.world_session.get("map_ref") and feet.distance_to(Vector3(p.get("x",0.),p.get("y",0.),p.get("z",0.)))<=2.:return str(reward.get("id",""))
	return ""
func try_loot_take_all()->Dictionary:
	var id:=nearest_reward()
	return gameplay.dispatch("claim_reward",[id]) if not id.is_empty() else gameplay.failure("附近没有可领取的服务器掉落")

func try_house_permissions(house:String)->Dictionary:return gameplay.dispatch("house_view",[house])
func try_house_update(change:Dictionary)->Dictionary:return gameplay.dispatch("house_change",[change])
