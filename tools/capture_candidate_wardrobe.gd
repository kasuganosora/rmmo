extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Candidate=preload("res://scripts/char/garment_candidate_cloth.gd")
var captured:=PackedByteArray()
var received:=false
var output_prefix:="candidate_hw_"
var trace_frames:=false
var trace_until:=-1
var trace_stage_frame:=-1
var stage_bytes:=PackedByteArray()
var stage_labels:Array=[]
func receive_stages(bytes:PackedByteArray,labels:Array)->void:stage_bytes=bytes;stage_labels=labels;received=true
func read_stages(candidate:Node)->void:
	var labels:Array=candidate.solver.review_stage_labels.duplicate()
	var bytes:PackedByteArray=candidate.solver._rd.buffer_get_data(candidate.solver._review_trace_buffer,0,labels.size()*candidate.solver._particle_count*16)
	call_deferred("receive_stages",bytes,labels)
func _initialize()->void:call_deferred("run")
func receive(bytes:PackedByteArray)->void:captured=bytes;received=true
func read_gpu(candidate:Node)->void:
	call_deferred("receive",candidate.solver._rd.buffer_get_data(candidate.solver._positions_buffer))
func run()->void:
	trace_frames=OS.get_cmdline_user_args().has("--trace-frames")
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--trace-until="):
			trace_until=int(argument.trim_prefix("--trace-until="));trace_frames=true
		if argument.begins_with("--trace-stage-frame="):
			trace_stage_frame=int(argument.trim_prefix("--trace-stage-frame="));trace_frames=true
	var shader_manifest:Dictionary=preload("res://tools/gpu_shader_review_manifest.gd").collect()
	if shader_manifest.is_empty():quit(2);return
	root.size=Vector2i(600,800)
	if OS.get_cmdline_user_args().has("--self-contact"):output_prefix="candidate_self_hw_"
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.show_new_base()
	var body:Node3D=studio.regional_preview
	# A cloth point needs a contact margin on both sides of the body/seat gap.
	studio.seat_contact_clearance=2.0*Candidate.CONTACT_MARGIN
	body.set_test_pose("sit");studio.update_pose_helpers()
	var objects:Array[MeshInstance3D]=[]
	for child in studio.chair.get_children():
		if child is MeshInstance3D:objects.append(child)
	objects.append(studio.floor_mesh)
	body.set_test_pose("rest");studio.set_surface_outfit(8)
	var garment:Node3D=studio.surface_wardrobe.garments.Clothing2
	var candidate:=Candidate.new();garment.add_child(candidate)
	candidate.review_stage_trace=trace_stage_frame>=0
	candidate.source_bending=OS.get_cmdline_user_args().has("--source-bending")
	candidate.interpolate_targets=OS.get_cmdline_user_args().has("--interpolate-targets")
	candidate.continuous_self_contacts=OS.get_cmdline_user_args().has("--self-contact")
	if OS.get_cmdline_user_args().has("--contact-iterations"):candidate.self_contact_iterations=4;output_prefix="candidate_self4_hw_"
	if OS.get_cmdline_user_args().has("--contact-structure"):candidate.self_contact_structural_projection=true;candidate.self_contact_iterations=4;output_prefix="candidate_self4s_hw_"
	if OS.get_cmdline_user_args().has("--self-edges"):candidate.self_edge_contacts=true;candidate.continuous_self_contacts=true;candidate.self_contact_iterations=4;candidate.self_contact_structural_projection=true;output_prefix="candidate_selfedge_body_hw_"
	if OS.get_cmdline_user_args().has("--eight-contacts"):candidate.self_contact_iterations=8;output_prefix="candidate_selfedge8_hw_"
	if OS.get_cmdline_user_args().has("--mass-balance"):candidate.self_contact_mass_balance=true;output_prefix="candidate_selfmass_hw_"
	if OS.get_cmdline_user_args().has("--body-tangents"):candidate.self_contact_body_tangents=true
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--review-id="):
			var review_id:=argument.trim_prefix("--review-id=")
			if review_id.is_empty() or not review_id.is_valid_ascii_identifier():push_error("Invalid review ID");studio.free();quit(2);return
			output_prefix="candidate_"+review_id+"_hw_"
	var manifest_file:=FileAccess.open(Art.review_path("character_3d/"+output_prefix+"shader_manifest.json"),FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(shader_manifest,"\t"));manifest_file.close()
	candidate.edge_contacts=OS.get_cmdline_user_args().has("--edge-contacts")
	if OS.get_cmdline_user_args().has("--convergence"):candidate.constraint_iterations=24
	if OS.get_cmdline_user_args().has("--baseline-iterations"):candidate.constraint_iterations=12
	if not candidate.initialize(garment,objects):push_error(candidate.frame_error);studio.free();quit(2);return
	if trace_frames:
		var trace_dir:String=Art.review_path("character_3d/"+output_prefix+"trace")
		DirAccess.make_dir_recursive_absolute(trace_dir)
		var info:=FileAccess.open(trace_dir+"/topology.json",FileAccess.WRITE)
		info.store_string(JSON.stringify({"garment_id":garment.garment_id,"control_to_particle":Array(candidate.control_to_particle),"shader_manifest":shader_manifest}));info.close()
	for frame in 5:await process_frame
	var previous:Dictionary={};var reports:Array=[]
	for name in (["stand"] if OS.get_cmdline_user_args().has("--stand-only") else ["stand","sit"]):
		var next:Dictionary=body.POSES[name]
		for frame in 65:
			var angles:Dictionary={}
			for bone:String in body.rests:angles[bone]=previous.get(bone,Vector3.ZERO).lerp(next.get(bone,Vector3.ZERO),minf(float(frame)/45.0,1.0))
			body.set_angles(angles)
			var bottom:=INF
			for point:Vector3 in body.posed_points:bottom=minf(bottom,point.y)
			body.position.y=-bottom
			# Approach the stationary chair from in front, then lower onto its seat.
			body.position.z=.45 if name=="stand" else .45*(1.0-minf(float(frame)/45.0,1.0))
			candidate.solver.review_trace_active=frame==trace_stage_frame
			if not candidate.advance(1.0/60.0):push_error(candidate.frame_error);studio.free();quit(2);return
			await process_frame
			await RenderingServer.frame_post_draw
			assert(body.angles_by_name==angles,"Cloth must not modify the requested joint pose")
			if trace_frames:
				received=false;RenderingServer.call_on_render_thread(read_gpu.bind(candidate))
				while not received:await process_frame
				var trace:=FileAccess.open(Art.review_path("character_3d/"+output_prefix+"trace/"+name+"_%03d.f32"%frame),FileAccess.WRITE)
				trace.store_buffer(captured);trace.close()
				if frame==trace_stage_frame:
					received=false;RenderingServer.call_on_render_thread(read_stages.bind(candidate))
					while not received:await process_frame
					var folder:String=Art.review_path("character_3d/"+output_prefix+"trace/")
					var stages:=FileAccess.open(folder+name+"_%03d.stages.f32"%frame,FileAccess.WRITE);stages.store_buffer(stage_bytes);stages.close()
					var labels:=FileAccess.open(folder+name+"_%03d.stages.json"%frame,FileAccess.WRITE);labels.store_string(JSON.stringify(stage_labels));labels.close()
				if trace_until>=0 and frame>=trace_until:
					studio.free()
					for cleanup in 4:await process_frame
					print("Partial diagnostic trace completed; not a full pose capture");quit();return
			if frame%15==0:print("CANDIDATE ",name," frame ",frame)
			if name=="sit" and frame in [15,30,45]:
				reports.append(await snapshot(candidate,body,garment,"sit_"+str(frame),objects))
		previous=next.duplicate()
		reports.append(await snapshot(candidate,body,garment,name,objects))
		print(reports[-1])
		studio.camera.size=2.7;studio.camera.position=Vector3(3,1.2,5);studio.camera.look_at(Vector3(0,.9,0))
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Art.review_path("character_3d/"+output_prefix+name+".png"))
		for view:String in ["front","side","back","hands"]:
			studio.camera.size=1.0 if view=="hands" else 2.7
			studio.camera.position={"front":Vector3(0,1.2,5),"side":Vector3(5,1.2,0),"back":Vector3(0,1.2,-5),"hands":Vector3(1.5,1.1,3)}[view]
			studio.camera.look_at(Vector3(0,.85,body.position.z) if view=="hands" else Vector3(0,.9,0))
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(Art.review_path("character_3d/"+output_prefix+name+"_"+view+".png"))
			if view=="back" and studio.chair:
				# Additional visibility-only inspection; collision geometry and pose
				# stay unchanged and no solver step runs between these two images.
				studio.chair.visible=false
				for frame in 3:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(Art.review_path("character_3d/"+output_prefix+name+"_back_unobstructed.png"))
				studio.chair.visible=true
	var report:=FileAccess.open(Art.review_path("character_3d/"+output_prefix+"report.json"),FileAccess.WRITE);report.store_string(JSON.stringify(reports,"\t"));report.close()
	studio.free()
	for frame in 4:await process_frame
	print("Candidate capture finished; inspect geometry audit before acceptance");quit()

func snapshot(candidate:Node,body:Node3D,garment:Node3D,label:String,objects:Array[MeshInstance3D])->Dictionary:
	received=false
	RenderingServer.call_on_render_thread(read_gpu.bind(candidate))
	while not received:await process_frame
	var values:=captured.to_float32_array();var points:=PackedVector3Array()
	for index in candidate.control_to_particle:points.append(Vector3(values[index*4],values[index*4+1],values[index*4+2]))
	var garment_points:Array=[];var body_points:Array=[];var boxes:Array=[]
	for point:Vector3 in points:garment_points.append([point.x,point.y,point.z])
	for point:Vector3 in body.posed_points:
		point+=body.root_offset
		body_points.append([point.x,point.y,point.z])
	for object:MeshInstance3D in objects:
		if not object.mesh is BoxMesh:continue
		var local:Transform3D=object.global_transform.affine_inverse()*candidate.global_transform
		var matrix:Array=[]
		for axis:Vector3 in [local.basis.x,local.basis.y,local.basis.z,local.origin]:matrix.append([axis.x,axis.y,axis.z])
		var size:Vector3=object.mesh.size
		boxes.append({"local_from_cloth":matrix,"size":[size.x,size.y,size.z]})
	var file:=FileAccess.open(Art.review_path("character_3d/"+output_prefix+label+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"garment_id":garment.garment_id,"garment":garment_points,"body":body_points,"floor":-body.position.y,"scene_boxes":boxes}));file.close()
	return {"pose":label,"strain":garment.strain(points),"body_triangles":candidate.body_triangles.size()/3,"scene_triangles":candidate.scene_triangles.size()/3}
