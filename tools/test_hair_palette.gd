extends SceneTree
const MV=preload("res://scripts/char/mv_generator.gd")
const Palette=preload("res://scripts/char/hair_palette.gd")
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var entries:=MV.palette_for("hair")
	assert(entries.size()==230)
	for i in range(230):
		var entry:Dictionary=entries[i]
		assert(entry.index==1001+i and entry.label=="K-%03d"%(i+1))
		assert(MV.row_color(entry.index)==entry.color)
		var ramp:Dictionary=MV._row_data(entry.index)
		assert(ramp.lum.size()==256 and ramp.lum[0]>ramp.lum[255])
		var saved:=Customization.new();saved.hair_row=entry.index
		assert(Customization.from_dict(JSON.parse_string(JSON.stringify(saved.to_dict()))).hair_row==entry.index)
	root.size=Vector2i(1200,700);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	var ids:=[1002,1012,1073,1132,1158,1206]
	for col in range(6):
		var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
		view.configure("female",{"part_ids":{"FrontHair1":15},"hair_on":true,"hair_row":ids[col]}, {})
		for mesh in view.model.gear.Hair:
			if mesh.visible:
				assert(mesh.material_override.get_shader_parameter("palette_colored"))
				assert(mesh.material_override.get_shader_parameter("hair_color")==MV.row_color(ids[col]))
		view.play("idle","front",true);view.model.set_process(false);view.model.pose_at(.2)
		view.viewport.size=Vector2i(300,380);view.camera.size=.79;view.camera.position=Vector3(0,1.7,5);view.camera.look_at(Vector3(0,1.69,0))
		var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*200,20);rect.size=Vector2(198,280);root.add_child(rect)
		var label:=Label.new();label.text="K-%03d"%(ids[col]-1000);label.position=Vector2(col*200+70,300);root.add_child(label)
	for i in range(230):
		var rect:=ColorRect.new();rect.color=entries[i].color;rect.position=Vector2(25+(i%30)*38,355+(i/30)*40);rect.size=Vector2(34,32);root.add_child(rect)
	await create_timer(.4).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/character_3d/hair_palette_preview.png")
	var creator=load("res://scenes/character_create.tscn").instantiate();root.add_child(creator)
	await process_frame;await process_frame
	creator._open_palette("hair",creator.hair_color_btn)
	await process_frame;await process_frame
	assert(creator.popup_grid.get_child_count()==230)
	creator.popup_grid.get_child(205).pressed.emit()
	await process_frame;await process_frame
	assert(creator._custom.hair_row==1206 and creator._custom.hair_on)
	assert(creator._view_3d.model.appearance.hair_row==1206)
	print("PASS creator colour picker selection and model propagation")
	print("PASS 230 palette IDs, colours, shading ramp, saved appearance, actual 3D material selection")
	quit()
