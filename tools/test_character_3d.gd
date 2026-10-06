extends SceneTree
const View = preload("res://scripts/char/character_view_3d.gd")
const Starter = preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var view:=View.new();root.add_child(view)
	for gender in ["male","female","young_male","young_female"]:
		view.configure(gender,{},Starter.PARTS)
		assert(view.model.skeleton.get_bone_count()==(67 if view.model.imported_rig!=null else 15))
		var body:Array=view.model.gear.Body.duplicate()
		for action in view.model.ACTIONS:
			for direction in view.model.YAW:
				view.play(action,direction,true);view.model.pose_at(.35)
				for i in range(view.model.skeleton.get_bone_count()):assert(view.model.skeleton.get_bone_pose_rotation(i).is_finite())
		for category in Starter.PARTS:
			var parts:Dictionary=Starter.PARTS.duplicate();parts[category]=null
			view.model.set_equipment(parts)
			for mesh in view.model.gear[category]:assert(not mesh.visible)
			for mesh in body:assert(is_instance_valid(mesh) and mesh.visible)
			view.model.set_equipment(Starter.PARTS)
			for mesh in view.model.gear[category]:
				assert(mesh.visible==(int(mesh.get_meta("equipment_variant",1))==1 and mesh.name!="Stockings"))
		if view.model.imported_rig==null:assert(view.model.gear.Clothing2.size()==5,"one hips mesh and exactly two pairs of leg segments")
		else:
			assert(view.model.gear.Clothing1.size()>0 and view.model.gear.Clothing2.size()>0 and view.model.gear.Boots.size()>0)
			assert(view.model.gear.Belt.size()==1,"Adult belt is one fitted mesh, not a ring and floating buckle")
			for mesh in view.model.gear.Belt:
				assert(mesh.skin!=null and not mesh.get_parent() is BoneAttachment3D,"Belt must deform with the waistband")
			for mesh in view.model.gear.Body:assert(mesh.skin!=null,"Imported body must retain weighted skinning")
			var expressions:=0
			for mesh in view.model.gear.Body:expressions+=mesh.mesh.get_blend_shape_count()
			assert(expressions>=50,"Face expressions must survive the male derivative and export")
			view.model.set_equipment({})
			for mesh in view.model.gear.BaseBottom:assert(mesh.visible)
			view.model.set_equipment({"Boots":1})
			for mesh in view.model.gear.Boots:
				if mesh.name=="Stockings":assert(mesh.visible,"Starter stockings return when trousers are removed")
			view.model.set_equipment(Starter.PARTS)
			for mesh in view.model.gear.Boots:
				if mesh.name=="Stockings":assert(not mesh.visible,"Trousers cover the starter stocking layer")
			for mesh in view.model.gear.BaseBottom:assert(not mesh.visible,"Base shorts must not intersect equipped trousers")
		print("PASS 3D body ",gender," eight directions/actions, independent gear, two articulated legs")
	var scene=load("res://scenes/character_create.tscn").instantiate()
	var player:=CharacterBody2D.new()
	player.set_script(load("res://scripts/game/player.gd"))
	var anim:=AnimatedSprite2D.new();anim.name="Anim";player.add_child(anim);anim.owner=player;anim.unique_name_in_owner=true
	root.add_child(player);player.set_physics_process(false)
	player.setup("1","male",{})
	player.set_facing_dir(7);player.play_character_action("sit_chair",true)
	player.character_3d.model.elapsed=.4
	var snapshot:Array=[]
	for item in Starter.ITEMS:snapshot.append({"slot":item.equip_slot,"item_id":item.id})
	var catalog=load("res://scripts/net/combat/item_catalog.gd").new();catalog.load_catalog()
	player.apply_gear_look({"gender":"male","customization":{}},snapshot,catalog)
	assert(player.character_3d.model.action=="sit_chair")
	assert(player.character_3d.model.direction=="back_left")
	assert(is_equal_approx(player.character_3d.model.elapsed,.4))
	player.apply_gear_look({"gender":"male"},[],catalog)
	for mesh in player.character_3d.model.gear.Clothing2:assert(not mesh.visible)
	print("PASS actual player adapter: gear snapshot, unequip, facing and action phase preserved")
	root.add_child(scene)
	await process_frame;await process_frame
	assert(scene._view_3d!=null and not scene.preview.visible)
	var shirt:CheckButton=scene.find_children("Clothing1","CheckButton",true,false)[0]
	shirt.button_pressed=false
	await process_frame;await process_frame
	for mesh in scene._view_3d.model.gear.Clothing1:assert(not mesh.visible)
	print("PASS creator uses live 3D preview and removable garments")
	view.configure("male",{"part_ids":{"FrontHair1":0}},Starter.PARTS)
	for mesh in view.model.gear.Hair:assert(not mesh.visible)
	view.configure("male",{"hair_on":true,"hair_row":3},Starter.PARTS)
	assert(view.model.gear.Hair[0].get_active_material(0) is ShaderMaterial,"Imported emission textures must support palette tinting")
	print("PASS imported hair removal, palette shader, base layers and preserved expressions")
	quit()
