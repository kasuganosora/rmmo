extends RefCounted
## Mock L2-style bags / skills / quests derived from selected character.

static func class_label(class_id: String) -> String:
	match class_id:
		"mage":
			return "法师"
		"warrior":
			return "战士"
		_:
			return "冒险者"

static func inventory_for(ch: Dictionary) -> Dictionary:
	var class_id := str(ch.get("class_id", "adventurer"))
	var items: Array = [
		{"name": "新手短剑", "type": "weapon", "qty": 1, "weight": 1200},
		{"name": "亚麻衣", "type": "armor", "qty": 1, "weight": 800},
		{"name": "红药水", "type": "consumable", "qty": 10, "weight": 20},
		{"name": "蓝药水", "type": "consumable", "qty": 5, "weight": 20},
	]
	if class_id == "mage":
		items[0] = {"name": "学徒魔杖", "type": "weapon", "qty": 1, "weight": 900}
		items.append({"name": "灵魂弹", "type": "consumable", "qty": 50, "weight": 5})
	elif class_id == "warrior":
		items[0] = {"name": "阔剑", "type": "weapon", "qty": 1, "weight": 1600}
		items.append({"name": "皮盾", "type": "armor", "qty": 1, "weight": 1100})
	var quest_items: Array = [
		{"name": "训练木剑证明", "type": "quest", "qty": 1, "weight": 0},
	]
	var weight := 0
	for it in items:
		weight += int(it.get("weight", 0)) * int(it.get("qty", 1))
	for it in quest_items:
		weight += int(it.get("weight", 0)) * int(it.get("qty", 1))
	var lv := int(ch.get("level", 1))
	return {
		"adena": 500 + lv * 120,
		"weight": weight,
		"weight_max": 46000 + lv * 2000,
		"items": items,
		"quest_items": quest_items,
	}

static func skills_for(ch: Dictionary) -> Dictionary:
	var class_id := str(ch.get("class_id", "adventurer"))
	var active: Array = [
		{"name": "普通攻击", "kind": "normal", "lv": 1},
		{"name": "气合", "kind": "buff", "lv": 1},
	]
	var passive: Array = [
		{"name": "武器精通", "kind": "passive", "lv": 1},
	]
	if class_id == "mage":
		active = [
			{"name": "风之打击", "kind": "normal", "lv": 1},
			{"name": "治愈术", "kind": "buff", "lv": 1},
			{"name": "弱化", "kind": "debuff", "lv": 1},
		]
		passive = [{"name": "法术精通", "kind": "passive", "lv": 1}]
	elif class_id == "warrior":
		active = [
			{"name": "强力斩击", "kind": "normal", "lv": 1},
			{"name": "嘲讽", "kind": "debuff", "lv": 1},
			{"name": "防御姿态", "kind": "toggle", "lv": 1},
		]
		passive = [{"name": "重装精通", "kind": "passive", "lv": 1}]
	return {"active": active, "passive": passive}

static func quests_for(ch: Dictionary) -> Array:
	var name := str(ch.get("name", "冒险者"))
	return [
		{
			"title": "新手的第一步",
			"npc": "训练教官",
			"progress": "0 / 3 只训练假人",
			"place": "starter_field",
			"solo": true,
			"repeat": false,
		},
		{
			"title": "%s 的试炼" % name,
			"npc": "村庄长老",
			"progress": "未开始",
			"place": "talking_island",
			"solo": true,
			"repeat": false,
		},
	]

static func char_stats(ch: Dictionary) -> Dictionary:
	var lv := int(ch.get("level", 1))
	var class_id := str(ch.get("class_id", "adventurer"))
	var str_v := 20 + lv
	var int_v := 20 + lv
	var dex_v := 20 + lv
	var con_v := 20 + lv
	var wit_v := 20 + lv
	var men_v := 20 + lv
	if class_id == "warrior":
		str_v += 8
		con_v += 5
	elif class_id == "mage":
		int_v += 8
		wit_v += 5
		men_v += 4
	else:
		dex_v += 4
		str_v += 2
	return {
		"class_id": class_id,
		"class_label": class_label(class_id),
		"exp": lv * lv * 100,
		"sp": lv * 50,
		"adena": 500 + lv * 120,
		"clan": "无",
		"str": str_v,
		"dex": dex_v,
		"con": con_v,
		"int": int_v,
		"wit": wit_v,
		"men": men_v,
		"p_atk": 12 + lv * 3 + (8 if class_id == "warrior" else 0),
		"m_atk": 10 + lv * 2 + (10 if class_id == "mage" else 0),
		"p_def": 20 + lv * 2,
		"m_def": 18 + lv * 2,
	}
