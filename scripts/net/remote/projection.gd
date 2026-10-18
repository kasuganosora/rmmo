extends RefCounted
## Convert modern server identities to the existing HUD's read-only vocabulary.
const SLOTS={"weapon":"weapon_main","offhand":"weapon_off","neck":"necklace","ring1":"ring_l","ring2":"ring_r"}
var transport:Node
var definitions:Dictionary={}
var entities:Dictionary={}
var items:Dictionary={}
var quests:Array=[]
var last_dialogue:Dictionary={}
var shop:Dictionary={}
var shop_revision:=0
var _revision:=0

func _init(owner:Node)->void:transport=owner

func reset()->void:
	_revision+=1;shop_revision+=1
	definitions.clear();entities.clear();items.clear();quests.clear();last_dialogue.clear();shop.clear()

func definition(kind:String,id:String)->Dictionary:
	var key:=kind+":"+id
	if definitions.has(key):return definitions[key]
	var revision:=_revision
	var result:Dictionary=await transport.request_api("/v1/gameplay/definition?kind="+kind.uri_encode()+"&uuid="+id.uri_encode())
	if revision!=_revision:return {}
	if not result.ok:return {}
	var value:Variant=result.body.get("data",{})
	if not value is Dictionary:return {}
	if definitions.size()>=2048:definitions.clear()
	definitions[key]=value.duplicate(true)
	return definitions[key]

func hydrate()->Dictionary:
	var scope:Dictionary=transport.context()
	var inventory:Dictionary=transport.business_snapshots.get("inventory",{})
	var rows:Array=inventory.get("bag",[]).duplicate(true)
	for value in inventory.get("equipment",{}).values():rows.append(value)
	for quest:Dictionary in transport.business_snapshots.get("progression",{}).get("quests",[]):
		var rewards:Variant=quest.get("reward_items",[])
		if rewards is Array:
			for reward:Dictionary in rewards:
				rows.append({"id":reward.get("item",""),"equipment":reward.get("equipment",{})})
	for row:Dictionary in rows:
		var id:=str(row.get("id",""))
		if id.is_empty():continue
		var frozen:Dictionary=row.get("equipment",{}).get("definition",{}) if row.get("equipment") is Dictionary else {}
		var data:Dictionary=frozen if not frozen.is_empty() else await definition("items",id)
		if scope!=transport.context():return {"ok":false,"error":"stale_projection"}
		if data.is_empty():return {"ok":false,"error":"missing_item_definition","item":id}
		register_item(id,data)
	for skill:String in transport.business_snapshots.get("skills",{}).get("grants",{}):
		if not transport.business_snapshots.skills.grants[skill]:continue
		var data:Dictionary=await definition("skills",skill)
		if scope!=transport.context():return {"ok":false,"error":"stale_projection"}
		if data.is_empty():return {"ok":false,"error":"missing_skill_definition","skill":skill}
		var row:=data.duplicate(true);row.id=skill
		row.cooldown=float(data.get("timing",{}).get("cooldown_ms",0))/1000.
		row.cast_time=float(data.get("timing",{}).get("cast_ms",0))/1000.
		row.mp_cost=data.get("cost",{}).get("mp",0)
		row.range=data.get("target",{}).get("range_m",0)
		row.requires_target=data.get("target",{}).get("mode","")=="unit"
		row.target_mode="ground" if data.get("target",{}).get("mode","")=="area" else data.get("target",{}).get("mode","self")
		transport.skill_catalog.register_skill(row)
	entities.clear()
	for entity:Dictionary in transport.business_snapshots.get("entities",[]):
		var id:=str(entity.get("uuid",""))
		if id.is_empty():continue
		var data:Dictionary=await definition(str(entity.get("kind","npcs")),str(entity.get("definition","")))
		if scope!=transport.context():return {"ok":false,"error":"stale_projection"}
		if data.is_empty():return {"ok":false,"error":"missing_creature_definition"}
		var row:=entity.duplicate(true);row["details"]=data;entities[id]=row
	apply()
	return {"ok":true}

func register_item(id:String,data:Dictionary)->void:
	var row:=data.duplicate(true);row.id=id
	row.equip_slot=SLOTS.get(str(data.get("equip_slot","")),str(data.get("equip_slot","")))
	row.bonuses={"atk":data.get("attack",0),"def":data.get("defense",0),"hp_max":data.get("hp_max_bonus",0),"mp_max":data.get("mp_max_bonus",0)}
	transport.item_catalog.register_item(row)
	items[id]=data.duplicate(true)

func item_row(raw:Dictionary)->Dictionary:
	var row:=raw.duplicate(true)
	var definition_id:=str(raw.get("id",""))
	var instance:=str(raw.get("instance_id",""))
	row.definition_id=definition_id;row.id=instance if not instance.is_empty() else definition_id
	if items.has(definition_id):register_item(str(row.id),items[definition_id])
	return row

func bag()->Array:
	var rows:Array=[]
	for raw:Dictionary in transport.business_snapshots.get("inventory",{}).get("bag",[]):rows.append(item_row(raw))
	return rows

func equipment()->Array:
	var rows:Array=[]
	for slot:String in transport.business_snapshots.get("inventory",{}).get("equipment",{}):
		var row:=item_row(transport.business_snapshots.inventory.equipment[slot]);row.slot=SLOTS.get(slot,slot);row.item_id=row.id;rows.append(row)
	return rows

func instance(reference:String,include_equipped:bool=false)->Dictionary:
	var found:Array=[]
	var inventory:Dictionary=transport.business_snapshots.get("inventory",{})
	var rows:Array=inventory.get("bag",[]).duplicate(true)
	if include_equipped:rows.append_array(inventory.get("equipment",{}).values())
	for row:Dictionary in rows:
		if reference==str(row.get("instance_id","")):return row.duplicate(true)
		if reference==str(row.get("id","")):found.append(row)
	return found[0].duplicate(true) if found.size()==1 else {}

func target(id:String)->Dictionary:
	if not entities.has(id):return {}
	var row:Dictionary=entities[id]
	return {"id":id,"map":row.get("map",""),"generation":int(row.get("state",{}).get("generation",0))}

func apply()->void:
	var progression:Dictionary=transport.business_snapshots.get("progression",{})
	var inventory:Dictionary=transport.business_snapshots.get("inventory",{})
	var attributes:Dictionary=inventory.get("stats",{})
	for key:String in attributes.get("effective",{}):
		transport.combat_stats.player[{"attack":"atk","defense":"def"}.get(key,key)]=attributes.effective[key]
	transport.combat_stats.player.attrs=attributes.get("points",{}).duplicate(true)
	transport.combat_stats.player.attr_points=int(inventory.get("free_attr",0))
	var now_game:=float(transport.business_snapshots.get("combat-state",{}).get("server_elapsed",0))
	var skills:Dictionary=transport.business_snapshots.get("skills",{})
	transport.combat_stats.skill_ready_at.clear()
	for id:String in skills.get("cooldowns_game_us",{}):
		transport.combat_stats.set_skill_cooldown(id,maxf(0.,float(skills.cooldowns_game_us[id])/1000000.-now_game))
	transport.combat_stats.set_attack_cooldown(maxf(0.,float(transport.business_snapshots.get("combat-state",{}).get("ready_at_game",0))-now_game))
	transport.inventory.restore_session_state({"stacks":bag(),"gold":int(progression.get("gold",0)),"max_slots":int(transport.business_snapshots.get("inventory",{}).get("capacity",40))})
	for row:Dictionary in transport.inventory.snapshot():transport.inventory.locked[str(row.id)]=bool(row.get("locked",false))
	transport.equipment.clear()
	for row:Dictionary in equipment():transport.equipment._equipped[str(row.slot)]=str(row.id)
	var known:Array=[]
	for id:String in skills.get("grants",{}):
		if skills.grants[id]:known.append(id)
	transport.combat_stats.skill_book.apply_snapshot({"known":known,"skill_points":0})
	quests=[]
	for raw:Dictionary in progression.get("quests",[]):
		var definition:Dictionary=raw.get("definition",{})
		var row:=definition.duplicate(true);row.id=definition.get("uuid","");row.status="completed" if raw.get("completed",false) else "in_progress"
		row.title=definition.get("name",row.id);row.desc=definition.get("description","")
		row.reward={"gold":int(definition.get("gold",0)),"exp":int(definition.get("experience",0)),"items":[]}
		for reward:Dictionary in definition.get("items",[]):row.reward.items.append({"item_id":reward.get("item",""),"qty":int(reward.get("qty",0))})
		row.objectives=[]
		var ready:=true
		for objective:Dictionary in definition.get("objectives",[]):
			var task:=objective.duplicate(true);task.cur=int(raw.get("progress",{}).get(str(objective.id),0));task.max=int(objective.get("count",1))
			task.text={"talk":"交谈","kill":"击败","collect":"收集"}.get(str(objective.get("kind","")),"目标")+"："+str(objective.get("target",""))
			for entity:Dictionary in entities.values():
				if entity.get("definition")==objective.get("target"):task.text=str(entity.get("details",{}).get("name",task.text));break
			row.objectives.append(task)
			if task.cur<task.max:ready=false
		if ready and not raw.get("completed",false):row.status="ready"
		quests.append(row)
	transport.combat_stats.clear_npcs()
	for id:String in entities:
		var row:Dictionary=entities[id];var data:Dictionary=row.details
		var stats:Dictionary=transport.combat_stats.ensure_npc(id,bool(row.get("combat_enabled",false)))
		stats.hp=int(row.get("state",{}).get("hp",0));stats.hp_max=int(data.get("hp_max",1));stats.name=str(data.get("name",id));stats.level=int(data.get("level",1))

func equipment_bonuses()->Dictionary:
	var value:Dictionary=transport.business_snapshots.get("inventory",{}).get("stats",{}).get("equipment",{})
	return {"atk":value.get("attack",0),"def":value.get("defense",0),"hp_max":value.get("hp_max",0),"mp_max":value.get("mp_max",0)}

func actions()->Array:
	var result:Array=[{"type":"inventory_update","items":bag(),"gold":transport.inventory.get_gold()},
		{"type":"equipment_update","equipment":equipment(),"bonuses":equipment_bonuses()},
		{"type":"quest_update","quests":quests.duplicate(true)},
		{"type":"remote_entities"},
		{"type":"remote_combat_state","stats":transport.combat_stats.snapshot_player_stats()}]
	var statuses:Array=[]
	var now_game:=float(transport.business_snapshots.get("combat-state",{}).get("server_elapsed",0))
	for status:Dictionary in transport.business_snapshots.get("statuses",{}).get("active",[]):
		var spec:Dictionary=status.get("definition",{})
		statuses.append({"id":status.get("status_id",""),"name":spec.get("key",""),"kind":spec.get("kind",""),"stacks":status.get("stacks",1),"remaining_sec":maxf(0.,float(status.get("expires_game_us",0))/1000000.-now_game),"duration_max":float(spec.get("duration_ms",0))/1000.})
	result.append({"type":"status_update","statuses":statuses})
	for id:String in transport.combat_stats.skill_ready_at:
		result.append({"type":"skill_cd","skill_id":id,"remaining":transport.combat_stats.skill_cd_remaining(id),"cooldown":float(transport.skill_catalog.get_skill(id).get("cooldown",0))})
	return result

func dialogue(data:Dictionary)->Array:
	last_dialogue=data.duplicate(true)
	var options:Array=[]
	for quest:Dictionary in data.get("quests",[]):
		var definition:Dictionary=quest.get("definition",{});var id:=str(definition.get("uuid",""))
		if quest.get("can_accept",false):options.append({"id":"quest_accept:"+id,"label":"接受："+str(definition.get("name",id))})
		if quest.get("can_complete",false):options.append({"id":"quest_turn_in:"+id,"label":"交付："+str(definition.get("name",id))})
	if data.get("shop") is Dictionary:options.append({"id":"shop_open:"+str(data.target.id),"label":"看看商品"})
	return [{"type":"show_npc_dialogue","npc_id":data.get("target",{}).get("id",""),"npc_name":data.get("name",""),"body":data.get("dialogue",""),"options":options}]
