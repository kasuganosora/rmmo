extends RefCounted
## Approved female body is the normal game recipe, not a review-only toggle.
static func apply(character:Dictionary)->void:
	if str(character.get("gender",""))!="female":return
	var original:Dictionary=character.get("customization",{}) if character.get("customization",{}) is Dictionary else {}
	if original.get("body_model","")=="female_base_v2":return
	if not character.has("legacy_customization"):character["legacy_customization"]=original.duplicate(true)
	var recipe:Dictionary=original.duplicate(true)
	recipe["body_model"]="female_base_v2"
	var parts:Dictionary=recipe.get("part_ids",{}).duplicate(true) if recipe.get("part_ids",{}) is Dictionary else {}
	parts["FrontHair1"]=preload("res://scripts/char/character_hairstyles.gd").initial("female","female_base_v2",int(parts.get("FrontHair1",201)))
	recipe["part_ids"]=parts
	character["customization"]=recipe
