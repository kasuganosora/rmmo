extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Candidate=preload("res://scripts/char/garment_candidate_cloth.gd")
var captured:=PackedByteArray()
var received:=false
var output_prefix:="candidate_hw_"
func _initialize()->void:call_deferred("run")
func receive(bytes:PackedByteArray)->void:captured=bytes;received=true
func read_gpu(candidate:Node)->void:
	call_deferred("receive",candidate.solver._rd.buffer_get_data(candidate.solver._positions_buffer))
func run()->void:
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
	candidate.continuous_self_contacts=OS.get_cmdline_user_args().has("--self-contact")
	candidate.edge_contacts=OS.get_cmdline_user_args().has("--edge-contacts")
	if OS.get_cmdline_user_args().has("--convergence"):candidate.constraint_iterations=24
	if OS.get_cmdline_user_args().has("--baseline-iterations"):candidate.constraint_iterations=12
	if not candidate.initialize(garment,objects):push_error(candidate.frame_error);studio.free();quit(2);return
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
			if not candidate.advance(1.0/60.0):push_error(candidate.frame_error);studio.free();quit(2);return
			await process_frame
			await RenderingServer.frame_post_draw
			assert(body.angles_by_name==angles,"Cloth must not modify the requested joint pose")
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
