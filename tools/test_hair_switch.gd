extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(not DirAccess.dir_exists_absolute("res://assets/characters/hair"))
	for gender in ["female","male"]:
		var model:=Model.new();root.add_child(model);model.set_process(false)
		model.configure(gender,{"part_ids":{"FrontHair1":15},"hair_on":true,"hair_row":1206},{})
		model.imported_rig.prepare_hair_choices(model)
		var rig=model.rig;var skeleton=model.skeleton
		for pass_id in range(2):
			for id in [10,11,12,13,14,15,0,1]:
				var start:=Time.get_ticks_usec()
				model.configure(gender,{"part_ids":{"FrontHair1":id},"hair_on":true,"hair_row":1132},{})
				var ms:float=(Time.get_ticks_usec()-start)/1000.0
				print("SWITCH ",gender," pass=",pass_id," style=",id," ms=",ms)
				assert(model.rig==rig and model.skeleton==skeleton)
				assert(skeleton.get_bone_count()==70)
				var count:=0
				for mesh in model.gear.Hair:
					if mesh.visible:
						count+=1
						if id>=10:assert(str(mesh.name).begins_with("Hair_%d_"%id))
				assert((count==0)==(id==0))
				model._process(.016)
		model.free()
	print("PASS external hair, cached switching, stable body/skeleton, visible meshes")
	quit()
