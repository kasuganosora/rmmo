extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Custom=preload("res://scripts/char/customization.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(700,900);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.show_new_base()
	var folder:String=Art.review_path("character_3d/body_colors_01");DirAccess.make_dir_recursive_absolute(folder)
	var palette:Array=Custom.MV.palette_for("skin")
	var reference_images:Dictionary={};var report:Array=[]
	for variant:Dictionary in [{"id":"source","recipe":{}},{"id":"warm","recipe":{"skin_row":int(palette[palette.size()/2].index),"eye_color":"#589d72"}},{"id":"blue","recipe":{"skin_on":false,"eye_color":"#62aabb"}},{"id":"restored","recipe":{}}]:
		studio.set_body_colors(variant.recipe)
		for light in 2:
			if studio.studio_mode!=(light==0):studio.toggle_lighting()
			for view:String in ["face","body"]:
				var center:=Vector3(0,1.60,0) if view=="face" else Vector3(0,1.03,0)
				studio.camera.size=.45 if view=="face" else 2.15;studio.camera.position=center+Vector3(.25,0,5);studio.camera.look_at(center)
				for frame in 4:await process_frame
				await RenderingServer.frame_post_draw
				var image:Image=root.get_texture().get_image();var key:String=("studio" if light==0 else "game")+"_"+view
				image.save_png(folder+"/"+variant.id+"_"+key+".png")
				if variant.id=="source":reference_images[key]=image.get_data()
				if variant.id=="restored":
					var same:bool=reference_images[key]==image.get_data();report.append({"view":key,"restore_pixels_identical":same})
		print("CAPTURE body colour variant=",variant.id," recipe=",variant.recipe)
	var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	studio.free()
	for frame in 4:await process_frame
	print("PASS colour captures completed; inspect both lighting conditions");quit()
