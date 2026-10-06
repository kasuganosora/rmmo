extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(240).timeout.connect(func():push_error("Creation regression timed out");quit(2))
	var ui=load("res://scenes/character_create.tscn").instantiate()
	root.add_child(ui)
	for frame in 4:await process_frame
	var choice:OptionButton=ui.find_child("HairstyleSelect",true,false)
	assert(choice!=null and choice.item_count==4)
	assert(ui.find_child("BustSize",true,false)==null,"Do not expose an unsupported shape slider")
	assert(ui._view_3d.model.axis_rig!=null and ui._portrait_3d.model.axis_rig!=null)
	var main_hair:Node3D=ui._view_3d.model.axis_rig.hair
	var portrait_hair:Node3D=ui._portrait_3d.model.axis_rig.hair
	assert(main_hair.key_light!=null and portrait_hair.key_light!=null)
	assert(main_hair.key_light!=portrait_hair.key_light,"Isolated previews must not share another world's key light")
	assert(main_hair.key_light.get_world_3d()==main_hair.get_world_3d())
	assert(portrait_hair.key_light.get_world_3d()==portrait_hair.get_world_3d())
	main_hair.key_light.rotation.y+=0.4
	for frame in 2:await process_frame
	assert(main_hair.materials[0].get_shader_parameter("source_key_enabled"))
	assert(main_hair.materials[0].get_shader_parameter("source_key_direction").is_equal_approx(main_hair.key_light.global_transform.basis.z.normalized()))
	var main_body:int=ui._view_3d.model.axis_rig.body.get_instance_id()
	var portrait_body:int=ui._portrait_3d.model.axis_rig.body.get_instance_id()
	for key:String in ["bust_size","waist_width","hip_size","nose_width","height"]:
		var slider:HSlider=ui.find_child("Shape_"+key,true,false)
		assert(slider!=null)
		slider.value=30
		for frame in 3:await process_frame
		assert(is_equal_approx(ui._view_3d.model.axis_rig.body.shape_values[key],-.3 if key=="height" else .3))
		assert(ui._view_3d.model.axis_rig.body.shape_values==ui._portrait_3d.model.axis_rig.body.shape_values)
		assert(ui._view_3d.model.axis_rig.body.get_instance_id()==main_body)
	for id in [203,0,202,201]:
		var index:=choice.get_item_index(id)
		choice.select(index);choice.item_selected.emit(index)
		for frame in 3:await process_frame
		assert(ui._view_3d.model.axis_rig.hair.selected==id)
		assert(ui._portrait_3d.model.axis_rig.hair.selected==id)
		assert(ui._view_3d.model.axis_rig.body.get_instance_id()==main_body)
		assert(ui._portrait_3d.model.axis_rig.body.get_instance_id()==portrait_body)
		var saved:=Customization.from_dict(JSON.parse_string(JSON.stringify(ui._custom.to_dict())))
		assert(saved.body_model=="female_base_v2" and saved.part_ids.FrontHair1==id)
		assert(saved.body_shapes==ui._custom.body_shapes)
	for i in 4:
		ui._on_random()
		for frame in 3:await process_frame
		assert(ui._part_ids.FrontHair1 in [201,202,203])
		assert(not ui._custom.body_shapes.is_empty())
		assert(ui._view_3d.model.axis_rig.body.shape_values==ui._custom.body_shapes)
		assert(ui._portrait_3d.model.axis_rig.body.shape_values==ui._custom.body_shapes)
		for key:String in Customization.Shapes.RANGES:
			var slider:HSlider=ui.find_child("Shape_"+key,true,false)
			assert(absf(slider.value-float(ui._custom.body_shapes.get(key,0))*100*(-1 if key=="height" else 1))<=.51)
	ui.find_child("ResetBodyShapes",true,false).pressed.emit()
	for frame in 3:await process_frame
	assert(ui._custom.body_shapes.is_empty())
	assert(ui._view_3d.model.axis_rig.body.shape_values.is_empty() and ui._portrait_3d.model.axis_rig.body.shape_values.is_empty())
	assert(ui._view_3d.model.axis_rig.body.get_instance_id()==main_body)
	ui._set_gender("male")
	for frame in 3:await process_frame
	assert(ui._custom.body_model=="" and ui._part_ids.FrontHair1<200)
	ui._set_gender("female")
	for frame in 3:await process_frame
	assert(ui._custom.body_model=="female_base_v2" and ui._part_ids.FrontHair1 in [201,202,203])
	ui.free()
	for frame in 4:await process_frame
	print("PASS actual creation UI: versioned native options, main/portrait identity, remove/switch, random, recipe roundtrip and gender compatibility")
	quit()
