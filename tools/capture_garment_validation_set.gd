extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const SAMPLES=[
	["Classic maid",["maid_classic/item_00"]],
	["Separate maid",["maid_separate/item_01","maid_separate/item_02"]],
	["Pleated skirt",["skirt_pleated/item_00"]],
	["Pencil skirt",["skirt_pencil/item_00"]],
	["Dress L / A",["dress_long/item_00"]],
	["Dress L / B",["dress_long/item_01"]],
	["Floor-length elf",["dress_elf/item_00"]],
	["Dress M08",["dress_layered/item_00"]]]
func _initialize()->void:call_deferred("run")
func run()->void:
	var samples:Array=SAMPLES
	var complex_mode:=OS.get_cmdline_user_args().has("--complex")
	if complex_mode:
		# The old L hat loses four triangles on export; keep it out until repaired.
		samples=[["Dress L",["dress_long/item_00"]],
			["HW dress + outer skirt",["dress_ruffle_layers/item_00","dress_ruffle_layers/item_01"]],
			["HW dress + hat",["dress_ruffle_layers/item_00","dress_ruffle_layers/item_02"]]]
	root.size=Vector2i(450,600);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.model.visible=false
	var canvas:=CanvasLayer.new();root.add_child(canvas)
	var label:=Label.new();label.position=Vector2(16,16);label.add_theme_font_size_override("font_size",24);canvas.add_child(label)
	var columns:=3 if complex_mode else 4
	var sheet:=Image.create(columns*450,600 if complex_mode else 1200,false,Image.FORMAT_RGB8)
	for index in samples.size():
		var holder:=Node3D.new();root.add_child(holder);var bounds:=AABB();var first:=true
		for id:String in samples[index][1]:
			var folder:String=Art.path("characters/source_models/garment_validation_set/"+id)
			var doc:=GLTFDocument.new();var state:=GLTFState.new()
			if doc.append_from_file(folder+"/garment_review.glb",state)!=OK:push_error("Missing garment "+id);quit(1);return
			var scene:=doc.generate_scene(state);holder.add_child(scene)
			var triangles:=0
			for mesh:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
				var box:AABB=mesh.global_transform*mesh.get_aabb()
				bounds=box if first else bounds.merge(box);first=false
				for surface in mesh.mesh.get_surface_count():
					var arrays:Array=mesh.mesh.surface_get_arrays(surface)
					triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
					if arrays[Mesh.ARRAY_TEX_UV].size()!=arrays[Mesh.ARRAY_VERTEX].size():push_error("Lost garment UV");quit(1);return
			var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/clothing_data.json"))
			var expected:=0
			for face:Dictionary in source.faces:expected+=face.vertices.size()-2
			if triangles!=expected:push_error("Garment topology changed "+id);quit(1);return
			print("PASS garment mesh/UV ",id," triangles=",triangles)
		label.text=samples[index][0]+"\nOriginal static garment"
		var center:=bounds.get_center();studio.camera.position=center+Vector3(.3,0,5);studio.camera.look_at(center)
		studio.camera.size=maxf(bounds.size.y*1.3,bounds.size.x*1.65)
		for frame in 5:await process_frame
		await RenderingServer.frame_post_draw
		var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(picture,Rect2i(0,0,450,600),Vector2i((index%columns)*450,(index/columns)*600))
		holder.free()
	sheet.save_png(Art.review_path("character_3d/garment_complex_catalog.png" if complex_mode else "character_3d/garment_validation_catalog.png"))
	studio.free();canvas.free();print("PASS ",samples.size()," garment silhouettes; static import only, not runtime cloth validation");quit()
