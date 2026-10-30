extends RefCounted
## Convert modern server identities to the existing HUD's read-only vocabulary.
const Contract=preload("res://scripts/net/remote/combat_contract.gd")
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
var _definition_version:=""
var _skill_catalog_stamp:=""
var _skill_book_stamp:=""
var _resurrection_stamp:=""

func _init(owner:Node)->void:transport=owner

func reset()->void:
	_revision+=1;shop_revision+=1
	definitions.clear();entities.clear();items.clear();quests.clear();last_dialogue.clear();shop.clear()
	_definition_version="";_skill_catalog_stamp="";_skill_book_stamp="";_resurrection_stamp=""

func _sync_definition_version()->void:
	var training:Dictionary=transport.business_snapshots.get("skills",{}).get("training",{})
	var stamp:=JSON.stringify([transport.context(),training.get("version",0)])
	if stamp!=_definition_version:
		_definition_version=stamp;_revision+=1;definitions.clear()

func definition(kind:String,id:String)->Dictionary:
	_sync_definition_version()
	if kind=="skills":
		for entry:Dictionary in training_view().get("entries",[]):
			if entry.get("skill_uuid","")==id and entry.get("definition") is Dictionary:
				return entry.definition.duplicate(true)
	var key:=kind+":"+id+":"+_definition_version
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
	_sync_definition_version()
	var scope:Dictionary=transport.context()
	var publication:int=transport._snapshot_published_serial
	var snapshots:Dictionary=transport.business_snapshots.duplicate(true)
	var pending_items:Array=[];var pending_skills:Array=[];var pending_entities:Dictionary={}
	var inventory:Dictionary=snapshots.get("inventory",{})
	var rows:Array=inventory.get("bag",[]).duplicate(true)
	for value in inventory.get("equipment",{}).values():rows.append(value)
	for quest:Dictionary in snapshots.get("progression",{}).get("quests",[]):
		var rewards:Variant=quest.get("reward_items",[])
		if rewards is Array:
			for reward:Dictionary in rewards:
				rows.append({"id":reward.get("item",""),"equipment":reward.get("equipment",{})})
	for row:Dictionary in rows:
		var id:=str(row.get("id",""))
		if id.is_empty():continue
		var frozen:Dictionary=row.get("equipment",{}).get("definition",{}) if row.get("equipment") is Dictionary else {}
		var data:Dictionary=frozen if not frozen.is_empty() else await definition("items",id)
		if scope!=transport.context() or publication!=transport._snapshot_published_serial:return {"ok":false,"error":"stale_projection"}
		if data.is_empty():return {"ok":false,"error":"missing_item_definition","item":id}
		pending_items.append({"id":id,"data":data})
	var skill_ids:Dictionary={}
	var training_entries:Dictionary={}
	for skill:String in snapshots.get("skills",{}).get("grants",{}):
		if snapshots.skills.grants[skill]:skill_ids[skill]=true
	for entry:Dictionary in snapshots.get("skills",{}).get("training",{}).get("entries",[]):
		var skill:=str(entry.get("skill_uuid",""))
		if not skill.is_empty():skill_ids[skill]=true;training_entries[skill]=entry
	for skill:String in skill_ids:
		var data:Dictionary=await definition("skills",skill)
		if scope!=transport.context() or publication!=transport._snapshot_published_serial:return {"ok":false,"error":"stale_projection"}
		if data.is_empty():return {"ok":false,"error":"missing_skill_definition","skill":skill}
		pending_skills.append(Contract.skill_row(skill,data,training_entries.get(skill,{})))
	for entity:Dictionary in snapshots.get("entities",[]):
		var id:=str(entity.get("uuid",""))
		if id.is_empty():continue
		var data:Dictionary=await definition(str(entity.get("kind","npcs")),str(entity.get("definition","")))
		if scope!=transport.context() or publication!=transport._snapshot_published_serial:return {"ok":false,"error":"stale_projection"}
		if data.is_empty():return {"ok":false,"error":"missing_creature_definition"}
		var row:=entity.duplicate(true);row["details"]=data;pending_entities[id]=row
	if scope!=transport.context() or publication!=transport._snapshot_published_serial:return {"ok":false,"error":"stale_projection"}
	for item:Dictionary in pending_items:register_item(str(item.id),item.data)
	transport.skill_catalog._by_id.clear()
	transport.skill_catalog.register_skill({"id":"basic_attack","name":"普通攻击","requires_target":true,"starter":true,"category":"physical"})
	for skill:Dictionary in pending_skills:transport.skill_catalog.register_skill(skill)
	entities=pending_entities
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
	if id.is_empty():return {}
	var map_ref:=str(transport.world_session.get("map_ref",""))
	var row:Dictionary={}
	var generation:Variant=null
	if transport.actors.has(id):
		if entities.has(id):return {}
		row=transport.actors[id]
		if row.get("location",{}).get("map_ref","")!=map_ref:return {}
		generation=row.get("generation")
	elif id==transport._session_character_id and not transport.self_actor.is_empty():
		row=transport.self_actor
		if row.get("location",{}).get("map_ref","")!=map_ref:return {}
		generation=row.get("generation")
	elif entities.has(id):
		row=entities[id]
		if row.get("map","")!=map_ref:return {}
		generation=row.get("state",{}).get("generation")
	else:return {}
	if not generation is int and not generation is float:return {}
	if not is_finite(float(generation)) or float(generation)!=floor(float(generation)) or float(generation)<0 or float(generation)>9007199254740991:return {}
	return {"id":id,"map":map_ref,"generation":int(generation)}

func training_view()->Dictionary:
	return transport.business_snapshots.get("skills",{}).get("training",{}).duplicate(true)

func training_entry(id:String)->Dictionary:
	for entry:Dictionary in training_view().get("entries",[]):
		if str(entry.get("skill_uuid",""))==id:return entry.duplicate(true)
	return {}

func statuses_snapshot()->Dictionary:
	return Contract.status_state(transport.business_snapshots.get("statuses",{}))

func acceptance(quest_id:String)->Dictionary:
	for quest:Dictionary in transport.business_snapshots.get("progression",{}).get("quests",[]):
		if quest.get("definition",{}).get("uuid","")!=quest_id:continue
		var result:Dictionary={}
		if quest.has("accepted_at_key"):result.accepted_at_key=str(quest.accepted_at_key)
		else:result.accepted_at_game=quest.get("accepted_at_game")
		if quest.has("acceptance_id"):result.acceptance_id=str(quest.acceptance_id)
		return result
	return {}

func objective_text(objective:Dictionary)->String:
	var kind:=str(objective.get("kind",""))
	var target:=str(objective.get("target",""))
	match kind:
		"reach_level":return "达到等级 %d" % int(objective.get("count",1))
		"complete_instance":return "通关副本："+target
		"environment_state","environment_operate":
			var object_name:=str(objective.get("object",""))
			for row:Dictionary in transport.business_snapshots.get("interactions",{}).get("objects",[]):
				if str(row.get("id",""))==object_name:object_name=str(row.get("name",row.get("fixture_id",object_name)));break
			var state:=str(objective.get("state",""));var action:=str(objective.get("action",""))
			var labels:={"open":"打开","close":"关闭","closed":"关闭","on":"开启","off":"关闭","activate":"激活","use":"使用"}
			var condition:=str(labels.get(state if kind=="environment_state" else action,state if kind=="environment_state" else action))
			if kind=="environment_operate" and not state.is_empty():condition+=" → "+str(labels.get(state,state))
			return "%s：%s（%s · %s）" % ["环境状态" if kind=="environment_state" else "环境操作",object_name,condition,str(objective.get("map",""))]
	var name:=target
	for entity:Dictionary in entities.values():
		if entity.get("definition")==target:name=str(entity.get("details",{}).get("name",target));break
	return str({"talk":"交谈","kill":"击败","collect":"收集"}.get(kind,"目标"))+"："+name

func apply()->void:
	var progression:Dictionary=transport.business_snapshots.get("progression",{})
	var inventory:Dictionary=transport.business_snapshots.get("inventory",{})
	var attributes:Dictionary=inventory.get("stats",{})
	var vitals:Dictionary=transport.business_snapshots.get("combat-state",{})
	transport.combat_stats.player={"authoritative":true}
	for key:String in ["hp","hp_max","mp","mp_max"]:
		if vitals.has(key):transport.combat_stats.player[key]=int(vitals[key])
	for key:String in ["level","experience","experience_to_next","exp_to_next"]:
		if progression.has(key):transport.combat_stats.player[{"experience":"exp","experience_to_next":"exp_to_next"}.get(key,key)]=progression[key]
	transport.combat_stats.player.attributes=attributes.duplicate(true)
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
	var training:Dictionary=skills.get("training",{})
	for entry:Dictionary in training.get("entries",[]):
		if (int(entry.get("rank",0))>0 or entry.get("granted",false)) and str(entry.get("skill_uuid","")) not in known:known.append(str(entry.skill_uuid))
	transport.combat_stats.skill_book.apply_snapshot({"known":known,"skill_points":int(training.get("skill_points",0))})
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
			task.text=objective_text(objective)
			row.objectives.append(task)
			if task.cur<task.max:ready=false
		if ready and not raw.get("completed",false):row.status="ready"
		quests.append(row)
	transport.combat_stats.clear_npcs()
	for id:String in entities:
		var row:Dictionary=entities[id];var data:Dictionary=row.details
		var state:Dictionary=row.get("state",{})
		var stats:Dictionary={"authoritative":true,"hp":int(state.get("hp",0)),"hp_max":int(data.get("hp_max",1)),"name":str(data.get("name",id)),"level":int(data.get("level",1)),"hostile":bool(row.get("combat_enabled",false))}
		var effective:Dictionary=row.get("stats",{}).get("effective",{})
		for key:String in effective:stats[{"attack":"atk","defense":"def"}.get(key,key)]=effective[key]
		if state.has("mp"):stats.mp=int(state.mp)
		if data.has("mp_max"):stats.mp_max=int(data.mp_max)
		transport.combat_stats.npcs[id]=stats

func equipment_bonuses()->Dictionary:
	var value:Dictionary=transport.business_snapshots.get("inventory",{}).get("stats",{}).get("equipment",{})
	return {"atk":value.get("attack",0),"def":value.get("defense",0),"hp_max":value.get("hp_max",0),"mp_max":value.get("mp_max",0)}

func actions()->Array:
	var result:Array=[{"type":"inventory_update","items":bag(),"gold":transport.inventory.get_gold()},
		{"type":"equipment_update","equipment":equipment(),"bonuses":equipment_bonuses()},
		{"type":"quest_update","quests":quests.duplicate(true)},
		{"type":"remote_entities"},
		{"type":"remote_combat_state","stats":transport.combat_stats.snapshot_player_stats()}]
	result.append_array(transport.gameplay.social.actions())
	var resurrection:Dictionary=transport.business_snapshots.get("resurrection",{})
	var resurrection_stamp:=JSON.stringify(resurrection)
	if resurrection_stamp!=_resurrection_stamp:
		_resurrection_stamp=resurrection_stamp;result.append({"type":"resurrection_update","resurrection":resurrection.duplicate(true)})
	var skill_rows:Array=transport.skill_catalog.list_all()
	var catalog_stamp:=JSON.stringify(skill_rows)
	if catalog_stamp!=_skill_catalog_stamp:
		_skill_catalog_stamp=catalog_stamp;result.append({"type":"skill_catalog_update","skills":skill_rows})
	var book:Dictionary=transport.combat_stats.skill_book.snapshot()
	var book_stamp:=JSON.stringify([book,training_view()])
	if book_stamp!=_skill_book_stamp:
		_skill_book_stamp=book_stamp;result.append(dict_with_book(book))
	var statuses:Array=[]
	var snapshot:Dictionary=transport.business_snapshots.get("statuses",{})
	var now_game:=float(snapshot.get("game_time_us",0))/1000000.
	if not snapshot.has("game_time_us"):now_game=float(transport.business_snapshots.get("combat-state",{}).get("server_elapsed",0))
	for status:Dictionary in statuses_snapshot().get("active",[]):
		statuses.append(Contract.status_row(status,now_game,snapshot.get("cancelable",[])))
	result.append({"type":"status_update","statuses":statuses})
	for id:String in transport.combat_stats.skill_ready_at:
		result.append({"type":"skill_cd","skill_id":id,"remaining":transport.combat_stats.skill_cd_remaining(id),"cooldown":float(transport.skill_catalog.get_skill(id).get("cooldown",0))})
	return result

func dict_with_book(book:Dictionary)->Dictionary:
	var action:=book.duplicate(true);action.type="skill_book_update";action.training=training_view()
	return action

func dialogue(data:Dictionary)->Array:
	last_dialogue=data.duplicate(true)
	var options:Array=[]
	for quest:Dictionary in data.get("quests",[]):
		var definition:Dictionary=quest.get("definition",{});var id:=str(definition.get("uuid",""))
		if quest.get("can_accept",false):options.append({"id":"quest_accept:"+id,"label":"接受："+str(definition.get("name",id))})
		if quest.get("can_complete",false):options.append({"id":"quest_turn_in:"+id,"label":"交付："+str(definition.get("name",id))})
	if data.get("shop") is Dictionary:options.append({"id":"shop_open:"+str(data.target.id),"label":"看看商品"})
	return [{"type":"show_npc_dialogue","npc_id":data.get("target",{}).get("id",""),"npc_name":data.get("name",""),"body":data.get("dialogue",""),"options":options}]
