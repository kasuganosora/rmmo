extends SceneTree
const T=preload("res://scripts/world3d/terrain_surface.gd")
const P=preload("res://scripts/world_editor/terrain_local_publish.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;push_error(label)
	else:print("PASS ",label)
func _initialize()->void:call_deferred("run")
func triangles(faces:PackedVector3Array)->Dictionary:
	var result:Dictionary={}
	for i in range(0,faces.size(),3):
		var key:=var_to_bytes(faces.slice(i,i+3)).hex_encode();result[key]=result.get(key,0)+1
	return result
func run()->void:
	var r:=preload("res://tools/test_terrain_incremental.gd").fixture()
	for z in 65:
		for x in 65:r.terrain_mesh.heights[z*65+x]=sin(x*.11)*cos(z*.17)*1.5
	for z in range(20,24):
		for x in range(43,47):r.terrain_mesh.holes[z*64+x]=true
	var node:=MeshInstance3D.new();node.mesh=T.mesh(r,null);root.add_child(node)
	var body:=StaticBody3D.new();root.add_child(body)
	check(P.initialize(node,r,body),"bounded collision initialization")
	var blocker:=StaticBody3D.new();var box:=CollisionShape3D.new();box.shape=BoxShape3D.new();box.shape.size=Vector3(2,2,2)
	blocker.add_child(box);blocker.position=Vector3(-8,5,-8);root.add_child(blocker)
	var total:=0;var all_bytes:=0;var native_id:=node.mesh.get_instance_id();var shared:Mesh=node.mesh;var shared_arrays:Array=Cpu.capture(shared).surfaces
	for i in 6:
		var args:={"id":r.uuid,"mode":["raise","lower","smooth","flatten","raise","lower"][i],"points":[[3,3]],"radius":3.,"strength":.2,"target_height":.1}
		var next:Dictionary=T.stroke(r,args).record
		var packet:=P.prepare(node,next,{})
		check(not packet.is_empty(),"local packet %s"%i)
		if packet.is_empty():continue
		P.publish(node,packet,{})
		if i==0:
			check(node.mesh!=shared and Cpu.capture(shared).surfaces==shared_arrays,"private storage preserves shared original")
			native_id=node.mesh.get_instance_id()
		else:check(node.mesh.get_instance_id()==native_id,"same GPU mesh identity %s"%i)
		var reference:=T.mesh(next,null);var bytes:=0
		for slot in 2:
			var actual:=RenderingServer.mesh_get_surface(node.mesh.get_rid(),slot)
			var expected:=RenderingServer.mesh_get_surface(reference.get_rid(),slot)
			for key in ["vertex_data","attribute_data","index_data"]:
				check(actual[key]==expected[key],"GPU buffer exact %s/%s/%s"%[i,slot,key])
				bytes+=expected[key].size()
		var cpu:Mesh=Cpu.capture(node.mesh)
		check(cpu.surfaces==T.arrays(next),"canonical CPU arrays %s"%i)
		check(node.custom_aabb==T.bounds(next) and cpu.bounds==T.bounds(next),"culling and authoring bounds %s"%i)
		var soup:=PackedVector3Array()
		for child:CollisionShape3D in body.get_children():soup.append_array(child.shape.get_faces())
		check(triangles(soup)==triangles(cpu.collision_faces()),"exact bounded collider triangles %s"%i)
		check(P.last_work.collision_blocks<P.last_work.total_blocks,"only touched collision blocks %s"%i)
		if i>0:
			var immediate:=P.intersect_ray(node.get_world_3d().direct_space_state,PhysicsRayQueryParameters3D.create(Vector3(3,10,3),Vector3(3,-5,3)),root)
			check(not immediate.is_empty() and absf(immediate.position.y-T.sample(next,Vector3(3,0,3)))<.0001,"same-frame picking revision %s"%i)
			var blocked_query:=PhysicsRayQueryParameters3D.create(Vector3(-8,10,-8),Vector3(-8,-10,-8))
			var blocked:=P.intersect_ray(node.get_world_3d().direct_space_state,blocked_query,root)
			check(not blocked.is_empty() and blocked.collider==blocker,"native obstacle still occludes current terrain %s"%i)
			blocked_query.exclude=[blocker.get_rid()]
			var visible:=P.intersect_ray(node.get_world_3d().direct_space_state,blocked_query,root)
			check(not visible.is_empty() and visible.collider==body,"CPU fallback respects exclusions %s"%i)
			blocked_query.collision_mask=2
			check(P.intersect_ray(node.get_world_3d().direct_space_state,blocked_query,root).is_empty(),"CPU fallback respects layers %s"%i)
		await physics_frame;await physics_frame
		var hit:=node.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3,10,3),Vector3(3,-5,3)))
		check(not hit.is_empty() and absf(hit.position.y-T.sample(next,Vector3(3,0,3)))<.0001,"picking sees current revision %s"%i)
		if i>0:total+=packet.bytes;all_bytes+=bytes
		r=next
	var hole:Dictionary=T.stroke(r,{"id":r.uuid,"mode":"hole","points":[[3,3]],"radius":2.}).record
	check(P.prepare(node,hole,{}).is_empty(),"topology change uses complete rebuild")
	root.size=Vector2i(960,720);root.content_scale_size=root.size;root.use_taa=false
	# Disable temporal camera jitter for a pixel-exact same-frame geometry oracle.
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-25,0);light.shadow_enabled=true;root.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.18,.22,.28)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.5;root.add_child(environment)
	var full:=MeshInstance3D.new();full.mesh=T.mesh(r,null);root.add_child(full);full.hide()
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.22,.3,.16);material.roughness=.9
	node.material_override=material;full.material_override=material
	var image_results:Array=[]
	for view:Array in [["near",Vector3(9,7,10),Vector3(3,0,3)],["middle",Vector3(30,24,30),Vector3.ZERO],["far",Vector3(65,50,65),Vector3.ZERO],["hole",Vector3(20,12,-4),Vector3(13,0,-10)]]:
		camera.look_at_from_position(view[1],view[2])
		node.show();full.hide();await process_frame;await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
		var partial:=root.get_texture().get_image()
		node.hide();full.show();await process_frame;await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
		var rebuilt:=root.get_texture().get_image()
		var same:bool=partial.get_data()==rebuilt.get_data();check(same,"same camera/light raster %s"%view[0])
		partial.save_png("D:/code/rmmo_runtime/review_artifacts/terrain_incremental_20261017/"+view[0]+"_partial.png")
		rebuilt.save_png("D:/code/rmmo_runtime/review_artifacts/terrain_incremental_20261017/"+view[0]+"_full.png")
		image_results.append({"view":view[0],"exact_pixels":same})
	var record:={"raster_method":"960x720, MSAA unchanged, TAA disabled equally for deterministic pixels, same camera/material/light/exposure, no actor", "images":image_results,"failures":failures,"partial_bytes":total,"full_bytes":all_bytes,"last_work":P.last_work}
	FileAccess.open("D:/code/rmmo_runtime/review_artifacts/terrain_incremental_20261017/publish.json",FileAccess.WRITE).store_string(JSON.stringify(record,"  "))
	print("TERRAIN_LOCAL_PUBLISH ",JSON.stringify(record));node.free();body.free();blocker.free();quit(1 if failures else 0)
