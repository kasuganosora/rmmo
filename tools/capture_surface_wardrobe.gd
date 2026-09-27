extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Body=preload("res://scripts/char/female_axis_body.gd")
const Wardrobe=preload("res://scripts/char/character_surface_wardrobe.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(480,700);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	studio.show_new_base()
	var body:Node3D=studio.regional_preview
	var wardrobe:=Wardrobe.new();body.add_child(wardrobe);wardrobe.configure(body)
	var catalog:Array=JSON.parse_string(FileAccess.get_file_as_string(Art.path("characters/equipment/surface_bound/catalog.json")))
	var report:Array=[]
	var canvas:=CanvasLayer.new();root.add_child(canvas);var label:=Label.new();label.position=Vector2(12,12);canvas.add_child(label)
	# Every source item retains all original triangles, including the old GLB hat's four lost triangles.
	for entry:Dictionary in catalog:
		assert(wardrobe.set_equipment({"Clothing1":entry.id}))
		var garment:Node3D=wardrobe.garments.Clothing1
		var expected:=0
		for face:Dictionary in garment.data.faces:expected+=face.vertices.size()-2
		assert(garment.triangle_count==expected)
		var rest:PackedVector3Array=garment.evaluate(body.rest_points)
		var error:=0.0
		for i in rest.size():error=maxf(error,rest[i].distance_to(garment.rest_points[i]))
		assert(error<.00001)
		body.set_test_pose("elbow")
		var skeleton_id:int=body.skeleton.get_instance_id()
		assert(wardrobe.set_equipment({"Clothing1":entry.id}))
		assert(wardrobe.garments.Clothing1==garment and body.skeleton.get_instance_id()==skeleton_id and body.pose_name=="elbow")
		assert(not wardrobe.set_equipment({"Clothing1":"../invalid"}))
		assert(wardrobe.garments.Clothing1==garment)
		body.set_angles({"hip":Vector3(23,-37,14)})
		var points:PackedVector3Array=body.read_gpu_points()
		var moved:PackedVector3Array=garment.evaluate(points)
		var delta:Transform3D=body.skeleton.get_bone_global_pose(body.skeleton.find_bone("hip"))*body.rests.hip.affine_inverse()
		for i in moved.size():assert(moved[i].distance_to(delta*rest[i])<.0001)
		report.append({"id":entry.id,"triangles":expected,"rest_error":error,"poses":{}})
		for pose:String in ["stand","elbow","reach","step","sit","lie"]:
			body.set_test_pose(pose)
			var posed:PackedVector3Array=garment.evaluate(body.posed_points)
			for p:Vector3 in posed:assert(p.is_finite())
			report[-1].poses[pose]=garment.strain(posed)
		print("PASS original shape/topology, rigid transform, finite poses, slot lifecycle: ",entry.id)
	assert(wardrobe.set_equipment({}));assert(wardrobe.get_child_count()==0)
	var output:=FileAccess.open(Art.review_path("character_3d/surface_wardrobe_report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"));output.close()
	var sheet:=Image.create(480*4,700*2,false,Image.FORMAT_RGB8)
	for index in range(1,studio.GARMENT_LOOKS.size()):
		assert(wardrobe.set_equipment(studio.GARMENT_LOOKS[index][1]))
		body.set_test_pose("stand");studio.update_pose_helpers()
		studio.camera.size=2.4;studio.camera.position=Vector3(1.8,1.1,5);studio.camera.look_at(Vector3(0,.95,0))
		label.text=studio.GARMENT_LOOKS[index][0]+"\nSurface binding / no cloth simulation"
		for frame in 4:await process_frame
		await RenderingServer.frame_post_draw
		var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(picture,Rect2i(0,0,480,700),Vector2i(((index-1)%4)*480,((index-1)/4)*700))
	sheet.save_png(Art.review_path("character_3d/surface_wardrobe_standing.png"))
	assert(wardrobe.set_equipment(studio.GARMENT_LOOKS[2][1]))
	var poses_sheet:=Image.create(480*3,700*2,false,Image.FORMAT_RGB8)
	var poses:Array=["stand","elbow","reach","step","sit","lie"]
	for index in poses.size():
		body.set_test_pose(poses[index]);studio.update_pose_helpers()
		studio.camera.size=2.7;studio.camera.position=Vector3(3,1.2,5);studio.camera.look_at(Vector3(0,.9,0))
		if poses[index]=="lie":studio.camera.size=3.3;studio.camera.position=Vector3(4,1.2,.3);studio.camera.look_at(Vector3(0,.2,.16))
		label.text=poses[index]+" / surface binding diagnostic"
		for frame in 4:await process_frame
		await RenderingServer.frame_post_draw
		var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
		poses_sheet.blit_rect(picture,Rect2i(0,0,480,700),Vector2i((index%3)*480,(index/3)*700))
	poses_sheet.save_png(Art.review_path("character_3d/surface_wardrobe_poses.png"))
	studio.free();canvas.free();print("PASS surface attachment infrastructure; strain report is NOT a cloth/collision acceptance");quit()
