extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var server=root.get_node("MockServer")
	server._session_user="maid_equipment_test"
	server._accounts[server._session_user]={"password":"test","characters":[{"id":991,"name":"换装测试","gender":"female","level":1,"look_id":"1","class_id":"adventurer","customization":{}}]}
	server.enter_world(991)
	var result:Array=await server.enter_world_ready
	assert(result[0],"Actual world entry must succeed")
	for id in ["maid_dress","maid_shoes","maid_dress_black","maid_headpiece"]:assert(server.inventory.has_item(id,1),"Spawn gifts must be in the bag")
	assert(server.equipment.get_item_in("chest")=="traveler_shirt","Gifts must not replace equipped starter clothing")
	for id in ["maid_dress","maid_shoes"]:assert(server.equipment.try_equip_from_bag(server.inventory,id).get("ok",false))
	assert(server.inventory.has_item("traveler_shirt",1) and server.inventory.has_item("traveler_boots",1))
	var model:=Model.new();root.add_child(model);model.set_process(false)
	var names:Array[String]=[]
	for gender in ["female","male"]:
		model.configure(gender,{"bust_size":.8},View.equipment_parts(gender,server.equipment.snapshot(),server.item_catalog))
		assert(model.skeleton.get_bone_count()==67)
		var current:Array[String]=[]
		for i in range(model.skeleton.get_bone_count()):current.append(model.skeleton.get_bone_name(i))
		current.sort()
		if names.is_empty():names=current
		else:assert(names==current,"Male/female must share the same bone names")
		for mesh in model.gear.Clothing1:assert(mesh.visible==(mesh.name=="MaidDress"))
		for mesh in model.gear.Boots:assert(mesh.visible in [true,false]);assert(mesh.visible==str(mesh.name).begins_with("Maid"))
		for mesh in model.gear.Clothing2:assert(not mesh.visible)
		assert(model.gear.HeadAccessory.size()==1,"Headpiece must be a separate weighted mesh")
		var headpiece:MeshInstance3D=model.gear.HeadAccessory[0]
		var dress:MeshInstance3D=model.gear.Clothing1.filter(func(m):return m.name=="MaidDress")[0]
		model.set_equipment({"Clothing1":3,"Boots":2,"HeadAccessory":1})
		assert(dress.visible and dress.material_override.get_shader_parameter("black_variant"))
		assert(headpiece.visible and headpiece.skin!=null)
		for mesh in model.gear.Clothing2:assert(not mesh.visible,"Black dress must also hide trousers")
		var stocking:MeshInstance3D=model.gear.Boots.filter(func(m):return m.name=="MaidStockings")[0]
		assert(stocking.material_override is ShaderMaterial,"Stockings need the skin-aware fabric material")
		model.set_equipment({"Clothing1":2,"Boots":2})
		assert(not headpiece.visible and not dress.material_override.get_shader_parameter("black_variant"))
		# Shoes and stockings belong exclusively to feet, independent of the dress.
		model.set_equipment({"Clothing1":2,"Boots":null})
		for mesh in model.gear.Boots:assert(not mesh.visible,"Unequip feet must remove both shoes and stockings")
		for mesh in model.gear.Clothing1:assert(mesh.visible==(mesh.name=="MaidDress"))
		model.set_equipment({"Clothing1":1,"Clothing2":1,"Boots":2})
		for mesh in model.gear.Boots:assert(mesh.visible==str(mesh.name).begins_with("Maid"),"Maid footwear must work without the dress")
		for mesh in model.gear.Clothing1:assert(mesh.visible==(mesh.name!="MaidDress"))
		model.set_equipment({"Clothing1":2,"Boots":1})
		for mesh in model.gear.Boots:assert(mesh.visible==not str(mesh.name).begins_with("Maid"),"Replacing shoes must remove the old stockings")
		model.play("dash","back_left",true)
		for i in range(20):model._process(1.0/60)
		var skeleton=model.skeleton;var phase:float=model.elapsed
		model.set_equipment({"Clothing1":1,"Clothing2":1,"Boots":1,"Belt":1})
		assert(model.skeleton==skeleton and is_equal_approx(model.elapsed,phase))
		for mesh in model.gear.Clothing1:assert(mesh.visible==(mesh.name!="MaidDress"))
		for mesh in model.gear.Clothing2:assert(mesh.visible)
		print("PASS ",gender," same item IDs, shared bones, maid equip/restore without animation reset")
	for id in ["traveler_shirt","traveler_boots"]:assert(server.equipment.try_equip_from_bag(server.inventory,id).get("ok",false))
	for id in ["maid_dress","maid_shoes"]:assert(server.inventory.has_item(id,1))
	assert(server.equipment.try_equip_from_bag(server.inventory,"maid_dress_black").get("ok",false))
	assert(server.equipment.try_equip_from_bag(server.inventory,"maid_headpiece").get("ok",false))
	assert(server.equipment.get_item_in("head_accessory")=="maid_headpiece")
	assert(server.equipment.get_item_in("head")=="","Head accessory must not consume the helmet slot")
	var mapped:=View.equipment_parts("female",server.equipment.snapshot(),server.item_catalog)
	assert(mapped.get("Clothing1")==3 and mapped.get("HeadAccessory")==1)
	assert(server.equipment.try_unequip_to_bag(server.inventory,"head_accessory").get("ok",false))
	assert(server.equipment.get_item_in("chest")=="maid_dress_black" and server.inventory.has_item("maid_headpiece",1))
	print("PASS actual spawn grants and reversible bag/equipment transfers")
	quit()
