extends RefCounted
## Item IDs and independent paperdoll layers; never a dressed Body variant.
const PARTS := {"Clothing1": 1, "Clothing2": 1, "Boots": 1, "Belt": 1}
const GIFT_ITEMS := [
	{"id":"maid_dress_black","name":"黑白女仆裙装","type":"equipment","equip_slot":"chest","model_parts":{"Clothing1":3},"bonuses":{"defense":1},"stack_max":1,"sell_price":2,"description":"黑色裙身、白色围裙，男女通用。与粉白款分别换装。"},
	{"id":"maid_headpiece","name":"女仆蕾丝头饰","type":"equipment","equip_slot":"head_accessory","model_parts":{"HeadAccessory":1},"bonuses":{},"stack_max":1,"sell_price":1,"description":"独立头饰槽装备，白色褶边与黑色发箍，男女通用。"},
	{"id":"maid_dress","name":"粉白女仆裙装","type":"equipment","equip_slot":"chest","mv_parts":{"Clothing1":2},"model_parts":{"Clothing1":2},"bonuses":{"defense":1},"stack_max":1,"sell_price":2,"description":"可换装的女仆裙与围裙，男女通用。穿戴时遮盖长裤和腰带的外观，卸下后恢复。"},
	{"id":"maid_shoes","name":"女仆皮鞋与丝袜","type":"equipment","equip_slot":"feet","mv_parts":{"Boots":2},"model_parts":{"Boots":2},"bonuses":{},"stack_max":1,"sell_price":2,"description":"皮鞋与配套丝袜共占鞋子槽，穿戴或卸下时一起切换；独立于裙装，男女通用。"},
]
const ITEMS := [
	{"id": "traveler_shirt", "name": "旅行者亚麻上衣", "type": "equipment", "equip_slot": "chest", "mv_parts": {"Clothing1": 1}, "bonuses": {"defense": 1}, "stack_max": 1, "sell_price": 2},
	{"id": "traveler_trousers", "name": "旅行者长裤", "type": "equipment", "equip_slot": "legs", "mv_parts": {"Clothing2": 1}, "bonuses": {"defense": 1}, "stack_max": 1, "sell_price": 2},
	{"id": "traveler_boots", "name": "旅行者短靴", "type": "equipment", "equip_slot": "feet", "mv_parts": {"Boots": 1}, "bonuses": {}, "stack_max": 1, "sell_price": 2},
	{"id": "traveler_belt", "name": "旅行者皮带", "type": "equipment", "equip_slot": "belt", "mv_parts": {"Belt": 1}, "bonuses": {}, "stack_max": 1, "sell_price": 1},
]
