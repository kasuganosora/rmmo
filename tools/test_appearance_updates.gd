extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const MV=preload("res://scripts/char/mv_generator.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	for gender in ["female","male"]:
		var model:=Model.new();root.add_child(model);model.set_process(false)
		var custom:Dictionary={"part_ids":{"FrontHair1":15},"hair_on":true,"hair_row":1206,"skin_on":false,"bust_size":.5}
		model.configure(gender,custom,{})
		model.imported_rig.prepare_hair_choices(model)
		var rig=model.rig;var skeleton=model.skeleton;var adapter=model.imported_rig
		model.play("cast","front_left",true);model.elapsed=.37
		var face:MeshInstance3D=model.gear.Body.filter(func(m):return m.name=="Face")[0]
		var body:MeshInstance3D=model.gear.Body.filter(func(m):return m.name=="Body")[0]
		var shape=body.mesh
		var start:=Time.get_ticks_usec()
		for i in range(100):
			custom.eye_color="#"+Color.from_hsv(i/100.0,.7,.8).to_html(false)
			custom.skin_on=i%2==0;custom.skin_row=MV.default_row("skin")
			custom.hair_row=1001+i;custom.bust_size=i/100.0
			model.configure(gender,custom,{"Clothing1":3 if i%2==0 else 0})
			assert(model.rig==rig and model.skeleton==skeleton and model.imported_rig==adapter)
			assert(body.mesh==shape and model.elapsed==.37 and model.action=="cast")
			var mat=face.get_active_material(0)
			assert(mat.get_shader_parameter("eye_enabled"))
			assert(mat.get_shader_parameter("eye_color")==Color(custom.eye_color))
			assert(body.material_override.get_shader_parameter("skin_color")==model._color(custom,"skin",Color("ffeadb")))
		print(gender," combined edit average ms=",(Time.get_ticks_usec()-start)/100000.0)
		var material=face.get_active_material(0)
		custom.eye_color="";custom.skin_on=false
		model.configure(gender,custom,{})
		assert(face.get_active_material(0)==material)
		assert(not material.get_shader_parameter("eye_enabled") and material.get_shader_parameter("tint_mode")==0)
		model.free()
	var creator=load("res://scenes/character_create.tscn").instantiate();root.add_child(creator)
	await process_frame;await process_frame
	var rig=creator._view_3d.model.rig
	var portrait_rig=creator._portrait_3d.model.rig
	var frames=creator.preview.sprite_frames
	var picker:ColorPickerButton=creator.find_child("EyeColor",true,false)
	for i in range(12):
		picker.color_changed.emit(Color.from_hsv(i/12.0,.7,.8))
		await process_frame;await process_frame
		assert(creator._view_3d.model.rig==rig and creator._portrait_3d.model.rig==portrait_rig)
		assert(creator.preview.sprite_frames==frames)
	creator._on_random()
	await process_frame;await process_frame
	assert(creator._view_3d.model.rig==rig and creator._portrait_3d.model.rig==portrait_rig)
	print("PASS combined edits, eye reset, skin toggles, equipment, stable meshes/animation, live creator and random colours")
	quit()
