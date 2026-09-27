extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Document=preload("res://scripts/world3d/world_document.gd")
const IO=preload("res://scripts/world3d/gltf_map_io.gd")
const Paths=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func label(parent:Node3D,text:String,at:Vector3)->void:
	var node:=Label3D.new();node.text=text;node.font_size=38;node.pixel_size=.0025;node.position=at;node.billboard=BaseMaterial3D.BILLBOARD_ENABLED;parent.add_child(node)
func bounds(model:Node3D)->AABB:
	var lo:=Vector3(INF,INF,INF);var hi:=-lo
	for category in ["Body","Hair"]:
		for mesh:MeshInstance3D in model.gear[category]:
			if not mesh.visible:continue
			var transforms:Array[Transform3D]=[]
			if mesh.skin!=null:
				for binding in mesh.skin.get_bind_count():
					var bone:int=model.skeleton.find_bone(mesh.skin.get_bind_name(binding))
					if bone<0:bone=mesh.skin.get_bind_bone(binding)
					transforms.append(model.skeleton.global_transform*model.skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(binding))
			for surface in mesh.mesh.get_surface_count():
				var data:Array=mesh.mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=data[Mesh.ARRAY_VERTEX]
				var bones=data[Mesh.ARRAY_BONES];var weights=data[Mesh.ARRAY_WEIGHTS]
				var stride:int=bones.size()/vertices.size() if bones!=null else 0
				for i in vertices.size():
					var p:Vector3=mesh.global_transform*vertices[i]
					if stride>0 and not transforms.is_empty():
						p=Vector3.ZERO
						for j in stride:p+=(transforms[bones[i*stride+j]]*vertices[i])*weights[i*stride+j]
					lo=lo.min(p);hi=hi.max(p)
	return AABB(lo,hi-lo)
func run()->void:
	root.size=Vector2i(1200,800);root.content_scale_size=root.size
	var document:=Document.new();document.add_box("block",Vector3(0,.5,0),Vector3.ONE)
	var source:Node3D=document.build();assert(source.get_meta("extras").rmmo_unit=="m")
	var path:String=Paths.review_path("vrchat_scale/one_meter.glb")
	assert(IO.save_scene(source,path)==OK);source.free()
	var scene:Node3D=IO.load_scene(path);root.add_child(scene)
	var mesh:MeshInstance3D=scene.find_children("*","MeshInstance3D",true,false)[0]
	var world_box:AABB=mesh.global_transform*mesh.mesh.get_aabb()
	assert(world_box.size.is_equal_approx(Vector3.ONE),"1m editor object must remain 1m through GLB export/import")
	assert(is_equal_approx(world_box.position.y,0) and is_equal_approx(world_box.end.y,1))
	mesh.create_trimesh_collision()
	await physics_frame;await physics_frame
	var hit:Dictionary=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,2,0),Vector3(0,-1,0)))
	assert(not hit.is_empty() and is_equal_approx(hit.position.y,1),"Physics surface must also be exactly one meter high")
	var report:Dictionary={"unit":"m","roundtrip_cube_size":[world_box.size.x,world_box.size.y,world_box.size.z],"physics_top_m":hit.position.y,"characters":{}}
	for gender in ["female","male"]:
		var model=Model.create(gender,{},preload("res://scripts/char/starter_equipment.gd").PARTS);scene.add_child(model);model.set_process(false)
		model.position.x=-1.15 if gender=="female" else 1.15;model.pose_at(0)
		var box:AABB=bounds(model)
		report.characters[gender]={"body_and_hair_height_m":box.size.y,"lowest_vertex_y_m":box.position.y,"highest_vertex_y_m":box.end.y,"model_asset_scale":model.rig.scale.y}
		assert(box.size.y>1.5 and box.size.y<2.2,"Actor must use human-scale meters rather than source centimeters")
		label(scene,"%s  %.3f m"%[gender,box.size.y],Vector3(model.position.x,box.end.y+.18,0))
	label(scene,"1.000 m",Vector3(0,1.15,.05))
	var floor:=MeshInstance3D.new();var ground:=BoxMesh.new();ground.size=Vector3(20,.04,20);floor.mesh=ground;floor.position.y=-.025;scene.add_child(floor)
	for i in 21:
		var tick:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=Vector3(.24 if i%10==0 else .12,.005,.015);tick.mesh=shape;tick.position=Vector3(-2.0,i*.1,0);scene.add_child(tick)
		if i%5==0:label(scene,"%.1f"%(i*.1),Vector3(-2.3,i*.1,0))
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("899ba6");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.6;scene.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,32,0);scene.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.9;scene.add_child(camera);camera.position=Vector3(0,1.65,6);camera.look_at(Vector3(-.3,1.0,0))
	var file:=FileAccess.open(Paths.review_path("vrchat_scale/rmmo-measurements.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report));print("PASS meter-space document, GLB roundtrip, physics surface and actor scale")
	if DisplayServer.get_name()!="headless":
		for i in 4:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Paths.review_path("vrchat_scale/scale-comparison.png"))
	scene.free();quit()
