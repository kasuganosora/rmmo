extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Starter=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func check(condition:bool,message:String)->void:
	if not condition:push_error(message);quit(1);assert(condition,message)
func run()->void:
	var data:=Customization.from_dict({"eye_color":"#247de8","bust_size":.83})
	var restored:=Customization.from_dict(JSON.parse_string(JSON.stringify(data.to_dict())))
	check(restored.eye_color=="#247de8" and is_equal_approx(restored.bust_size,.83),"Saved appearance must round-trip")
	check(Customization.from_dict({}).bust_size==.5,"Old characters retain original proportions")
	check(Customization.valid_bust_size(INF)==.5 and Customization.valid_bust_size(2)==1,"Invalid sizes are bounded")
	check(Customization.valid_eye_color("#zzzzzz")=="","Invalid eye colours rejected")
	var models:Array=[]
	for size in [0.0,.5,1.0]:
		var model:=Model.new();root.add_child(model);model.configure("female",{"eye_color":"#247de8","bust_size":size},Starter.PARTS);models.append(model)
		var face:MeshInstance3D=model.gear.Body.filter(func(m):return m.name=="Face")[0]
		check(face.get_active_material(0).get_shader_parameter("eye_enabled"),"Iris shader active")
		check(face.mesh.get_blend_shape_count()>50,"Expressions survive body changes")
		for category in ["Body","Clothing1","BaseTop"]:
			for mesh in model.gear[category]:check(mesh.skin!=null,"Clothes and body remain weighted")
	var small:Mesh=models[0].gear.Body.filter(func(m):return m.name=="Body")[0].mesh
	var original:Mesh=models[1].gear.Body.filter(func(m):return m.name=="Body")[0].mesh
	var large:Mesh=models[2].gear.Body.filter(func(m):return m.name=="Body")[0].mesh
	var a:PackedVector3Array=small.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
	var b:PackedVector3Array=original.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var c:PackedVector3Array=large.surface_get_blend_shape_arrays(0)[1][Mesh.ARRAY_VERTEX]
	var changed:=0
	for i in range(b.size()):
		check(a[i].is_finite() and c[i].is_finite(),"Deformation must remain finite")
		if absf(c[i].z-b[i].z)>.01:
			check(a[i].z<b[i].z and c[i].z>b[i].z,"Chest depth responds monotonically")
			changed+=1
	check(changed>20,"Slider must actually change body geometry")
	var model:Node3D=models[2];model.play("cast","front_left",true);model.elapsed=.3
	var shape:Mesh=model.gear.Body.filter(func(m):return m.name=="Body")[0].mesh
	model.configure("female",{"eye_color":"#247de8","bust_size":1.0},{})
	check(model.gear.Body.filter(func(m):return m.name=="Body")[0].mesh==shape and model.elapsed==.3,"Unequipping preserves shape and action phase")
	var old_rig=model.rig
	var start:=Time.get_ticks_usec()
	for i in range(101):
		model.configure("female",{"eye_color":"#247de8","bust_size":i/100.0},{})
		check(model.rig==old_rig,"Slider must reuse the rig")
		for mesh in model.imported_rig.bust_instances:
			check(is_equal_approx(mesh.get_blend_shape_value(1),maxf(0.0,(i/100.0-.5)*2)),"Body and clothing weights update together")
	print("BUST average ms=",(Time.get_ticks_usec()-start)/101000.0)
	for row in [1206,1132,1012]:
		model.configure("female",{"eye_color":"#247de8","bust_size":1.0,"hair_on":true,"hair_row":row,"part_ids":{"FrontHair1":1}},{})
		for mesh in model.imported_rig.original_hair:
			for surface in range(mesh.mesh.get_surface_count()):
				var mat=mesh.get_active_material(surface)
				if mat is ShaderMaterial:check(mat.get_shader_parameter("tint")==preload("res://scripts/char/mv_generator.gd").row_color(row),"Original updo accepts repeated colour updates")
	var creator=load("res://scenes/character_create.tscn").instantiate();root.add_child(creator)
	await process_frame;await process_frame
	check(creator.find_child("ClothRow",true,false)==null,"Clothing colour control removed")
	var slider:HSlider=creator.find_child("BustSize",true,false)
	var picker:ColorPickerButton=creator.find_child("EyeColor",true,false)
	check(slider!=null and picker!=null,"Creator exposes both controls")
	slider.value=80;picker.color_changed.emit(Color("247de8"))
	await process_frame;await process_frame
	check(is_equal_approx(creator._custom.bust_size,.8) and creator._custom.eye_color=="#247de8","Controls update saved customization")
	check(creator._view_3d.model.appearance.eye_color=="#247de8","Preview consumes the same saved appearance")
	print("PASS saved appearance, defaults, validation, iris shader, body/clothes deformation, unequip, creator controls")
	quit()
