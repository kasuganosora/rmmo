extends RefCounted
## Stable recipe IDs, selected by body resource version across all appearance UI.
const SOURCE_OPTIONS={201:"长发",202:"短发",203:"马尾"}
static func options(gender:String,body_model:String)->Dictionary:
	if gender=="female" and body_model=="female_base_v2":
		var result:Dictionary=SOURCE_OPTIONS.duplicate();result[0]="无";return result
	var result:Dictionary={1:"原始短发" if gender=="male" else "原始盘发"}
	result.merge(preload("res://scripts/char/character_hair_3d.gd").OPTIONS)
	result[0]="无";return result
static func initial(gender:String,body_model:String,previous:int)->int:
	var choices:=options(gender,body_model)
	if choices.has(previous):return previous
	return 201 if body_model=="female_base_v2" and gender=="female" else 1
static func random_choice(gender:String,body_model:String)->int:
	var choices:Array=options(gender,body_model).keys();choices.erase(0)
	return choices.pick_random()
