extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var studio=load("res://scenes/character_skin_studio.tscn").instantiate();root.add_child(studio)
	await process_frame
	var body:Node3D=studio.regional_preview
	var body_id:int=body.get_instance_id();var skeleton_id:int=body.skeleton.get_instance_id()
	studio.set_surface_outfit(2)
	assert(studio.surface_wardrobe.garments.size()==5)
	var inner:Node3D=studio.surface_wardrobe.garments.UnderwearBottom
	assert(not inner.cloth_enabled and not inner.enable_cloth())
	assert(studio.set_underlayer("UnderwearTop",""))
	studio.set_surface_outfit(8)
	assert(not studio.surface_wardrobe.garments.has("UnderwearTop"))
	assert(studio.surface_wardrobe.garments.UnderwearBottom==inner)
	assert(studio.set_underlayer("UnderwearBottom",""))
	studio.set_surface_outfit(2)
	assert(not studio.surface_wardrobe.garments.has("UnderwearBottom"))
	assert(studio.set_underlayer("UnderwearTop","underlayer_lace/item_00"))
	var top:Node3D=studio.surface_wardrobe.garments.Clothing1
	studio.set_surface_outfit(2);assert(studio.surface_wardrobe.garments.Clothing1==top)
	studio.pose_selector.select(3);studio.pose_amount.set_value_no_signal(.5);studio.apply_body_pose()
	assert(body.pose_name=="step")
	var pose:Dictionary=body.angles_by_name.duplicate(true);var position:Vector3=body.position
	# A small attached accessory exercises the actual warm-start lifecycle quickly.
	assert(studio.surface_wardrobe.set_equipment({"HeadAccessory":"maid_separate/item_00"}))
	assert(studio.surface_wardrobe.warm_start_cloth())
	assert(body.angles_by_name==pose and body.position.is_equal_approx(position) and body.pose_name=="step")
	assert(body.get_instance_id()==body_id and body.skeleton.get_instance_id()==skeleton_id)
	var first:Node3D=studio.surface_wardrobe.garments.HeadAccessory
	var second=preload("res://scripts/char/character_surface_garment.gd").new();body.add_child(second)
	assert(second.initialize(body,"maid_separate/item_00") and second.enable_cloth())
	assert(first.cloth!=second.cloth and first.cloth.position_texture!=second.cloth.position_texture)
	assert(first.mesh_instance.mesh.surface_get_material(0)!=second.mesh_instance.mesh.surface_get_material(0))
	var frozen:PackedByteArray=second.cloth.last_positions.duplicate()
	body.set_test_pose("elbow");first.cloth.step(body)
	assert(second.cloth.last_positions==frozen,"Cloth buffers leaked between garment instances")
	second.free()
	studio.configure_body("male");assert(not studio.garment_selector.visible and not studio.cloth_toggle.get_parent().visible)
	studio.show_new_base();assert(studio.garment_selector.visible and studio.cloth_toggle.get_parent().visible)
	assert(studio.surface_wardrobe.set_equipment({}) and studio.surface_wardrobe.get_child_count()==0)
	studio.free();print("PASS surface wardrobe UI, transactional slots, warm start pose preservation, independent cloth buffers and cleanup");quit()
