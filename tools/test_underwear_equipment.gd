extends SceneTree
const Equipment=preload("res://scripts/net/combat/equipment.gd")
const Appearance=preload("res://scripts/char/character_view_3d.gd")
const Paperdoll=preload("res://scripts/char/paperdoll_look.gd")
var failed:=0
func check(value:bool,label:String)->void:
	if not value:failed+=1;push_error(label)
	else:print("PASS ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	await process_frame
	var server=load("res://scripts/net/net.gd").server()
	if server==null:quit(2);return
	var catalog=server.item_catalog
	server.inventory.clear();server.equipment.clear()
	var ids:=["underwear_lace_bra_white","underwear_lace_briefs_white"]
	for id:String in ids:server.inventory.add_item(id,1)
	check(Equipment.SLOT_IDS.has("underwear_top") and Equipment.SLOT_IDS.has("underwear_bottom"),"registered independent equipment slots")
	var invalid:Dictionary=server.try_equip_item(ids[0],"underwear_bottom")
	check(not invalid.get("ok",false) and server.inventory.get_qty(ids[0])==1,"wrong slot rejected without consuming item")
	for id:String in ids:
		var result:Dictionary=server.try_equip_item(id)
		check(result.get("ok",false),"equip from bag: "+id)
		check(result.actions.any(func(action):return action.type=="equipment_update"),"existing equipment_update transport")
	var recipe:Dictionary=Appearance.equipment_parts("female",server.equipment.snapshot(),catalog)
	check(recipe.UnderwearTop==1 and recipe.UnderwearBottom==1,"legacy renderer receives optional layers")
	check(recipe.SurfaceEquipment==preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE,"new body consumes same item snapshot")
	# Exercise a real replacement transaction with distinct inventory identity,
	# using the same asset to isolate transfer semantics from asset selection.
	var replacement:Dictionary=catalog.get_item(ids[0]).duplicate(true)
	replacement.id="test_lace_bra_alternative";catalog.register_item(replacement)
	server.inventory.add_item(replacement.id,1)
	check(server.try_equip_item(replacement.id).get("ok",false),"replace top independently")
	check(server.inventory.get_qty(ids[0])==1 and server.equipment.get_item_in("underwear_bottom")==ids[1],"old top returns to bag; bottom unchanged")
	check(server.try_unequip_item("underwear_top").get("ok",false),"unequip top")
	var partial:Dictionary=Appearance.equipment_parts("female",server.equipment.snapshot(),catalog)
	check(partial.UnderwearTop==0 and partial.UnderwearBottom==1 and not partial.SurfaceEquipment.has("UnderwearTop"),"empty top survives appearance translation")
	check(server.try_unequip_item("underwear_bottom").get("ok",false),"unequip bottom")
	var empty:Dictionary=Appearance.equipment_parts("female",server.equipment.snapshot(),catalog)
	check(empty.UnderwearTop==0 and empty.UnderwearBottom==0 and empty.SurfaceEquipment.is_empty(),"both empty means no underlayers")
	server.inventory.add_item("traveler_shirt",1);server.try_equip_item("traveler_shirt")
	empty=Appearance.equipment_parts("female",server.equipment.snapshot(),catalog)
	check(empty.UnderwearTop==0 and empty.UnderwearBottom==0 and empty.SurfaceEquipment.is_empty(),"outerwear does not restore removed underwear")
	check(Paperdoll.equipment_to_surface_parts("male_base_v2",[{"item_id":ids[0]}],catalog).is_empty(),"female assets not attached to an incompatible body")
	print("UNDERWEAR EQUIPMENT ","PASS" if failed==0 else "FAIL")
	quit(0 if failed==0 else 1)
