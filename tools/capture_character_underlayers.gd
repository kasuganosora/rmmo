extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Wardrobe=preload("res://scripts/char/character_surface_wardrobe.gd")
const RECIPE={"UnderwearTop":"underlayer_lace/item_00","UnderwearBottom":"underlayer_briefs/item_00"}
func _initialize()->void:call_deferred("run")
func triples(points:PackedVector3Array)->Array:
	var result:Array=[]
	for p:Vector3 in points:result.append([p.x,p.y,p.z])
	return result
func run()->void:
	root.size=Vector2i(700,900);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.show_new_base()
	var body:Node3D=studio.regional_preview
	var wardrobe:Node3D=studio.surface_wardrobe
	if not wardrobe.set_equipment(RECIPE):quit(2);return
	var report:Array=[]
	var folder:String=Art.review_path("character_3d/underlayer_lace_03")
	DirAccess.make_dir_recursive_absolute(folder)
	for pose:String in ["stand","reach","step","sit","lie","lie_relaxed"]:
		body.set_test_pose(pose);studio.update_pose_helpers()
		if studio.chair:studio.chair.visible=false
		var input:Dictionary=body.angles_by_name.duplicate(true)
		for slot:String in RECIPE:
			var garment:Node3D=wardrobe.garments[slot]
			var points:PackedVector3Array=garment.evaluate(body.posed_points)
			var snapshot:={"garment_id":garment.garment_id,"garment":triples(points),"body":triples(body.posed_points),"floor":-body.position.y,"scene_boxes":[]}
			var file:=FileAccess.open(folder+"/"+pose+"_"+slot+".json",FileAccess.WRITE);file.store_string(JSON.stringify(snapshot));file.close()
			report.append({"pose":pose,"slot":slot,"strain":garment.strain(points),"triangles":garment.triangle_count})
		for view:String in ["front","side","back"]:
			var target:=Vector3(0,1.03,0)
			var offset:=Vector3(0,0,5) if view=="front" else (Vector3(5,0,.3) if view=="side" else Vector3(0,0,-5))
			studio.camera.size=2.15
			if pose=="sit":target.y=.72;offset.y=1.4
			if pose.begins_with("lie"):
				target=Vector3(0,.2,.15);studio.camera.size=2.3
				offset=Vector3(.1,5,.1) if view=="front" else (Vector3(4,1,.1) if view=="side" else Vector3(.1,-5,.1))
			studio.camera.position=target+offset;studio.camera.look_at(target)
			if pose.begins_with("lie"):studio.floor_mesh.visible=false
			for frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+pose+"_"+view+".png")
		assert(body.angles_by_name==input,"Underlayers must not alter the actor pose")
		print("CAPTURED underlayers ",pose)
	var output:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t"));output.close()
	studio.free();print("PASS underlayer capture completed; geometry and visual review still required");quit()
