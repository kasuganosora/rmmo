extends RefCounted
## Ordinary equipment items: an empty slot really means no underlayer.
const ITEMS=[
	{"id":"underwear_lace_bra_white","name":"白色蕾丝文胸","type":"equipment","equip_slot":"underwear_top","model_parts":{"UnderwearTop":1},"surface_parts":{"female_base_v2":{"UnderwearTop":"underlayer_lace/item_00"}},"bonuses":{},"stack_max":1,"sell_price":1,"description":"独立内衣上装，可替换或卸下。白色蕾丝与不透杯衬。"},
	{"id":"underwear_lace_briefs_white","name":"白色蕾丝三角内裤","type":"equipment","equip_slot":"underwear_bottom","model_parts":{"UnderwearBottom":1},"surface_parts":{"female_base_v2":{"UnderwearBottom":"underlayer_briefs/item_00"}},"bonuses":{},"stack_max":1,"sell_price":1,"description":"独立内衣下装，可替换或卸下。白色蕾丝与布质内衬。"},
]
const DEFAULT_REVIEW_RECIPE={"UnderwearTop":"underlayer_lace/item_00","UnderwearBottom":"underlayer_briefs/item_00"}
