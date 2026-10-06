extends SceneTree
## Export the same requested rest -> natural stand -> sit trajectory as the
## candidate capture. No cloth solver runs and no joint pose is adjusted here.
const Art=preload("res://scripts/asset/art_paths.gd")
const Body=preload("res://scripts/char/female_axis_body.gd")
const Garment=preload("res://scripts/char/character_surface_garment.gd")

func _initialize()->void:call_deferred("run")

func run()->void:
	var output:String=Art.review_path("character_3d/codim_hw_motion")
	if FileAccess.file_exists(output+"/motion.json"):
		push_error("Motion already exported; inspect existing evidence before replacing it");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var body:=Body.new();root.add_child(body);body.initialize();body.set_test_pose("rest")
	var garment:=Garment.new();body.add_child(garment)
	if not garment.initialize(body,"dress_ruffle_layers/item_01"):
		body.free();quit(2);return
	var weights:=FileAccess.get_file_as_bytes(Art.path("characters/equipment/surface_bound/"+garment.garment_id+"/cloth_rest.bin")).to_float32_array()
	assert(weights.size()==garment.rest_points.size()*4)
	var previous:Dictionary={};var frames:Array=[]
	for pose:String in ["stand","sit"]:
		var next:Dictionary=body.POSES[pose]
		for frame in 65:
			var angles:Dictionary={}
			for bone:String in body.rests:angles[bone]=previous.get(bone,Vector3.ZERO).lerp(next.get(bone,Vector3.ZERO),minf(float(frame)/45.0,1.0))
			body.set_angles(angles)
			var bottom:=INF
			for point:Vector3 in body.posed_points:bottom=minf(bottom,point.y)
			body.position=Vector3(0,-bottom,.45 if pose=="stand" else .45*(1.0-minf(float(frame)/45.0,1.0)))
			var offset:Vector3=body.position+body.root_offset
			var stem:=pose+"_%03d"%frame
			var body_file:=FileAccess.open(output+"/"+stem+".obj",FileAccess.WRITE)
			for point:Vector3 in body.posed_points:
				point+=offset
				body_file.store_line("v %.9f %.9f %.9f"%[point.x,point.y,point.z])
			body_file.close()
			var targets:PackedVector3Array=garment.evaluate(body.posed_points)
			var follow:=FileAccess.open(output+"/"+stem+".follow",FileAccess.WRITE)
			follow.store_line("%d %.17f .8"%[targets.size(),1.0/60.0])
			for i in targets.size():
				var target:Vector3=targets[i]+offset
				follow.store_line("%.9f %.9f %.9f %.9f"%[target.x,target.y,target.z,1.0-weights[i*4+3]])
			follow.close()
			assert(body.angles_by_name==angles)
			frames.append({"frame":frames.size(),"pose":pose,"pose_frame":frame,"stem":stem,
				"body_sha256":FileAccess.get_sha256(output+"/"+stem+".obj"),
				"follow_sha256":FileAccess.get_sha256(output+"/"+stem+".follow")})
			if frame%15==0:print("EXPORTED ",stem)
			await process_frame
		previous=next.duplicate()
	var report:=FileAccess.open(output+"/motion.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"scope":"motion and original soft targets only; no simulation or scene colliders",
		"coordinate_space":"world","dt":1.0/60.0,"body_vertices":body.posed_points.size(),
		"cloth_vertices":garment.rest_points.size(),"garment_id":garment.garment_id,
		"body_sha256":garment.binding.body_sha256,"garment_sha256":garment.binding.source_sha256,
		"exporter_sha256":FileAccess.get_sha256("res://tools/export_codim_motion.gd"),"frames":frames},"\t"))
	report.close();body.free();print("Exported motion; not garment acceptance");quit()
