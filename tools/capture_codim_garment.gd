extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
var snapshot_path:=""
func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--snapshot="):snapshot_path=argument.trim_prefix("--snapshot=")
	call_deferred("run")
func run()->void:
	if snapshot_path.is_empty():push_error("Explicit --snapshot required");quit(2);return
	var capture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(snapshot_path))
	if capture.substep!=capture.substeps:push_error("Visual capture requires a completed motion frame");quit(2);return
	var name:String=snapshot_path.get_file().get_basename()
	if not name.is_valid_ascii_identifier():push_error("Invalid capture name");quit(2);return
	root.size=Vector2i(720,900)
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.show_new_base()
	var body:Node3D=studio.regional_preview
	var pose:String=capture.motion.pose;var frame:int=capture.motion.pose_frame
	var previous:Dictionary={} if pose=="stand" else body.POSES.stand
	var next:Dictionary=body.POSES[pose];var angles:Dictionary={}
	for bone:String in body.rests:angles[bone]=previous.get(bone,Vector3.ZERO).lerp(next.get(bone,Vector3.ZERO),minf(float(frame)/45.0,1.0))
	body.set_angles(angles)
	var first:Array=capture.body[0]
	var offset:Vector3=Vector3(first[0],first[1],first[2])-body.posed_points[0]
	body.position=offset
	var error:=0.0
	for i in body.posed_points.size():
		var p:Array=capture.body[i]
		error=maxf(error,(body.posed_points[i]+offset).distance_to(Vector3(p[0],p[1],p[2])))
	if error>.00001:push_error("Rendered body differs from requested input: "+str(error));studio.free();quit(2);return
	studio.set_surface_outfit(8)
	var garment:Node3D=studio.surface_wardrobe.garments.Clothing2
	var points:=PackedVector3Array()
	for p:Array in capture.garment:points.append(Vector3(p[0],p[1],p[2])-offset)
	var normals:=PackedVector3Array();normals.resize(points.size())
	for face:Dictionary in garment.data.faces:
		for i in range(1,face.vertices.size()-1):
			var a:int=face.vertices[0];var b:int=face.vertices[i];var c:int=face.vertices[i+1]
			var normal:Vector3=-(points[b]-points[a]).cross(points[c]-points[a])
			for id:int in [a,b,c]:normals[id]+=normal
	var height:int=ceili(float(points.size())/512)
	var positions:=PackedFloat32Array();positions.resize(512*height*4)
	var normal_data:=positions.duplicate()
	for i in points.size():
		for j in 3:positions[i*4+j]=points[i][j];normal_data[i*4+j]=normals[i].normalized()[j]
	var pt:=ImageTexture.create_from_image(Image.create_from_data(512,height,false,Image.FORMAT_RGBAF,positions.to_byte_array()))
	var nt:=ImageTexture.create_from_image(Image.create_from_data(512,height,false,Image.FORMAT_RGBAF,normal_data.to_byte_array()))
	for i in garment.mesh_instance.mesh.get_surface_count():
		var material:ShaderMaterial=garment.mesh_instance.mesh.surface_get_material(i)
		material.set_shader_parameter("cloth_positions",pt);material.set_shader_parameter("cloth_normals",nt);material.set_shader_parameter("simulate",true)
	# Reconstruct the same fixed chair, without touching the body's requested pose.
	var furniture:=Node3D.new();studio.add_child(furniture)
	for box:Dictionary in capture.scene_boxes:
		var rows:Array=box.local_from_cloth;var axes:Array=[]
		for row:Array in rows:axes.append(Vector3(row[0],row[1],row[2]))
		var transform:=Transform3D(Basis(axes[0],axes[1],axes[2]),axes[3]).affine_inverse()
		var mesh:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=Vector3(box.size[0],box.size[1],box.size[2]);mesh.mesh=shape;mesh.transform=transform;furniture.add_child(mesh)
	for view:String in ["front","side","back"]:
		studio.camera.size=2.5;studio.camera.position={"front":Vector3(0,1,5),"side":Vector3(5,1,0),"back":Vector3(0,1,-5)}[view]
		studio.camera.look_at(Vector3(0,.9,.2))
		for wait_frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Art.review_path("character_3d/"+name+"_"+view+".png"))
		if view=="back":
			# Visibility-only companion image; never changes simulated colliders.
			furniture.visible=false
			for wait_frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(Art.review_path("character_3d/"+name+"_back_unobstructed.png"))
			furniture.visible=true
	studio.free();print("Rendered reference snapshot; geometry audit remains independent");quit()
