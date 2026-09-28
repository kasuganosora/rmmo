extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func recipe(id:int,row:int=18)->Dictionary:
	return {"body_model":"female_base_v2","part_ids":{"FrontHair1":id},"hair_on":true,"hair_row":row}
func run()->void:
	var a:=Model.new();a.body_type="female";a.appearance=recipe(201);root.add_child(a)
	var b:=Model.new();b.body_type="female";b.appearance=recipe(201,25);root.add_child(b)
	a.set_process(false);b.set_process(false)
	var body:Node3D=a.axis_rig.body
	var hair:Node3D=a.axis_rig.hair
	var original_body:int=body.get_instance_id()
	var original_mesh:int=body.mesh_instance.get_instance_id()
	var bones:int=a.skeleton.get_bone_count()
	assert(bones==80)
	assert(hair.materials[0]!=b.axis_rig.hair.materials[0])
	var other_color:Color=b.axis_rig.hair.materials[0].get_shader_parameter("hair_color")
	a.play("walk","front",true);a._from_rotations.clear();a.pose_at(.4)
	var source_id:int=hair.source.get_instance_id()
	a.configure("female",recipe(201,30),{})
	assert(hair.source.get_instance_id()==source_id)
	assert(b.axis_rig.hair.materials[0].get_shader_parameter("hair_color")==other_color)
	for id in [202,203,201,0,203]:
		a.configure("female",recipe(id),{})
		assert(hair.selected==id)
		assert(body.get_instance_id()==original_body and body.mesh_instance.get_instance_id()==original_mesh)
		assert(a.skeleton.get_bone_count()==bones and a.action=="walk")
		assert((hair.source==null)==(id==0))
	# The ponytail ribbon must retain its source shading and never inherit hair dye.
	var accessory:StandardMaterial3D
	for mesh:MeshInstance3D in hair.source.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			if mesh.get_active_material(i) is StandardMaterial3D:accessory=mesh.get_active_material(i)
	assert(accessory!=null and accessory.albedo_texture!=null,"Source ribbon texture missing from baked runtime")
	var texture_id:int=accessory.albedo_texture.get_instance_id()
	var accessory_color:Color=accessory.albedo_color
	var pixels:Image=accessory.albedo_texture.get_image()
	assert(pixels.get_width()>1 and pixels.get_height()>1)
	assert(not pixels.get_pixel(256,256).is_equal_approx(pixels.get_pixel(400,100)),"Ribbon shading was flattened")
	a.configure("female",recipe(203,35),{})
	assert(accessory.albedo_color==accessory_color and accessory.albedo_texture.get_instance_id()==texture_id)
	var original_recipe:=recipe(203)
	original_recipe.hair_on=false
	a.configure("female",original_recipe,{})
	for mat:ShaderMaterial in hair.materials:
		for parameter in ["hair_color","hair_color2","hair_color3"]:
			assert(mat.get_shader_parameter(parameter)==mat.get_meta("source_"+parameter),"Original source palette did not restore")
	for clip in ["idle","walk","cast","attack","sit_chair","death"]:
		a.play(clip,"front",true);a._from_rotations.clear();a.pose_at(a.action_duration()*.5)
		var expected:Transform3D=body.solved_bones[hair.head_index]*body.rests.head.affine_inverse()
		expected.origin+=body.root_offset
		assert(hair.transform.is_equal_approx(expected),"Hair did not consume final head snapshot")
		assert(hair.transform.origin.is_finite())
	# Explicit head turn tests the attachment independently of whole-body rotation.
	body.set_angles({"head":Vector3(12,35,-8)})
	var delta:Transform3D=body.solved_bones[hair.head_index]*body.rests.head.affine_inverse()
	assert(hair.transform.basis.is_equal_approx(delta.basis))
	assert(hair.fit_bake_error<.00001)
	a.free();b.free()
	for frame in 3:await process_frame
	print("PASS: source hair switch/remove, palette isolation, source ribbon texture/dye isolation, no body rebuild, 80 unchanged body bones, 6 actions and explicit head rotation")
	quit()
