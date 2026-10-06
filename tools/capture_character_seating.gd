extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Paths=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func box(parent:Node3D,size:Vector3,position:Vector3,color:Color)->void:
	var mesh:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=size;mesh.mesh=shape
	var material:=StandardMaterial3D.new();material.albedo_color=color;mesh.material_override=material
	parent.add_child(mesh);mesh.position=position
func run()->void:
	root.size=Vector2i(650,800);root.content_scale_size=root.size
	var stage:=Node3D.new();root.add_child(stage)
	box(stage,Vector3(10,.05,10),Vector3(0,-.026,0),Color("c6c6bf"))
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("899ba6")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.6;root.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,32,0);root.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.0;root.add_child(camera)
	var model=Model.create("female",{},{});stage.add_child(model);model.set_process(false)
	for gender in ["female","male"]:
		model.configure(gender,{}, {"Clothing1":2,"Boots":2,"HeadAccessory":1})
		var rest:Dictionary=model.imported_rig.rest_positions;var scale_y:float=model.rig.scale.y
		var height:float=(rest.shinL.y-model.imported_rig.garment_motion.leg_radius)*scale_y
		var width:float=model.imported_rig.garment_motion.pelvis_size.x*2.5*scale_y
		var depth:float=rest.thighL.distance_to(rest.shinL)*scale_y
		var chair:=Node3D.new();stage.add_child(chair)
		box(chair,Vector3(width,.055,depth),Vector3(0,height-.0275,.02),Color("eeeeee"))
		for x in [-1,1]:
			for z in [-1,1]:box(chair,Vector3(.045,height,.045),Vector3(x*(width*.5-.03),height*.5,.02+z*(depth*.5-.03)),Color("dddddd"))
		box(chair,Vector3(width,height*.9,.055),Vector3(0,height*1.45,.02-depth*.5),Color("eeeeee"))
		var cases=[["sit_chair",Vector3(2,1.1,0),Vector3(0,.7,.05)], ["sit_chair",Vector3(1.8,1.3,2),Vector3(0,.7,.05)], ["sit_chair",Vector3(0,.25,2),Vector3(0,.65,0)], ["sit_ground",Vector3(1.7,1.3,2),Vector3(0,.5,0)], ["death",Vector3(1.5,1.2,2),Vector3(0,.35,0)]]
		for i in cases.size():
			chair.visible=i<3;model.play(cases[i][0],"front",true);model.pose_at(2.4)
			camera.position=cases[i][1];camera.look_at(cases[i][2])
			camera.size=2.0
			if i==4:
				var focus:Vector3=(model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones.hips)).origin
				camera.size=2.7;camera.position=focus+Vector3(1.5,1.2,2);camera.look_at(focus)
			for frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(Paths.review_path("character_3d/seating_%s_%d.png"%[gender,i]))
		chair.free()
	model.free();quit()
