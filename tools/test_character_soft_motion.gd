extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var model:=Model.new();root.add_child(model);model.set_process(false)
	model.configure("female",{"bust_size":.7},{"Clothing1":1})
	var motion=model.imported_rig.soft_motion
	assert(motion.indices.size()==2 and model.skeleton.get_bone_count()==67)
	for category in ["Body","Clothing1","BaseTop"]:
		var affected:=0
		for mesh in model.gear[category]:
			if mesh.name=="Face":continue
			var bindings:Array[int]=[]
			for i in range(mesh.skin.get_bind_count()):
				if str(mesh.skin.get_bind_name(i)).begins_with("SecondaryBreast") or mesh.skin.get_bind_bone(i) in motion.indices:bindings.append(i)
			assert(bindings.size()==2,"Each garment must bind both secondary bones")
			for surface in range(mesh.mesh.get_surface_count()):
				var arrays=mesh.mesh.surface_get_arrays(surface)
				for i in range(arrays[Mesh.ARRAY_BONES].size()):
					if arrays[Mesh.ARRAY_BONES][i] in bindings and arrays[Mesh.ARRAY_WEIGHTS][i]>.01:affected+=1
		assert(affected>20,"Body and garments need real nonzero weights")
	for action in ["walk","dash"]:
		model.play(action,"front",true)
		var peak:=0.0
		for frame in range(240):
			model._process(1.0/60)
			peak=maxf(peak,absf(motion.offsets[0].y))
			assert(motion.offsets[0].is_finite() and absf(motion.offsets[0].y)<=.08501)
		assert(peak>.02,"Movement must have visible secondary motion")
		assert(not motion.offsets[0].is_equal_approx(motion.offsets[1]),"Left/right springs must have independent follow-through")
		print(action," vertical peak: ",peak)
	var before:Vector3=motion.offsets[0]
	model.play("idle","front",false)
	assert(motion.offsets[0]==before,"Stopping must not reset secondary motion")
	for frame in range(120):model._process(1.0/60)
	assert(motion.offsets[0].length()<.0001,"Spring must settle after stopping")
	model.set_equipment({})
	assert(model.imported_rig.soft_motion==motion,"Changing clothes must preserve spring state")
	var npc:=Model.new();root.add_child(npc);npc.set_process(false)
	npc.configure("female",{"bust_size":.2},{"Clothing1":1})
	assert(npc.imported_rig.soft_motion!=motion and npc.skeleton!=model.skeleton)
	npc.play("dash","right",true)
	for frame in range(30):npc._process(1.0/60)
	assert(motion.offsets[0].length()<.0001,"NPC animation must not mutate another character")
	model.configure("male",{}, {})
	assert(model.imported_rig.soft_motion.indices.is_empty())
	print("PASS weighted secondary bones, independent springs, settling, gear and NPC instance isolation")
	quit()
