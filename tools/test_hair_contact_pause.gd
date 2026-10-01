extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
	view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":201}}, {})
	view.model.set_process(false)
	var body=view.model.axis_rig.body;var spring=view.model.axis_rig.hair.spring
	assert(not spring.contacts.is_empty())
	spring.set_contacts_enabled(true)
	var previous:Transform3D=spring.contacts[0].node.transform
	spring.set_contacts_enabled(false)
	body.set_angles({"head":Vector3(0,35,20)});spring.sync_contacts(body)
	assert(spring.contacts[0].node.transform==previous)
	spring.set_contacts_enabled(true)
	assert(not spring.contacts[0].node.transform.is_equal_approx(previous))
	var enabled:Transform3D=spring.contacts[0].node.transform
	spring.sync_contacts(body,true)
	assert(spring.contacts[0].node.transform.is_equal_approx(enabled),"Enable did not immediately restore current collider transforms")
	view.free();await process_frame
	print("PASS disabled hair contacts stop updates; re-enable immediately restores current transforms")
	quit()
