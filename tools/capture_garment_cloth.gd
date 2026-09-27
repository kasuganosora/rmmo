extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(480,700);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.show_new_base()
	var body:Node3D=studio.regional_preview
	body.set_test_pose("rest")
	var complex_mode:=OS.get_cmdline_user_args().has("--complex")
	var prefix:="cloth_hw_" if complex_mode else "cloth_"
	studio.set_surface_outfit(8 if complex_mode else 2)
	var wardrobe:Node3D=studio.surface_wardrobe
	for garment:Node3D in wardrobe.garments.values():
		assert(garment.enable_cloth())
		var actual:PackedVector3Array=garment.cloth.read_points()
		var reference:PackedVector3Array=garment.evaluate(body.posed_points)
		for i in actual.size():assert(actual[i].distance_to(reference[i])<.00001,"Cloth GPU target differs from CPU surface reference")
	var canvas:=CanvasLayer.new();root.add_child(canvas);var label:=Label.new();label.position=Vector2(12,12);canvas.add_child(label)
	var sheet:=Image.create(480*3,700*2,false,Image.FORMAT_RGB8)
	var report:Array=[]
	var names:Array=["stand","elbow","reach","step","sit","lie"]
	if complex_mode:names=["stand","step","sit"]
	if OS.get_cmdline_user_args().has("--stand-only"):names=["stand"]
	var previous:Dictionary={}
	for index in names.size():
		var next:Dictionary=body.POSES[names[index]]
		for frame in 100:
			var angles:Dictionary={}
			for bone:String in body.rests:angles[bone]=previous.get(bone,Vector3.ZERO).lerp(next.get(bone,Vector3.ZERO),minf(float(frame)/60.0,1.0))
			body.set_angles(angles)
			# Body pose transitions retain the same world root; ground placement below
			# is a test fixture adjustment, not an avatar locomotion implementation.
			body.posed_points=body.read_gpu_points()
			var bottom:=INF
			for p:Vector3 in body.posed_points:bottom=minf(bottom,p.y)
			body.position.y=-bottom;body.world_offset=body.position
			wardrobe.step_cloth()
			assert(body.angles_by_name==angles,"Cloth contact must not change the wearer's requested pose")
			if frame%20==0:await process_frame
		previous=next.duplicate();body.pose_name=names[index];studio.update_pose_helpers()
		var skirt:Node3D=wardrobe.garments.Clothing2
		var points:PackedVector3Array=skirt.cloth.read_points()
		for p:Vector3 in points:assert(p.is_finite() and p.length()<5)
		var dump:=FileAccess.open(Art.review_path("character_3d/"+prefix+names[index]+".json"),FileAccess.WRITE)
		var garment_points:Array=[];var body_points:Array=[]
		for p:Vector3 in points:garment_points.append([p.x,p.y,p.z])
		for p:Vector3 in body.posed_points:body_points.append([p.x,p.y,p.z])
		dump.store_string(JSON.stringify({"garment_id":skirt.garment_id,"garment":garment_points,"body":body_points,"floor":-body.position.y}));dump.close()
		report.append({"pose":names[index],"strain":skirt.strain(points),"solve_ms":skirt.cloth.last_ms,"wearer_pose_unchanged":body.angles_by_name==angles_for_pose(body,next)})
		print(report[-1])
		studio.camera.size=2.7;studio.camera.position=Vector3(3,1.2,5);studio.camera.look_at(Vector3(0,.9,0))
		if names[index]=="lie":studio.camera.size=3.3;studio.camera.position=Vector3(4,1.2,.3);studio.camera.look_at(Vector3(0,.2,.16))
		label.text=names[index]+" / experimental cloth contact"
		for frame in 4:await process_frame
		await RenderingServer.frame_post_draw
		var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
		picture.save_png(Art.review_path("character_3d/"+prefix+names[index]+".png"))
		sheet.blit_rect(picture,Rect2i(0,0,480,700),Vector2i((index%3)*480,(index/3)*700))
	sheet.save_png(Art.review_path("character_3d/"+prefix+"poses.png"))
	var output:=FileAccess.open(Art.review_path("character_3d/"+prefix+"report.json"),FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t"));output.close()
	studio.free();canvas.free();print("PASS cloth finite transitions; inspect strain and visual contact before acceptance");quit()
func angles_for_pose(body:Node3D,pose:Dictionary)->Dictionary:
	var result:Dictionary={}
	for bone:String in body.rests:result[bone]=pose.get(bone,Vector3.ZERO)
	return result
